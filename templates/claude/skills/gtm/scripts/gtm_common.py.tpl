"""Gedeelde helpers voor de GTM-scripts. Geeft nooit de private key weer."""
import json
import os
import sys

DEFAULT_KEY_FILE = "~/.config/labelvier/lv-reporting.json"
ENV_VAR = "GTM_SERVICE_ACCOUNT_FILE"
READONLY_SCOPES = ["https://www.googleapis.com/auth/tagmanager.readonly"]
GA4_READONLY_SCOPES = ["https://www.googleapis.com/auth/analytics.readonly"]


def fail(message, code=1):
    print(f"FOUT: {message}", file=sys.stderr)
    sys.exit(code)


def key_path():
    return os.path.expanduser(os.environ.get(ENV_VAR) or DEFAULT_KEY_FILE)


def build_service(api, version, scopes):
    """Bouwt een Google API-client (discovery) met de opgegeven scopes. Geeft (service, client_email) terug."""
    path = key_path()
    if not os.path.isfile(path):
        fail(f"sleutelbestand niet gevonden: {path} (zet {ENV_VAR} of plaats het bestand op het standaardpad)")
    try:
        with open(path) as fh:
            info = json.load(fh)
    except (OSError, ValueError) as exc:
        fail(f"sleutelbestand is geen geldige JSON ({type(exc).__name__})")
    if info.get("type") != "service_account" or not info.get("client_email") or not info.get("private_key"):
        fail("sleutelbestand lijkt geen geldig service account (type/client_email/private_key ontbreekt)")

    try:
        from google.oauth2 import service_account
        from googleapiclient.discovery import build
    except ImportError:
        fail("google-auth / google-api-python-client niet geïnstalleerd: pip install -r requirements.txt")

    creds = service_account.Credentials.from_service_account_info(info, scopes=scopes)
    service = build(api, version, credentials=creds, cache_discovery=False)
    return service, info["client_email"]


def load_service(scopes=None):
    """Bouwt de Tag Manager API-client. Geeft (service, client_email) terug."""
    return build_service("tagmanager", "v2", scopes or READONLY_SCOPES)


def list_all(list_fn, key, **kwargs):
    """Haalt alle pagina's van een list-call op (nextPageToken) en geeft de items terug."""
    items = []
    token = None
    while True:
        params = dict(kwargs)
        if token:
            params["pageToken"] = token
        response = list_fn(**params).execute()
        items.extend(response.get(key, []))
        token = response.get("nextPageToken")
        if not token:
            return items


def explain_http_error(exc):
    """Zet een HttpError om in een herleidbare melding (zonder secrets)."""
    status = getattr(exc.resp, "status", "?")
    text = str(exc)
    if status == 403 and ("analyticsadmin" in text.lower()) and (
            "has not been used" in text or "disabled" in text or "accessNotConfigured" in text):
        return "403: de Google Analytics Admin API staat niet aan in het GCP-project. Schakel 'Google Analytics Admin API' in."
    if status == 403 and ("analyticsdata" in text.lower()) and (
            "has not been used" in text or "disabled" in text or "accessNotConfigured" in text):
        return "403: de Google Analytics Data API staat niet aan in het GCP-project. Schakel 'Google Analytics Data API' in."
    if status == 403 and ("accessNotConfigured" in text or "has not been used" in text or "disabled" in text):
        return "403: de Tag Manager API staat niet aan in het GCP-project. Schakel 'Tag Manager API' in."
    if status == 403:
        return ("403: geen toegang. Is het service account als gebruiker toegevoegd aan het GTM-account/de container "
                "(GTM) of aan de GA4-property/het account (GA4, rol Viewer)?")
    if status == 401:
        return "401: authenticatie mislukt (sleutel ingetrokken of ongeldig?)."
    return f"HTTP {status}: {text[:300]}"
