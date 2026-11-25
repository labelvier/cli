#!/usr/bin/env python3
"""Controleert of het service account bij Google Tag Manager kan.

Gebruik:
  ~/.claude/skills/gtm/.venv/bin/python ~/.claude/skills/gtm/scripts/gtm_check.py [--domain labelvier.nl]

Toont het client_email (nooit de private key), de GTM-accounts en containers.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gtm_common import ENV_VAR, explain_http_error, key_path, list_all, load_service  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--domain", help="toon alleen containers waarvan naam of domein dit bevat")
    args = parser.parse_args()

    service, email = load_service()
    from googleapiclient.errors import HttpError  # pas na load_service: dan is de dependency gecontroleerd

    print(f"Sleutelbestand: {key_path()} (via {ENV_VAR} of standaardpad)")
    print(f"Service account: {email}")

    try:
        accounts = list_all(service.accounts().list, "account")
    except HttpError as exc:
        print(f"FOUT: {explain_http_error(exc)}", file=sys.stderr)
        return 2

    if not accounts:
        print("Geen GTM-accounts zichtbaar: het service account is (nog) niet als gebruiker "
              "toegevoegd aan een GTM-account.")
        return 3

    needle = (args.domain or "").lower()
    found = 0
    for account in accounts:
        print(f"\nAccount: {account.get('name')} ({account['accountId']})")
        try:
            containers = list_all(service.accounts().containers().list, "container", parent=account["path"])
        except HttpError as exc:
            print(f"  FOUT bij containers: {explain_http_error(exc)}")
            continue
        for c in containers:
            domains = c.get("domainName", [])
            hay = " ".join([c.get("name", "")] + domains).lower()
            if needle and needle not in hay:
                continue
            found += 1
            print(f"  - {c.get('name')} | {c.get('publicId')} | domein: {', '.join(domains) or '-'} "
                  f"| {c.get('path')}")
    if needle and not found:
        print(f"\nGeen container gevonden voor '{args.domain}'.")
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
