<!-- labelvier-ai-version: 1 -->
# Label Vier CLI

`labelvier` (shorthand `l4`) is the team's command tool. It is installed on every developer machine. Use it before you script something yourself or click through a hosting panel: releases, deploys, SiteGround sites, cron, SSH aliases and storage are covered.

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
| `siteground …` | SiteGround hosting through its API (see below) |
| `cron deploy <ssh-host>` | Upload `run_cron_jobs.sh` to a SiteGround server and set `DISABLE_WP_CRON` |
| `ssh alias\|list\|search\|remove` | Manage Host aliases in `~/.ssh/config` |
| `storage summary <host>` | Disk usage on a server; `convert-to-webp <host>` for uploads; `cleanup` for leftover dumps |
| `migrate start\|staging\|load\|sync-status` | Move a site from a VPS or localhost to SiteGround |
| `starterkit install\|update\|fix-permissions` | Set up or update a Starter Kit project |
| `woocommerce add\|remove` | WooCommerce SCSS compilation in the theme |
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
- SSH key: `site:ssh-key <domain> [--ssh-key <file.pub>] [--ssh-alias <name>]` authorizes the key and adds a Host alias through `labelvier ssh alias`. After that, `ssh <alias>` works.
- Cron: `site:cron <domain>` lists jobs, `--add "<command>" --at "<min hour day mon dow>"` adds one, `--remove <id>` deletes one. This is the only way to set cron on SiteGround: SSH has no `crontab`.
- Usage: `account:stats <plan>`, `site:stats <domain>` and `account:autoscale <plan>` find the site behind a CPU spike.

Credentials and sessions live in `~/.config/labelvier/siteground`. Never print, commit or paste them. Treat `site:login` links as secrets.

### Real WordPress cron on SiteGround

1. `labelvier cron deploy <ssh-alias>` uploads the runner and disables WP-Cron.
2. `labelvier siteground site:cron <domain> --add "/bin/bash /home/customer/run_cron_jobs.sh" --at "*/5 * * * *"`.

No SSH alias yet? Run `labelvier siteground site:ssh-key <domain>` first.

## Safety

Many commands change remote servers, git branches or paid hosting. Never run them just to test or explore. Ask the user first for: `deploy`, `release finish`, `create-site`, `site:*` writes, `site:cron --add/--remove`, `cron deploy`, `migrate`, `storage cleanup` and `storage convert-to-webp`. Reading commands (`--help`, `accounts`, `sites`, `site:info`, `site:cron` without flags, `deploy log`, `ssh list`) are safe.
