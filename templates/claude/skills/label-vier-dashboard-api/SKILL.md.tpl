---
name: label-vier-dashboard-api
description: Lees en beheer data in het Label Vier Dashboard (websites, plugins, WordPress core-versies, logs, contactpersonen) via de REST API v1. Gebruik bij vragen over welke websites een bepaalde plugin of versie draaien, welke plugin-updates beschikbaar zijn, Lighthouse/PageSpeed-scores, update-logs, of het opzoeken, toevoegen, wijzigen en verwijderen van contactpersonen (bv. noodcontact) per website.
---

<!-- labelvier-ai-version: 1 -->
<!-- Bron: resources/api-doc/api-v1.yaml in de dashboard-repo. Werk deze skill bij als de API verandert. -->

# Label Vier Dashboard API

REST API (v1) van het monitoring-dashboard voor WordPress-websites. Antwoorden zijn JSON.

## Setup

Twee omgevingsvariabelen:

- `LV_DASHBOARD_URL` — standaard `https://dashboard.labelvier.nl` (overschrijf voor staging)
- `LV_DASHBOARD_API_KEY` — jouw API key, opgeslagen in `~/.claude/.env` (zet `labelvier ai claude install` daar voor je neer)

Key aanmaken: dashboard → Nova → gebruikersmenu → **API keys** → actie **Create API key**. De key is maar één keer zichtbaar. Kies read-only (`read`) of read/write (`read` + `write`).

Regels:
- Print of log de key nooit en commit hem nergens.
- Gebruik read-only tenzij schrijven echt nodig is.
- Staat `LV_DASHBOARD_API_KEY` niet gezet? Vraag de gebruiker om er een aan te maken, verzin niets.

## Requests

```bash
# Lees de key/URL uit ~/.claude/.env als ze niet al in de omgeving staan (zonder de waarde te printen).
_lv_env() { sed -n "s/^$1=//p" "$HOME/.claude/.env" 2>/dev/null | tail -n 1 | sed -e "s/^'\(.*\)'\$/\1/" -e 's/^"\(.*\)"$/\1/'; }
LV_DASHBOARD_API_KEY="${LV_DASHBOARD_API_KEY:-$(_lv_env LV_DASHBOARD_API_KEY)}"
LV_DASHBOARD_URL="${LV_DASHBOARD_URL:-$(_lv_env LV_DASHBOARD_URL)}"
LV_DASHBOARD_URL="${LV_DASHBOARD_URL:-https://dashboard.labelvier.nl}"
curl -s -H "Authorization: Bearer $LV_DASHBOARD_API_KEY" -H "Accept: application/json" \
  "$LV_DASHBOARD_URL/api/v1/websites?search=dushi"
```

Alle voorbeelden hieronder gaan uit van die setup-regels. Elke Bash-call start een nieuwe shell, dus zet ze bovenaan elke call.

`Accept: application/json` is verplicht. Zonder die header krijg je bij fouten een redirect of HTML terug. Gebruik `jq` om te filteren.

## Endpoints

| Methode | Pad | Ability | Filters |
|---------|-----|---------|---------|
| GET | `/websites` | read | `search` (naam, slug of URL) |
| GET | `/websites/{id}` | read | — (incl. `plugins` met `pivot` en `contacts`) |
| GET | `/plugins` | read | `search` |
| GET | `/plugins/{id}` | read | — (incl. `websites` met `pivot`) |
| GET | `/cores` | read | — (WordPress core-versies) |
| GET | `/logs` | read | `website_id`, `plugin_id`, `log_type` (`error` of `success`) |
| GET | `/logs/{id}` | read | — |
| GET | `/contacts` | read | `website_id`, `type` |
| GET | `/contacts/{id}` | read | — |
| POST | `/contacts` | write | — |
| PUT/PATCH | `/contacts/{id}` | write | — |
| DELETE | `/contacts/{id}` | write | — |

Lijsten zijn gepagineerd; detail-endpoints geven `{"data": {...}}`. Belangrijke velden:
- Website: `id`, `name`, `slug`, `website_url`, `core` (met `version`), `accessibility`, `best_practices`, `performance`, `seo` (0–100), `success_rate`, `last_synced_at`
- Plugin: `id`, `name`, `slug`, `version` (laatst bekende versie)
- `pivot` (plugin op website): `current_version`, `update_version` (gevuld = update beschikbaar), `status` (o.a. `active`, `inactive`, `must-use`, `dropin`)
- Log: `log_type`, `message`, `old_version`, `new_version`, `website_id`, `plugin_id`, `core_id`, `created_at`
- Contact: `id`, `website_id`, `name`, `email`, `phone_number`, `type`

