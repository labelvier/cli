# Uptime Kuma CLI

Manages the monitors on https://status.labelvier.nl (Uptime Kuma 2.3.2, checked 2026-11-18).
Run it through `labelvier uptime-kuma <command>`: `inc/uptime-kuma.sh` checks node >= 20, runs `npm ci`
when the lockfile changed, and forwards all arguments to `src/cli.js`. Point `KUMA_CLI_DIR` at another
checkout to run that one instead.

It replaces the bash + Python `uptime-kuma` script in the uptime-kuma Docker project
(bitbucket `labelvier/uptime-kuma`). That script needed a Python venv with `uptime-kuma-api`, which only
supports Uptime Kuma 1.x.

## Code

- [src/client.js](src/client.js): Socket.IO client. One dependency: `socket.io-client`.
- [src/monitor.js](src/monitor.js): URL normalizing and the payload for a new HTTP monitor.
- [src/filter.js](src/filter.js): picks monitors (`--domain`, `--filter`, `--id`, `--name`, `--tag`, `--all`). Pure, unit-tested.
- [src/config.js](src/config.js): dotenv parser, stored login, the project `.env` import.
- [src/cli.js](src/cli.js): argument parsing, commands, confirmation.
- [src/prompt.js](src/prompt.js): copy of `node/siteground/src/prompt.js`.

## API

Uptime Kuma has no REST API for monitors. The web app talks Socket.IO; the handlers are in
`server/server.js` of the release tag (https://github.com/louislam/uptime-kuma). Used here:

| Event | Arguments | Answer |
|---|---|---|
| `login` | `{ username, password, token }` (`token` = 2FA code) | `{ ok, token }` or `{ tokenRequired: true }` |
| `loginByToken` | JWT | `{ ok }`; `authInvalidToken` after a password change |
| `monitorList` | pushed by the server after a login | object `id -> monitor` |
| `add` | monitor object as the web form sends it | `{ ok, monitorID }` |
| `notificationList` | pushed after a login | array; `isDefault` marks the ones a new monitor gets |
| `getMonitor` | id | `{ ok, monitor }` (full object) |
| `editMonitor` | full monitor object | `{ ok }`; `accepted_statuscodes` must be strings |
| `pauseMonitor` / `resumeMonitor` | id | `{ ok }` |
| `deleteMonitor` | id, deleteChildren (bool, 2.x) | `{ ok }`; we always pass `false` |

`edit` fetches the monitor with `getMonitor`, applies the changes and sends the whole object back,
the same way the edit form does. `--retries` maps to `maxretries` (the old script wrote it to
`retryInterval` by mistake).

## Login and secrets

- `login` takes the CLI user from `~/Sites/uptime-kuma/.env` (keys `USERNAME`/`PASSWORD`, or
  `KUMA_USERNAME`/`KUMA_PASSWORD`), from `--from-env <file>`, from `UPTIME_KUMA_USERNAME` +
  `UPTIME_KUMA_PASSWORD`, or asks. Only those keys are read: that `.env` is the Docker project's
  and also holds `DB_ROOT_PASSWORD`.
- The password is swapped for the JWT from `login`. Only `KUMA_URL`, `KUMA_USERNAME` and `KUMA_TOKEN`
  are written, to `$KUMA_STATE_DIR/.env` (default `~/.config/labelvier/uptime-kuma/.env`, chmod 600).
- Environment wins over the file: `UPTIME_KUMA_URL`, `UPTIME_KUMA_TOKEN`.
- Never read plain `USERNAME` from the environment: zsh treats it as the logged-in user and ignores
  an assignment to it, so `export USERNAME=labelvier` silently keeps your own name.
- Never print, commit or paste the token.

## Tests

`npm test` here, or `tests/run.sh node` from the repo root (runs `npm ci` first). The client tests use a
fake socket; nothing touches the network. On 2026-11-18 `add`, `pause`, `resume` and `delete` were checked live with a throwaway monitor for
apple.com (id 253, deleted again), and `update` with a no-op on monitor 1. Use such a throwaway monitor
again for live checks, never existing client monitors.
