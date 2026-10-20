# Test suite

Two runners, one entry point: `npm test` (= `tests/run.sh`). CI runs the same on
Ubuntu and macOS (`.github/workflows/test.yml`).

| Part | Where | Runner | Covers |
| --- | --- | --- | --- |
| syntax | `tests/run.sh syntax` | `bash -n` | every bash file parses |
| bash | `tests/bats/*.bats` | [bats-core](https://bats-core.readthedocs.io) (`brew install bats-core`) | entry script, dispatch, every `inc/*.sh` command collection, `scripts/*.sh` |
| node | `node/siteground/test/*.test.js` | `node --test` (node 20+, no dependencies) | the SiteGround CLI: totp, session/env, client, sitetools, actions, cli, demo |

## Rules

- One `.bats` file per `inc/<name>.sh`, named `<name>.bats`; `entry.bats` for the
  `labelvier` script itself, `helpers.bats` for `inc/helpers.sh`, `scripts.bats`
  for `scripts/*.sh`.
- Every test runs in the sandbox from `tests/bats/test_helper.bash`: own `$HOME`,
  own cwd, stubs first on `$PATH`, the 12-hour update check off.
- Nothing in a test may touch the network, the real `$HOME`, Homebrew, Docker,
  SSH or the developer's git config. Stub those commands with `stub <name>` and
  assert on `stub_calls`. Real git is fine inside a repo made with `make_git_repo`.
- Test behaviour through the public entry (`run_cli <cmd> <sub>`) where the
  command is cheap, and unit-test `_`-helpers after `load_cli` where it is not.
- Questions (`read`) get their answer on stdin: `run_cli release start <<< "y"`.
- No sleeps, no retries, no dependence on test order.
