#!/usr/bin/env bats
# The `labelvier` entry script: usage, dispatch, the l4/wp-takeoff names,
# colour handling and the 12-hour update checker.

load test_helper
bats_require_minimum_version 1.5.0
setup()    { setup_sandbox; }
teardown() { teardown_sandbox; }

# A private copy of the CLI in the sandbox with a fake .git directory, so the
# update checker's `.last_git_check` (next to inc/) can be touched freely
# without touching the real checkout. Prints the copy's entry script.
make_cli_copy() {
  local dir="$TEST_TMP/cli"
  mkdir -p "$dir/.git"
  cp "$CLI_ROOT/labelvier" "$CLI_ROOT/package.json" "$dir/"
  cp -R "$CLI_ROOT/inc" "$dir/inc"
  echo "$dir/labelvier"
}

package_version() {
  sed -nE 's/.*"version": *"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$CLI_ROOT/package.json"
}

# ------------------------------------------------------------------- usage

@test "bare call prints the usage and exits 1" {
  run_cli
  [ "$status" -eq 1 ]
  assert_output_contains "This is the Label Vier CLI"
  assert_output_contains "Usage: labelvier <command> [arguments]"
  assert_output_contains "Possible commands:"
  refute_output_contains "Unknown command"
}

@test "a flag-like first argument prints the usage and exits 1" {
  run_cli --help
  [ "$status" -eq 1 ]
  assert_output_contains "Usage: labelvier <command> [arguments]"
  refute_output_contains "Unknown command"
  run_cli -v
  [ "$status" -eq 1 ]
  assert_output_contains "Usage: labelvier <command> [arguments]"
  refute_output_contains "Unknown command"
}

@test "an unknown command is named, followed by the usage, and exits 1" {
  run_cli frobnicate
  [ "$status" -eq 1 ]
  [ "$(plain_output | head -1)" = "✗ Unknown command: frobnicate" ]
  assert_output_contains "Possible commands:"
}

@test "the usage lists the command collections" {
  run_cli
  local listed
  listed="$(plain_output | sed -n '/Possible commands:/,$p' | tail -n +2 | sed 's/^  //')"
  for cmd in ai core cron deploy hello release setup; do
    printf '%s\n' "$listed" | grep -qx "$cmd"
  done
}

@test "the usage hides _-prefixed helpers and main" {
  run_cli
  local listed
  listed="$(plain_output | sed -n '/Possible commands:/,$p' | tail -n +2 | sed 's/^  //')"
  [ -n "$listed" ]
  ! printf '%s\n' "$listed" | grep -q '^_'
  ! printf '%s\n' "$listed" | grep -qx 'main'
}

@test "the usage lists every inc/*.sh command and nothing else" {
  run_cli
  local listed expected
  # bats exports its own bats_* functions; the CLI inherits and lists them.
  listed="$(plain_output | sed -n '/Possible commands:/,$p' | tail -n +2 | sed 's/^  //' | grep -v '^bats_' | sort)"
  expected="$(cd "$CLI_ROOT/inc" && ls *.sh | sed 's/\.sh$//' | grep -v '^helpers$' | sort)"
  [ "$listed" = "$expected" ]
}

@test "the version in the usage comes from package.json" {
  local version
  version="$(package_version)"
  [ -n "$version" ]
  run_cli
  assert_output_contains "(version $version)"
}

# ---------------------------------------------------------------- dispatch

@test "a real command is dispatched with its arguments" {
  run_cli hello world Eric
  [ "$status" -eq 0 ]
  [ "$(plain_output)" = "Hello Eric!" ]
}

@test "the exit status of the command is passed through" {
  run_cli hello nope
  [ "$status" -eq 1 ]
  assert_output_contains "Unknown command: nope"
}

@test "an _-prefixed helper cannot be run as a command" {
  run_cli _is_semantic_version 1.2.3
  [ "$status" -eq 1 ]
  assert_output_contains "Unknown command: _is_semantic_version"
}

# ------------------------------------------------------------------- names

@test "the l4 symlink runs the same CLI and names itself in the usage" {
  run "$CLI_ROOT/l4" hello world
  [ "$status" -eq 0 ]
  [ "$(plain_output)" = "Hello world!" ]
  run --separate-stderr "$CLI_ROOT/l4"
  [ "$status" -eq 1 ]
  assert_output_contains "Usage: l4 <command> [arguments]"
  [ -z "$stderr" ]
}

@test "wp-takeoff warns about the deprecation on stderr and still runs the command" {
  run --separate-stderr "$CLI_ROOT/wp-takeoff" hello world
  [ "$status" -eq 0 ]
  [ "$(plain_output)" = "Hello world!" ]
  printf '%s\n' "$stderr" | sed -E $'s/\x1b\\[[0-9;]*m//g' | grep -qF "'wp-takeoff' is deprecated, use labelvier or l4 instead."
}

@test "labelvier itself does not print the deprecation warning" {
  run --separate-stderr "$CLI" hello world
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

# ------------------------------------------------------------------ colour

@test "the banner is not coloured when NO_COLOR is set" {
  run_cli
  assert_output_contains "Label Vier CLI"
  ! printf '%s' "$output" | grep -q $'\033\\[38;2;'
}

@test "the banner is not coloured when stdout is not a terminal" {
  run env -u NO_COLOR "$CLI"
  assert_output_contains "Label Vier CLI"
  ! printf '%s' "$output" | grep -q $'\033\\[38;2;'
}

@test "the usage text honours NO_COLOR too" {
  run_cli
  ! printf '%s' "$output" | grep -q $'\033\\['
}

# ---------------------------------------------------------- update checker

@test "the update checker is skipped when LABELVIER_AUTO_UPDATE is set" {
  stub git
  run_cli hello world
  [ "$status" -eq 0 ]
  refute_output_contains "Checking for updates"
  refute_stub_called '^git'
}

@test "the update checker is skipped when .last_git_check is fresh" {
  stub git
  local cli
  cli="$(make_cli_copy)"
  touch "$TEST_TMP/cli/.last_git_check"
  run env -u LABELVIER_AUTO_UPDATE "$cli" hello world
  [ "$status" -eq 0 ]
  [ "$(plain_output)" = "Hello world!" ]
  refute_stub_called '^git'
}

@test "the update checker fetches when .last_git_check is older than 12 hours" {
  stub git
  local cli
  cli="$(make_cli_copy)"
  touch -t 202001010000 "$TEST_TMP/cli/.last_git_check"
  run env -u LABELVIER_AUTO_UPDATE "$cli" hello world
  [ "$status" -eq 0 ]
  assert_output_contains "Checking for updates..."
  assert_output_contains "Hello world!"
  assert_stub_called '^git fetch --tags --force$'
  refute_stub_called '^git pull'
}

@test "the update checker runs when .last_git_check is missing and then creates it" {
  stub git
  local cli
  cli="$(make_cli_copy)"
  run env -u LABELVIER_AUTO_UPDATE "$cli" hello world
  [ "$status" -eq 0 ]
  assert_stub_called '^git fetch --tags --force$'
  [ -f "$TEST_TMP/cli/.last_git_check" ]
}

@test "the update checker does nothing when the CLI is not a git checkout" {
  stub git
  local cli
  cli="$(make_cli_copy)"
  rmdir "$TEST_TMP/cli/.git"
  run env -u LABELVIER_AUTO_UPDATE "$cli" hello world
  [ "$status" -eq 0 ]
  refute_stub_called '^git'
  [ ! -f "$TEST_TMP/cli/.last_git_check" ]
}
