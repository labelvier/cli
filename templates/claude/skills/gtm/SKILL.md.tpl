---
name: gtm
description: Google Tag Manager bekijken en (later) uitrollen, en Google Analytics 4 alleen-lezen uitlezen, via het Label Vier service account. Gebruik bij vragen over GTM-accounts, containers, tags, triggers of variabelen, of over GA4-cijfers zoals best bekeken pagina's.
---

<!-- labelvier-ai-version: 1 -->

# GTM-skill

Werkt via het Google service account `lv-reporting` en de Tag Manager API v2. Geïnstalleerd door `labelvier ai claude install` in `~/.claude/skills/gtm`.

## Sleutel

- Pad: env `GTM_SERVICE_ACCOUNT_FILE`, standaard `~/.config/labelvier/lv-reporting.json`.
- De sleutel wordt niet door de CLI of deze skill verspreid en staat **nooit** in een repo.

## Scopes

- Nu: `https://www.googleapis.com/auth/tagmanager.readonly`
- GA4: `https://www.googleapis.com/auth/analytics.readonly`
- Voor uitrol later: `tagmanager.edit.containers`, `tagmanager.edit.containerversions`, `tagmanager.publish`

## Scripts

De Python-omgeving staat in `~/.claude/skills/gtm/.venv`. Ontbreekt die of mislukte de install, draai dan `labelvier ai claude install` opnieuw (of handmatig: `python3 -m venv ~/.claude/skills/gtm/.venv && ~/.claude/skills/gtm/.venv/bin/pip install -r ~/.claude/skills/gtm/requirements.txt`).

- `~/.claude/skills/gtm/.venv/bin/python ~/.claude/skills/gtm/scripts/gtm_check.py [--domain labelvier.nl]`: toont het service account, de GTM-accounts en containers (naam, GTM-ID, domein).
- `~/.claude/skills/gtm/.venv/bin/python ~/.claude/skills/gtm/scripts/gtm_export.py --container accounts/<id>/containers/<id> [--out exports/]`: read-only export van workspaces, tags, triggers en variabelen.

## GA4 (alleen-lezen)

Vereist dat in het GCP-project de **Google Analytics Admin API** en **Google Analytics Data API** aan staan, en dat het service account als Viewer is toegevoegd aan het GA4-account/de property.

- `~/.claude/skills/gtm/.venv/bin/python ~/.claude/skills/gtm/scripts/ga4_find_property.py [--measurement-id G-XXXXXXX]`: zoekt het numerieke property-ID bij een measurement-ID; zonder argument alle zichtbare accounts en properties.
- `~/.claude/skills/gtm/.venv/bin/python ~/.claude/skills/gtm/scripts/ga4_top_pages.py --property <id> --start YYYY-MM-DD --end YYYY-MM-DD [--path-contains /blog/] [--limit 10]`: best bekeken pagina's (pagePath, pageTitle, screenPageViews), aflopend. Weergaven worden per pad opgeteld; bij meerdere titels voor één pad toont het script de titel met de meeste weergaven. Datums: YYYY-MM-DD, `today`, `yesterday` of `NdaysAgo`; `--property` moet numeriek zijn (een `G-…` measurement-ID eerst omzetten met `ga4_find_property.py`). Let op: een overzichtspagina zoals `/blog/` telt mee in het filter.

## Veiligheidsregels

- Nooit de private key of het sleutelbestand printen, loggen of committen. Alleen `client_email` mag getoond worden.
- Niet publiceren of wijzigen in GTM zonder expliciet akkoord van Eric of Vincent.
- Foutmeldingen: 403 `accessNotConfigured` = Tag Manager API staat uit in het GCP-project; lege accountlijst = service account is niet als gebruiker aan GTM toegevoegd. Voor GA4: 403 met Admin/Data API = die API staat uit in het GCP-project; lege lijst of 403 zonder dat = service account heeft geen toegang tot de property.
