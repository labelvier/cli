# AGENTS.md

WP Takeoff CLI — pure-bash command tool (`wp-takeoff`, usually aliased `wt`) for the Label Vier WordPress Starter Kit. No build step, no dependencies; bash sourced at runtime.

## Layout

- `wp-takeoff` — entry point. Sources every `inc/*.sh`, then `main "$@"` runs `$1` as a function.
- `inc/*.sh` — one command collection per file. Filename == function name (`inc/release.sh` → `release()`).
- `inc/core.sh` — install/update/alias/generate machinery.
- `inc/helpers.sh` — shared `_`-prefixed helpers (`_echo_documentation`, `_echo_function_description`, `_dispatch`, `_flag_is_present`, `_is_semantic_version`, `_needs_active_wptakeoff_project`).
- `templates/example.sh.tpl` — scaffold template (`wp-takeoff core generate`).
- `templates/` — files deployed to servers (cron runner, etc.) plus the scaffold template above.
- `package.json` — only holds `version`.

## How commands work

- Each command is a **subshell function** `cmd() ( ... )` (parens, not braces).
- It contains an inner `main() { _dispatch "$filename" "$@"; }` — don't hand-roll the if/else, `_dispatch` (in `helpers.sh`) already does it: runs `$1` as a function with remaining args, prints that function's `# @description` (via `_echo_function_description`) instead of running it when the very next arg is `--help`, or falls back to `_echo_documentation` when no subcommand was given.
- `ssh.sh` and `ai.sh`'s nested `claude` subcommand are the two exceptions with hand-rolled dispatch (special forwarding / a hand-written second-level doc) — they inline the same `--help`-right-after-the-subcommand check rather than calling `_dispatch`. Mirror that inline check if you add another nested/special dispatcher.
- Never pass an unguarded arg straight into `type -t`/`declare -f` when it might be `--help` or another flag — bash's `type`/`declare` parse a leading `--...` as their own option and error out instead of just failing the lookup. Guard with a `[[ "$name" == -* ]]` check (or `declare -f --`) before the lookup, as `_dispatch` and the top-level `wp-takeoff` entry script do.
- The top-level help list is auto-generated from `declare -F` minus names starting with `_` or `main`. So **every internal helper must be `_`-prefixed** to stay hidden.
- Subcommand help comes from `# @function <name>` + `# @description <text>` comment pairs (single line each). Keep `@description` one terse sentence — name what it does, flags in short form (`--force`, not a parenthetical essay). Don't list requirements/usage examples/sub-details there; put those in the command's own `--help`-style output if it needs more, not in this comment.
- `<cmd> <sub> --help` prints that one `@description` line and does **not** run the subcommand — this is load-bearing, don't let a subcommand consume `--help` as a regular flag.
- Color vars `$__red $__blue $__green $__bold $__reset` are set in `wp-takeoff` and inherited — use them, don't redefine.

## Adding a command

1. Read `inc/hello.sh` (minimal) and `inc/cron.sh` / `inc/release.sh` (real) first; mirror their structure.
2. Scaffold with `wp-takeoff core generate <command-name> <first-command-name>` — both args are optional and, if omitted, are asked for interactively; passing them makes it a non-interactive one-liner (the form an agent should use). Or copy the pattern from `templates/example.sh.tpl` by hand.
3. Underscore-prefix all helpers. Reuse `inc/helpers.sh` and `core _get_package_version`.
4. Use the `wt-command-builder` agent (`.claude/agents/`) for this work — it can run `core generate` itself instead of hand-writing the boilerplate.

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
