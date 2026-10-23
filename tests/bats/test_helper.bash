# Shared helpers for the bats suite. Load at the top of every .bats file:
#
#   load test_helper
#   setup()    { setup_sandbox; }
#   teardown() { teardown_sandbox; }
#
# Every test runs in a throwaway sandbox: its own $HOME, its own working
# directory and a stub directory first on $PATH. Commands that must never run
# for real in a test (ssh, rsync, brew, docker, npm, open, osascript, ...) get
# a stub that records the call; see `stub`.

CLI_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
CLI="$CLI_ROOT/labelvier"

# Fresh sandbox: $TEST_TMP (cwd), $HOME inside it, stubs first on $PATH.
setup_sandbox() {
  TEST_TMP="$(mktemp -d "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/lv-test.XXXXXX")"
  export TEST_TMP
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME"
  STUB_DIR="$TEST_TMP/stubs"
  STUB_LOG="$TEST_TMP/stub-calls.log"
  export STUB_DIR STUB_LOG
  mkdir -p "$STUB_DIR"
  : > "$STUB_LOG"
  ORIGINAL_PATH="$PATH"
  export PATH="$STUB_DIR:$PATH"
  # The 12-hour update check pulls from git and reads from the terminal: off.
  export LABELVIER_AUTO_UPDATE=1
  export NO_COLOR=1
  # Never fall through to the developer's real git identity or config.
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@example.com"
  cd "$TEST_TMP"
}

teardown_sandbox() {
  cd /
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
  [ -n "${ORIGINAL_PATH:-}" ] && export PATH="$ORIGINAL_PATH"
  return 0
}

# stub <command> [body]
# Puts an executable <command> first on $PATH that appends "<command> <args>"
# to $STUB_LOG and then runs <body> (bash, with "$@" = the arguments).
# Default body: exit 0. Examples:
#   stub ssh
#   stub brew 'echo "brew called with: $*"'
#   stub docker 'case "$1" in ps) echo abc123;; *) exit 0;; esac'
#   stub git 'exit 1'
stub() {
  local name="$1"
  local body="${2:-exit 0}"
  {
    echo '#!/usr/bin/env bash'
    echo "printf '%s\\n' \"$name \$*\" >> \"\$STUB_LOG\""
    echo "$body"
  } > "$STUB_DIR/$name"
  chmod +x "$STUB_DIR/$name"
}

# Remove a stub again so the real command is used.
unstub() {
  rm -f "$STUB_DIR/$1"
}

# All recorded stub calls, one per line ("<command> <args>").
stub_calls() {
  cat "$STUB_LOG"
}

# Succeeds when a stub call line matches the given grep -E pattern.
assert_stub_called() {
  grep -qE -- "$1" "$STUB_LOG" || {
    echo "expected a stub call matching: $1" >&2
    echo "recorded calls:" >&2
    cat "$STUB_LOG" >&2
    return 1
  }
}

# Fails when any stub call line matches the given grep -E pattern.
refute_stub_called() {
  if grep -qE -- "$1" "$STUB_LOG"; then
    echo "did not expect a stub call matching: $1" >&2
    cat "$STUB_LOG" >&2
    return 1
  fi
}

# Run the CLI through its real entry point (dispatch, help, exit codes).
run_cli() {
  run "$CLI" "$@"
}

# Strip ANSI colour codes from $output (and echo the result).
plain_output() {
  printf '%s\n' "$output" | sed -E $'s/\x1b\\[[0-9;]*m//g'
}

# Succeeds when the colour-stripped $output contains the substring.
assert_output_contains() {
  if ! plain_output | grep -qF -- "$1"; then
    echo "expected output to contain: $1" >&2
    echo "actual output:" >&2
    plain_output >&2
    return 1
  fi
}

refute_output_contains() {
  if plain_output | grep -qF -- "$1"; then
    echo "did not expect output to contain: $1" >&2
    plain_output >&2
    return 1
  fi
}

# Source the CLI's functions into the current shell without running main(),
# for unit-testing a function directly: load_cli; then call e.g.
#   run _is_semantic_version 1.2.3
#   run release _get_version
# Mirrors what the `labelvier` entry script does before main "$@".
load_cli() {
  main_function="labelvier"
  __red="\033[0;31m"
  __blue="\033[0;34m"
  __green="\033[0;32m"
  __bold="\033[1m"
  __reset="\033[0m"
  __dir="$CLI_ROOT"
  local file
  for file in "$CLI_ROOT"/inc/*.sh; do
    # shellcheck disable=SC1090
    source "$file"
  done
}

# Minimal git repository in the sandbox with one commit on `master` and a
# `develop` branch, the layout `labelvier release` expects. Prints its path.
make_git_repo() {
  local dir="${1:-$TEST_TMP/repo}"
  mkdir -p "$dir"
  git -C "$dir" init -q -b master
  git -C "$dir" config user.name "Test"
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config commit.gpgsign false
  echo "# test" > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m "initial"
  git -C "$dir" branch develop
  echo "$dir"
}

# bare_path [excluded...]
# A PATH with the stubs plus the base system tools, minus the named commands.
# Links every executable from the system directories into $TEST_TMP/bare-bin,
# so "absent" really is absent on every machine (on Ubuntu /bin is /usr/bin and
# apt installs parallel, jq, cwebp there too; Homebrew/nvm are never included).
bare_path() {
  local bin="$TEST_TMP/bare-bin" dir tool name
  if [ ! -d "$bin" ]; then
    mkdir -p "$bin"
    for dir in /usr/bin /bin /usr/sbin /sbin; do
      [ -d "$dir" ] || continue
      for tool in "$dir"/*; do
        name="${tool##*/}"
        [ -x "$tool" ] && [ ! -e "$bin/$name" ] && ln -s "$tool" "$bin/$name"
      done
    done
  fi
  for name in "$@"; do
    rm -f "$bin/$name"
  done
  echo "$STUB_DIR:$bin"
}

# Octal permission bits of a file, e.g. 600 (BSD and GNU stat differ).
file_mode() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1 && [ "$(uname)" = "Darwin" ]; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

# Write a .env file in the current directory from KEY=value arguments.
make_env() {
  printf '%s\n' "$@" > .env
}
