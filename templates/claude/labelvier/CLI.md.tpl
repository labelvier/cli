<!-- labelvier-ai-version: 5 -->
# Label Vier CLI

`labelvier` (shorthand `l4`) is the team's command tool. It is installed on every developer machine. Use it before you script something yourself or click through a hosting panel: releases, deploys, SiteGround sites and backups, GitOps for Laravel, cron, SSH aliases and storage are covered.

## Getting help

- `labelvier` lists every command.
- `labelvier <command>` lists its subcommands.
- `labelvier <command> <subcommand> --help` prints one line about that subcommand and does not run it.
- `labelvier siteground` prints the full SiteGround usage with all flags.

Read that help before you guess flags. Missing arguments are asked for interactively; pass them as arguments (and `--yes` where it exists) when you run without a terminal.

## Commands

| Command | Use it for |
|---|---|
| `release start\|finish\|cancel\|merge-features` | Git-flow releases: version bump, merge to master/main and develop, tag |
| `deploy staging [--all-features]` | Merge the current branch into `staging`, deploy, purge the SiteGround cache |
| `deploy production [--yes]` | Deploy from master/main or `release/*`, log who deployed, purge the cache |
| `deploy log [amount]` | Production deploy history of the project |
| `gitops setup\|deployer\|tests\|status` | GitOps for a Laravel project on SiteGround: merges into `develop` and pushes to `staging` deploy to staging through GitHub Actions and Deployer (see below) |
| `siteground …` | SiteGround hosting through its API (see below) |
| `uptime-kuma list\|add\|pause\|resume\|delete\|update` | Monitors on status.labelvier.nl (see below) |
| `cron deploy <ssh-host>` | Upload `run_cron_jobs.sh` to a SiteGround server and set `DISABLE_WP_CRON` |
| `ssh alias\|list\|search\|remove` | Manage Host aliases in `~/.ssh/config` |
| `storage summary <host>` | Disk usage on a server; `convert-to-webp <host>` for uploads; `cleanup` for leftover dumps |
| `migrate start\|staging\|load\|sync-status` | Move a site from a VPS or localhost to SiteGround |
| `starterkit install\|update\|fix-permissions` | Set up or update a Starter Kit project |
| `woocommerce add\|remove` | WooCommerce SCSS compilation in the theme |
| `zed autocomplete` | PHP autocompletion for the Zed editor |
| `setup` | Check and install the required tools on a new machine |
| `ai check\|update`, `ai claude install`, `ai mistral install` | AI tooling and these instruction files |
| `core update` | Update the CLI itself |
| `changelog` | What changed in the CLI |

## SiteGround

`labelvier siteground` talks to the SiteGround client area and Site Tools APIs. Use it instead of my.siteground.com or Site Tools in a browser.

- Session: `siteground session:status` shows if you are logged in. A login is `siteground login`; it opens a browser. Ask the user to run it when the session has expired.
- Overview: `accounts`, `sites [--account <name>]`, `site:info <domain>`.
- New site: `create-site --domain <domain> --account <plan> --app wordpress --memcached --ssl --https --yes`. Use `--dry-run` first.
- Existing site: `site:ssl`, `site:memcached`, `site:php`, `site:db`, `site:ssh`, `site:login <domain> --print`.
- Parked domains: `site:alias <domain>` lists them, `--add <alias> [--ssl]` parks one. `site:ssl <domain> --alias <alias>` secures one parked domain; `site:ssl <domain> --aliases` also secures every parked domain without a certificate.
- Backups: `site:backup <domain>` lists them, `--create [--name <label>]` makes a manual backup and waits until it is done. When it reports that the backup may still be running, do not run `--create` again: check with `site:backup <domain>` first, every extra run uses a manual backup slot.
- Database password: `site:db-password <domain> [--user <name>] --yes` gives a database user a new generated password, saved in the site credentials. The site loses its database connection until `.env` or `wp-config.php` has the new password, so update that right after.
- SSH key: `site:ssh-key <domain> [--ssh-key <file.pub>] [--ssh-alias <name>]` authorizes the key and adds a Host alias through `labelvier ssh alias`. After that, `ssh <alias>` works.
- Cron: `site:cron <domain>` lists jobs, `--add "<command>" --at "<min hour day mon dow>"` adds one, `--remove <id>` deletes one. This is the only way to set cron on SiteGround: SSH has no `crontab`.
- Usage: `account:stats <plan>`, `site:stats <domain>` and `account:autoscale <plan>` find the site behind a CPU spike.