## Paginatie

`?page=1&per_page=100` (max 100). Het antwoord bevat `data`, `current_page`, `last_page`, `total` en `next_page_url`. Haal alles op door `next_page_url` te volgen tot die `null` is:

```bash
url="$LV_DASHBOARD_URL/api/v1/websites?per_page=100"
while [ "$url" != "null" ]; do
  page=$(curl -s -H "Authorization: Bearer $LV_DASHBOARD_API_KEY" -H "Accept: application/json" "$url")
  echo "$page" | jq -c '.data[]'
  url=$(echo "$page" | jq -r '.next_page_url')
done
```

## Contactpersonen schrijven

Vereist een key met `write`. Types: `emergency`, `general` (standaard), `administrative`.

```bash
# Aanmaken (verplicht: website_id, name, email)
curl -s -X POST -H "Authorization: Bearer $LV_DASHBOARD_API_KEY" -H "Accept: application/json" \
  -H "Content-Type: application/json" "$LV_DASHBOARD_URL/api/v1/contacts" \
  -d '{"website_id": 12, "name": "Jan Jansen", "email": "jan@example.com", "phone_number": "0612345678", "type": "emergency"}'

# Wijzigen: alleen de meegestuurde velden veranderen
curl -s -X PATCH -H "Authorization: Bearer $LV_DASHBOARD_API_KEY" -H "Accept: application/json" \
  -H "Content-Type: application/json" "$LV_DASHBOARD_URL/api/v1/contacts/34" \
  -d '{"phone_number": "0687654321"}'

# Verwijderen
curl -s -X DELETE -H "Authorization: Bearer $LV_DASHBOARD_API_KEY" -H "Accept: application/json" \
  "$LV_DASHBOARD_URL/api/v1/contacts/34"
```

Voor je iets wijzigt of verwijdert: zoek eerst het contact op en laat zien welk contact het wordt. **Vraag altijd bevestiging aan de gebruiker vóór een DELETE** (en bij het overschrijven van bestaande gegevens).

## Veelvoorkomende taken

**Welke websites hebben een update voor plugin X?**
1. `GET /plugins?search=x` → pak het `id` van de juiste plugin (bij meerdere treffers: vraag welke).
2. `GET /plugins/{id}` → filter `websites` op `pivot.update_version != null`; toon website-naam, `pivot.current_version` en `pivot.update_version`.

**Welke websites draaien plugin X in versie Y?** Zelfde als hierboven, filter op `pivot.current_version`.

**Noodcontact van website Y**
1. `GET /websites?search=y` → `id`
2. `GET /contacts?website_id={id}&type=emergency`

**Recente fouten van een website**
`GET /logs?website_id={id}&log_type=error` (nieuwste eerst; de log bevat plugin-/core-id en oude/nieuwe versie).

**Welke websites zitten op een oude WordPress-versie?**
`GET /cores` voor de nieuwste versie, vergelijk met `websites[].core.version` uit `GET /websites?per_page=100`.

**Slechtste PageSpeed-scores**
`GET /websites?per_page=100`, sorteer lokaal op `performance`, `seo`, `accessibility` of `best_practices` (waarden kunnen `null` zijn).

## Fouten

| Status | Betekenis | Actie |
|--------|-----------|-------|
| 401 | Key ontbreekt, is ongeldig of ingetrokken | Controleer `LV_DASHBOARD_API_KEY` en de `Accept`-header; maak zo nodig een nieuwe key |
| 403 | Key mist de ability (bv. read-only key op POST/PATCH/DELETE) | Vraag een read/write key aan |
| 404 | Id bestaat niet | Zoek het id opnieuw op via de lijst met `search` |
| 422 | Validatiefout: `{"message": ..., "errors": {veld: [..]}}` | Corrigeer de genoemde velden |

## Volledige spec

De OpenAPI-spec en een interactieve viewer staan achter authenticatie. De spec is ook met je API key op te halen:

```bash
curl -s -H "Authorization: Bearer $LV_DASHBOARD_API_KEY" "$LV_DASHBOARD_URL/api-docs/openapi"
```

De viewer staat op `$LV_DASHBOARD_URL/api-docs` (in de browser, na inloggen). Deze skill bevat alle endpoints, dus de spec is meestal niet nodig.
