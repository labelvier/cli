# Plan: SiteGround automation

## Phase 1 — Proof of concept (done 2026-10-14)

- [x] Find the API behind my.siteground.com (`uapi.siteground.com/v1`, Bearer JWT).
- [x] Capture the "new blank website, existing domain" wizard payload.
- [x] Find token refresh + order status endpoints in the SPA bundle.
- [x] Node CLI: `login`, `accounts`, `sites`, `create-site`.
- [x] Created `analytics.labelvier.dev` on `Develop - Hamerkop` (site `SmczellITUpKZz09`), then Memcached,
      Let's Encrypt and forced HTTPS on it.

## Phase 2 — Make it useful (in progress)

- [x] WordPress / WooCommerce install through the wizard (`step2`), admin password generated and stored.
- [x] Site Tools API: token, task polling, domains, SSL (Let's Encrypt), force HTTPS, Memcached,
      SSH keys + ssh command, MySQL database/user/grant.
- [x] `create-site` asks step by step for what is missing (domain, plan with site count + free disk,
      app, admin email, Memcached, SSL, HTTPS, SSH key, database) and shows a summary before ordering.
- [x] `site:*` commands for existing sites.
- [x] Login ticks "Stay logged in" automatically.
- [x] Dummy test site `sgdummy.labelvier.dev` (WordPress) on Hamerkop (removed again).
- [x] Progress spinners for every API step.
- [x] SSH alias in `~/.ssh/config` via `labelvier ssh alias` after authorizing a key (`--ssh-alias`).
- [x] PHP version: always asked in `create-site` (versions read from an existing site on the plan),
      `site:php` for existing sites. Setting it is untested end-to-end (dummy was gone): verify once.
- [x] `labelvier siteground …` command in labelvier/cli (`inc/siteground.sh`, not committed there yet).
- [ ] Check the refresh-token lifetime after a login with "Stay logged in" (`npm run sg -- session:status`).
- [x] Cron jobs: `site:cron` lists, adds (`--add`, `--at`) and deletes (`--remove`). Listing verified on
      `analytics.labelvier.dev`; adding and deleting not yet verified live.
- [ ] More Site Tools options when needed: staging, backups, redirects, email.
- [ ] `delete-site` (endpoints known: `GET /sites/{id}/delete`, `DELETE /sites/{id}`), only with explicit confirm.
- [ ] Tests for the payload builders (no network).

## Phase 3 — Later

- [ ] Hook into `labelvier` CLI (e.g. `labelvier site create <domain> --plan hamerkop`).
- [ ] Hosted: small HTTP service / Slack command / Basecamp hook calling the same client; secret storage.
- Not needed: DNS automation via TransIP (decided 2026-10-14; `*.labelvier.dev` wildcard covers dev sites).

## Challenges / gaps

1. **Session lifetime (biggest blocker for hosting).** Refresh token lives 24h and is not rotated.
   "Stay logged in" may extend it (to verify). Options if not:
   - a. Accept it: run `npm run login` before a batch of work. Fine for local CLI use.
   - b. Headless login with Playwright using stored username/password + TOTP secret. Login page uses
     reCAPTCHA, may block headless browsers. Storing the main account password and 2FA secret on a
     server is a large security risk.
   - c. Dedicated SiteGround collaborator user with only the rights needed, used for (b).
   - d. Ask SiteGround for an official / reseller API.
2. **Unofficial APIs.** Can change without notice (version in build path). Keep clients thin and the
   bundle-grep method documented in AGENTS.md so endpoints can be re-captured fast.
3. **ToS.** Automating our own client area is probably fine, but it is not an official API. Keep volume low.
4. **Payload extras.** The UI sends `payment.additional` (browser fingerprint) and `marketingInfo`. We
   leave them out; works today. Add them if SiteGround starts requiring them.
5. **Upsells / costs.** `step3.extras` stays `{}`. Never use `domain_type: "n"` (domain registration) or
   paid apps without an explicit flag.
6. **Disk space.** Basis - Albatros is at 96% (17 GB free). The plan picker shows free space per plan.
7. **Wildcard SSL.** `POST /ssl-le` rejects the `generate` field; wildcard certificates not possible via
   this route yet (also needs DNS at SiteGround).
8. **Secrets in output.** `create-site` prints the generated WP/DB passwords once and stores them in
   `.credentials/`. For hosted use, send them to a vault instead.