Credentials and sessions live in `~/.config/labelvier/siteground`. Never print, commit or paste them. Treat `site:login` links as secrets.

### Real WordPress cron on SiteGround

1. `labelvier cron deploy <ssh-alias>` uploads the runner and disables WP-Cron.
2. `labelvier siteground site:cron <domain> --add "/bin/bash /home/customer/run_cron_jobs.sh" --at "*/5 * * * *"`.

No SSH alias yet? Run `labelvier siteground site:ssh-key <domain>` first.

## GitOps (Laravel)

`labelvier gitops setup` is a wizard, run from the root of a Laravel project, that makes every merge into `develop` deploy to a SiteGround staging site: GitHub Actions merges into `staging` and deploys with Deployer. A push to `staging` (`labelvier deploy staging`) deploys the same way, without a `deploy-staging` npm script. It writes `deploy.php` and the workflows, creates a deploy key, prepares the server (shared `.env`, storage and `public/.htaccess` with the SiteGround PHP handler, `public_html` symlink), sets the GitHub environment and secrets and runs the first deploy. Every step that changes the server, GitHub or SiteGround asks first and defaults to no, so it needs a terminal: ask the user to run it.

- `gitops deployer` writes only `deploy.php` (SiteGround, `recipe/laravel.php`) and requires `deployer/deployer`; it never overwrites. Suggest it for a Laravel project without `deploy.php`, or when `gitops status` warns the recipe is missing. The app `.env` stays on the server, never in GitHub.
- `gitops tests` adds the tests workflow (on every PR and before each staging deploy).
- `gitops status` shows what is in place: project files, deploy key, GitHub environment, secrets and branch.

## Uptime Kuma

`labelvier uptime-kuma` manages the monitors on status.labelvier.nl. Use it instead of the web interface.

- Login: `uptime-kuma session:status` shows if the stored token works. `uptime-kuma login` reads the login from `~/Sites/uptime-kuma/.env` when that checkout exists, otherwise it asks. It stores a token, never the password. Without a terminal and no token the commands fail with an explanation: ask the user to run `labelvier uptime-kuma login`.
- Pick monitors with one filter: `--domain <a.nl,b.nl>` (includes subdomains and www), `--id <1,2>`, `--filter <text>`, `--name <regex>`, `--tag <name>` or `--all`.
- `add <url> [--name <name>]` creates an HTTP monitor (300s, HEAD, 3 retries, default notifications) and asks first when the domain is already monitored.
- `list [filter] [--json]`, `pause`, `resume`, `delete`, `update --interval/--timeout/--retries/--method`. Writes show the matched monitors and ask first; `--yes` skips that.
- A site that left our hosting: `uptime-kuma list --domain <domain>`, then `delete --domain <domain>`.

## Safety

Many commands change remote servers, git branches or paid hosting. Never run them just to test or explore. Ask the user first for: `deploy`, `release finish`, `create-site`, `site:*` writes (including `site:backup --create`, `site:db-password` and `site:alias --add`), `site:cron --add/--remove`, `gitops setup`, `cron deploy`, `migrate`, `storage cleanup`, `storage convert-to-webp` and `uptime-kuma add/pause/resume/delete/update`. Reading commands (`--help`, `accounts`, `sites`, `site:info`, `site:cron`, `site:backup` and `site:alias` without flags, `gitops status`, `deploy log`, `ssh list`, `uptime-kuma list/session:status`) are safe.
