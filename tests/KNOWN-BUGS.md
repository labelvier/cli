# Bugs found while writing the suite

Each has a test marked `skip "bug: …"` with the intended behaviour. Fix the code,
remove the skip. Not fixed on the test branch on purpose: tests first.

| Where | Bug | Test file |
| --- | --- | --- |
| `inc/helpers.sh` `_echo_documentation` | Ends on a `read` that hits EOF, returns 1. Bare `labelvier <cmd>` and `<cmd> <sub> --help` exit 1 instead of 0 (AGENTS.md: "no error, docs only"). | `helpers.bats`, `hello.bats`, `release.bats` |
| `labelvier` `_print_usage` / unknown command | ANSI codes always emitted; only the banner honours `NO_COLOR` / non-tty. | `entry.bats` |
| `labelvier` | `_`-prefixed helpers are callable as commands (`labelvier _is_semantic_version 1.2.3` runs). | `entry.bats` |
| `inc/core.sh:26` `update` | Exits 1 when already up-to-date: `[ $? -eq 10 ] && return 0` leaves status 1 on the normal path. | `core.bats` |
| `inc/core.sh` `_migrate_remote_if_needed` | Rewrites a Bitbucket remote to `labelvier/WP-Takeoff-CLI.git`; the remote is `labelvier/cli.git`. | `core.bats` (asserts current behaviour) |
| `inc/migrate.sh:59` `staging` | `wp=$(npm run \| grep "  db:export")` clobbers `$wp`; every remote command becomes `"  db:export db reset …"`. All staging ssh steps broken. | `migrate.bats` |
| `inc/migrate.sh:296` `run` | `mkdir -p migration_profiles` relative to cwd, profile copied to `$__dir/migration_profiles/`; first save fails. | `migrate.bats` |
| `inc/migrate.sh:566,589` | `sed -i ''` is BSD-only; fails under GNU sed (Ubuntu CI). | `migrate.bats` (skips on GNU sed) |
| `inc/migrate.sh` `sync-status` | With no `.migration` and no profiles it runs `ssh -p "" "@"` instead of exiting. | noted, not asserted |
| `inc/starterkit.sh:109` `update` | `dev_theme_path="$current_dir"$(…)` is never empty, so "DEV_THEME_PATH is not set" can never trigger. | `starterkit.bats` |
| `inc/storage.sh` | Uses undefined `$__yellow`. | noted |
| `templates/convert-to-webp.sh.tpl` | xargs fallback (no GNU parallel) calls `process_image` without the type argument: GIFs go through `cwebp`, animation lost. | `templates.bats` |
| `templates/convert-to-webp.sh.tpl` `is_webp_file` | Greps `od` output with single spaces; BSD `od` prints two, so on macOS WebP files are never skipped and get re-converted. | `templates.bats` (Darwin skip) |
| `node/siteground` `session:status` | Crashes with a Buffer error when the stored token is not a JWT; `session:import` accepts any string. | `cli.test.js` (tested around) |
| `node/siteground` `prompt.interactive` | `undefined` instead of `false` on a pipe. | `prompt.test.js` |
