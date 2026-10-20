# SiteGround automation — findings

Goal: stop clicking through my.siteground.com to create and configure sites. We automate
through the internal APIs that the SiteGround web apps use. Node.js (built-in `fetch`,
only Playwright for the login step) so it can later run hosted.

## How to use

Lives in labelvier/cli as `node/siteground` (was the separate labelvier/siteground repo). Run it via
`labelvier siteground <command>`: `inc/siteground.sh` checks node >= 20, runs `npm ci` when the lockfile
changed, installs Playwright's Chromium before `login`, and forwards everything to `src/cli.js`.
Point `SG_CLI_DIR` at another checkout to run that one instead.

```bash
labelvier siteground login                           # browser opens, log in incl. 2FA ("Stay logged in" is ticked for you)
labelvier siteground accounts                        # plans with site count + disk usage
labelvier siteground create-site                     # asks for domain, plan, app, extras step by step
labelvier siteground create-site --domain x.labelvier.dev --account Hamerkop --app wordpress \
  --memcached --ssl --https --no-ssh-key --yes       # fully non-interactive
labelvier siteground site:info x.labelvier.dev
labelvier siteground site:ssl x.labelvier.dev        # after DNS points to the server
labelvier siteground site:memcached|site:ssh-key|site:ssh|site:db x.labelvier.dev
labelvier siteground site:cron x.labelvier.dev [--add "<command>" --at "* * * * *" | --remove <id>]
labelvier siteground account:stats Albatros [--days 31 --top 15 --sort cpu|exec]   # which site eats CPU / executions
labelvier siteground account:autoscale Albatros      # autoscale settings + resources added by autoscaling
labelvier siteground site:stats yoni.care [--days 31]  # CPU seconds + executions per day for one site
```

Without the wrapper: `npm ci && npx playwright install chromium`, then `node src/cli.js <command>`.

Every missing option is asked in the terminal (the PHP version always).
After an SSH key is authorized it offers a Host alias in `~/.ssh/config` (default: first label of
the domain). That runs `labelvier ssh alias <name> <host> <user> 18765 <private key>` with stdin
closed, so the config format stays the same as the rest of the team's tooling. Progress is shown with a
spinner on stderr ([src/spinner.js](src/spinner.js)); without a TTY it prints plain `…`/`✔` lines. Without a terminal (CI/hosted) missing
options fall back to safe defaults or fail with "Missing --x".

Hidden demo mode for screen recordings: `create-site --demo` (or `SG_DEMO=1`). All reads and
checks hit SiteGround for real, every write is blocked, and creating the site plus the Site Tools steps
are simulated with delays. The "already exists" check is skipped, so you can "create" an existing site.
IPs, `*.sgvps.net` hosts, SSH users and account/site ids are masked on stdout/stderr; nothing is
written to `.credentials/` or `~/.ssh/config`. See [src/demo.js](src/demo.js).

Secrets live in `SG_STATE_DIR` (default `~/.config/labelvier/siteground`), never in the code checkout:
- `.session.json`: client-area tokens (chmod 600). For hosted use pass `SG_REFRESH_TOKEN`.
- `.credentials/<domain>.json`: generated WP admin and database passwords (chmod 600).
- `.browser-profile/`: Playwright profile for the login.
The wrapper copies `.session.json` and `.credentials/` once from an old `~/Sites/siteground` checkout.
Never commit, paste or log these.

Code: [src/client.js](src/client.js) (client area API), [src/sitetools.js](src/sitetools.js)
(Site Tools API), [src/actions.js](src/actions.js) (reusable steps), [src/cli.js](src/cli.js),
[src/prompt.js](src/prompt.js), [src/login.js](src/login.js).

Test site: `sgdummy.labelvier.dev` on Develop - Hamerkop was used for experiments and has been
removed again (2026-10-14). Create a new dummy when needed.
`siteground.labelvier.dev` is refused by SiteGround (`translate.core.form.new_domain.subdomain.unavailable_domain`):
domains containing "siteground" are blocked.

## Two APIs

| | Client area | Site Tools |
|---|---|---|
| Used by | my.siteground.com | tools.siteground.com |
| Base | `https://uapi.siteground.com/v1` | `https://<server>.sgvps.net/api-sgcp/v00` |
| Auth | client JWT (1h) + refresh JWT | site JWT from `GET /auth/sites/{siteId}/token` (uapi) |
| Scope | accounts, orders, sites list, wizard | one site: domains, SSL, cache, SSH, DB, PHP, … |

