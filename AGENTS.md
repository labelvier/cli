# AGENTS.md

WP Takeoff CLI — pure-bash command tool (`wp-takeoff`, usually aliased `wt`) for the Label Vier WordPress Starter Kit. No build step, no dependencies; bash sourced at runtime.

## Layout

- `wp-takeoff` — entry point. Sources every `inc/*.sh`, then `main "$@"` runs `$1` as a function.
- `inc/*.sh` — one command collection per file. Filename == function name (`inc/release.sh` → `release()`).
- `inc/core.sh` — install/update/alias/generate machinery.
- `inc/helpers.sh` — shared `_`-prefixed helpers (`_echo_documentation`, `_flag_is_present`, `_is_semantic_version`, `_needs_active_wptakeoff_project`).
- `inc/example.sh.tpl` — scaffold template (`wp-takeoff core generate`).
- `templates/` — files deployed to servers (cron runner, etc.).
- `package.json` — only holds `version`.

## How commands work

- Each command is a **subshell function** `cmd() ( ... )` (parens, not braces).
- It contains an inner `main()` that dispatches: if `$1` names a function, run it with remaining args; otherwise print docs via `_echo_documentation`.
- The top-level help list is auto-generated from `declare -F` minus names starting with `_` or `main`. So **every internal helper must be `_`-prefixed** to stay hidden.
- Subcommand help comes from `# @function <name>` + `# @description <text>` comment pairs (single line each).
- Color vars `$__red $__blue $__green $__bold $__reset` are set in `wp-takeoff` and inherited — use them, don't redefine.

## Adding a command

1. Read `inc/hello.sh` (minimal) and `inc/cron.sh` / `inc/release.sh` (real) first; mirror their structure.
2. `wp-takeoff core generate` to scaffold, or copy the pattern from `inc/example.sh.tpl`.
3. Underscore-prefix all helpers. Reuse `inc/helpers.sh` and `core _get_package_version`.
4. Use the `wt-command-builder` agent (`.claude/agents/`) for this work.

## Environment constraints

- macOS bash **3.2** + BSD userland: BSD `date` (`date -r <ts>`), BSD `sed -i ''`, `md5` (not `md5sum`). No `mapfile`/`readarray`.
- WordPress projects run in **Docker** — invoke WP-CLI via the project's `npm run wp` wrapper, not bare `wp` (`npm run wp -- --info` to pass assoc args).
- Read `.env` for ports/urls/paths (`DEV_THEME_PATH`, etc.).
- `core _run_update_checker` runs on every invocation; it `read`s for a git-pull confirmation — non-interactive callers (launchd/cron) get EOF and skip it.

## Verify changes safely

- `bash -n inc/<file>.sh` — syntax.
- `./wp-takeoff <cmd>` — prints docs (confirms dispatch + parsing).
- `./wp-takeoff <cmd> <sub>` — runs subcommand.
- Never run destructive, remote (ssh/scp), or quota-spending subcommands just to "test". Confirm dispatch + syntax, or ask.

## Release

Bump `version` in `package.json` only when asked. The tool self-updates via `git pull` (`core update`); remote is GitHub (`labelvier/WP-Takeoff-CLI`).