Both: `Authorization: Bearer <jwt>`, `Accept: application/json`, JSON bodies, no cookies/CSRF.
Envelope: `{ "status": 200, "message": …, "data": … }`.

Documentation = the SPA bundles. Every endpoint is a one-liner, grep for paths:
- `https://my.siteground.com/build_<ts>_v<ver>/main.js` (client area, e.g. `ze(t)("/sites/wizard","POST",body)`)
- `https://tools.siteground.com/build_<ts>_v<ver>/index.js` (Site Tools; resource map `XYZ:{endpoint:"/xyz",…}`)

## Client area API (uapi)

### Auth / session

| What | Details |
|---|---|
| Login | `login.siteground.com` (separate app, reCAPTCHA + 2FA, "Stay logged in" checkbox). Hands over via `?hash=…`. |
| Storage | SPA keeps `token` + `refreshToken` in `localStorage["ua_session"].session`. |
| Access token | JWT, `tokenType: access`, **1 hour**. |
| Refresh token | JWT, `tokenType: refresh`, **24 hours** without "Stay logged in"; **not rotated**. Effect of "Stay logged in" on the lifetime: to verify on the next login. |
| Refresh | `POST /auth/refresh-client-token` body `{"refresh_token":"…"}` (no Bearer) → `data.client_token`. |

### Accounts (hosting plans)

- `GET /accounts?sort_field=created&sort_order=DESC` → `data.accounts[]`: id, name, `server.ip/location`,
  `can_create_sites`, `status`, `plan_description`. **`quota_info.usage` is the number of sites**, not disk.
- `GET /accounts/{id}` → plan + `websites[]`.
- `GET /account/{id}/stats/disk` → `{ total, limit, other, site_stats_responses[{domain,value}] }` in MB.
- `GET /account/{id}/stats/{metric}?fromDate=<unix>&toDate=<unix>&step=h|d|m` for `cpu_seconds` and
  `program_executions` → `{ limit, points[], aggregated_site_stats_responses[{id,domain,points[]}] }`.
  Daily points are stamped 23:59:59 UTC; the range is also padded with zero points at other timestamps.
  Cloud plans also have `cpu_core_usage` and `ram`, which need `&timeZone=…&clientTimeZone=…` and
  `step=m3` (20 min); the core usage response has no per-site series (`limits_list` = cores).
- Cloud autoscale: `GET /accounts/{id}/autoscalesettings` (`cpu`/`mem`: `current_value`, `current_cap`,
  `current_threshold` %), `GET /accounts/{id}/autoscalelogs` (added units with `date_added`/`expiration_date`).
  `POST /accounts/{id}/autoscalesettings` changes them (not used).

| Name | Account id | Server |
|---|---|---|
| Basis - Albatros | `TFE3L1oza01JUT09` | c125667.sgvps.net / 35.214.165.2 |
| Basis - Aalscholver | `TFFIK1lua0tKUT09` | c1112626.sgvps.net / 35.214.192.38 |
| Compleet - Zeearend | `TFE3L1pIZ0ZMZz09` | c125835.sgvps.net / 35.214.251.239 |
| Develop - Hamerkop | `TFFEeVkzOEZJQT09` | c1103939.sgvps.net / 35.214.252.94 |

`*.labelvier.dev` has a wildcard A record (TransIP) to Hamerkop, so new subdomains resolve at once.

### Website wizard

1. `GET /domain/checkexisting/{accountId}/{domain}` → `registered`, `client_is_owner_of_domain` (400 with
   `validation.domain` when the name is not allowed).
2. `GET /sites/wizard/step2/{accountId}/w1` → installable apps (`other[].name`, `is_paid`) + form schema.
3. `POST /sites/wizard/step3/{accountId}` body `{"order":{"step1":…,"step2":…}}` → upsell list only, creates nothing.
4. `POST /sites/wizard` body:
   ```json
   {"order":{
     "step1":{"account":"<accountId>","domain_type":"e",
              "domains":[{"domain":"x.labelvier.dev","is_primary":1}],"datacenter":"","site":""},
     "step2":{},
     "step3":{"extras":{}}}}
   ```
   → `data.id` = order id. `step2` for an app:
   `{"installation_type":"n","installation_candidate":{"name":"WordPress","email":"…","password":"…"}}`
   (`name` also `WooCommerce`, `Joomla`, …). The UI also sends `payment.additional` and `marketingInfo`; not needed.
5. Poll `GET /order/{orderId}/status` (UI: every 10s) → `data.order_item_activations[]`, `status`:
   `-1` failed, `0` pending, `1` started, `100` done. Items: `site_activation` (≤10s, `exposed_data.site_id`),
   plus `cms_install` for apps (~40s, `exposed_data.admin_url` = one-time auto-login link, treat as secret).

`domain_type`: `e` existing domain, `n` register new domain (costs money), `t` temporary `*.sg-host.com`.

### Other

- `GET /sites/list` → `websites[]` (id, domain, account_id, cms, status, server).
- `GET /sites` → `[{id, domain, api_url, …}]` (`api_url` = Site Tools host).
- `GET /sites/{id}/server-data`, `GET /sites/{id}/delete` (pre-check), `DELETE /sites/{id}` (not used yet).

## Site Tools API (`https://<api_url>/api-sgcp/v00`)

Token: `GET /auth/sites/{siteId}/token` on uapi → `data.site_token` (claims `api_url`, `cts`, `vsec`;
renew when less than a quarter of `vsec` is left).

Conventions (resource style): `GET /x` list, `POST /x` create, `PUT /x/{id}` update, `DELETE /x/{id}`.
Writes return `task_id`; when the HTTP status is `202`, poll `GET /task/{id}` until
`options.completed !== 0`, success when `response.err_code == 0`. All calls below returned 200 directly.

| Feature | Call | Notes |
|---|---|---|
| Meta / limits | `GET /endpoint` | `data.features.username` = SSH user (e.g. `u114-…`), PHP limits, quotas |
| Domains | `GET /domain-all` | `id`, `name`, `main`, `cert_id`, `sg_pointed`, `config.ssh_host`, `settings` |
| Force HTTPS | `PUT /domain-all/{id}` `{"settings":{"https_enforce":1,"https_rewrite_links":0}}` | needs a certificate |
| SSL list | `GET /ssl` | `not_after`, `issuer`, `info.cert.le` |
| Let's Encrypt | `POST /ssl-le` `{"domain_id":1}` | covers domain + www. UI field `generate` is rejected ("Unsupported input field"), wildcard unknown |
| Memcached | `GET /uservice`; `POST /uservice` `{"type":"memcached","settings":{}}`; `DELETE /uservice/{id}` | 127.0.0.1:11211 |
| SSH keys | `GET /ssh`; `POST /ssh` `{"key_pub":"ssh-ed25519 …","comment":"…"}`; `DELETE /ssh/{id}` | login `ssh -p 18765 <username>@<ssh_host>` |
| SSH key generate | `POST /ssh-key` `{"comment","password"}` | SiteGround generates the pair (not used) |
| MySQL | `POST /db-mysql_db` `{"label"}`; `POST /db-mysql_user` `{"label","password"}`; `POST /db-mysql_grant` `{"db_id","dbuser_id","grants":{"all":1}}` | names are generated (`db…`, `u…`) |
| Cron | `GET /cron`; `POST /cron` `{"cmd","min","hour","day","mon","dow"}`; `PUT /cron/{id}` (same body); `DELETE /cron/{id}` | crontab fields as strings; the UI sends dow `7` as `0`. Only route to cron on SiteGround: SSH has no `crontab`. Notification email: `GET/POST /cron-notify` (not used). GET + payload taken from the bundle; POST/DELETE not yet verified live |
| PHP versions | `GET /php-version` | `[{id: 83, version: "PHP 8.3.35", default?, recommended?, mod_php}]` |
| PHP version (main domain) | `PUT /uservice/{apacheId}` `{"settings":{"php_version":83}}`; `{"settings":{}}` = managed | apache uservice from `GET /uservice`. Other domains: `PUT /domain/{id}` `{"php_version":83}` (0 = managed), not used |

Other resources in the bundle: backup, dns-*, email*, ftp, location-* (redirects, protect, IP block),
php-variable/extension, wordpress (incl. staging), webstats, errorlogs/accesslogs.

## Research method (for next time)

- Client area: in the browser pane monkey-patch `window.fetch` to log method/url/body/response, plus a
  guard that rejects non-GET calls to uapi. Walk a wizard to the end and capture the final payload
  without side effects. `read_network_requests` does not show these fetches.
- Site Tools: download `index.js` from tools.siteground.com and grep the resource map
  (`XYZ:{endpoint:"/xyz"}`), form field names (`name:"…"` near the form constant) and `createItem(...)` bodies.
  Then test on `sgdummy.labelvier.dev`.
- The browser-pane session is separate from the Playwright session and expires on its own.
