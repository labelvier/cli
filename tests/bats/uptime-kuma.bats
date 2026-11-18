#!/usr/bin/env bats
# inc/uptime-kuma.sh: the bash wrapper around the Node CLI in node/uptime-kuma.
# node and npm are stubs; KUMA_CLI_DIR points at a fake checkout in the sandbox.

load test_helper

setup() {
  setup_sandbox
  KUMA_DIR="$TEST_TMP/kuma"
  export KUMA_CLI_DIR="$KUMA_DIR"
  mkdir -p "$KUMA_DIR/src"
  echo '{"name":"uptime-kuma"}' > "$KUMA_DIR/package.json"
  echo '{}' > "$KUMA_DIR/package-lock.json"
  : > "$KUMA_DIR/src/cli.js"

  # node: version from NODE_STUB_MAJOR (default 22), the `-e` major check from the
  # same number, and anything else (the CLI itself) echoes its args and the state dir.
  export NODE_STUB_MAJOR=22
  stub node 'major="${NODE_STUB_MAJOR:-22}"
case "$1" in
  --version) echo "v$major.0.0" ;;
  -e) [ "$major" -ge 20 ] ;;
  *) echo "node $*"; echo "KUMA_STATE_DIR=${KUMA_STATE_DIR:-unset}" ;;
esac'
  # npm ci leaves the marker file real npm leaves behind.
  stub npm 'case "$*" in *" ci "*) mkdir -p "$2/node_modules" && touch "$2/node_modules/.package-lock.json" ;; esac; exit 0'
}
teardown() { teardown_sandbox; }

install_node_modules() {
  mkdir -p "$KUMA_DIR/node_modules"
  touch "$KUMA_DIR/node_modules/.package-lock.json"
}

calls() { stub_calls | grep -vE "^node (-e|--version)"; }

NPM_CI_PATTERN='^npm --prefix .*/kuma ci --silent --no-audit --no-fund$'

@test "is listed as a top-level command" {
  run_cli
  assert_output_contains "uptime-kuma"
}

@test "fails when the Node CLI is not at KUMA_CLI_DIR" {
  rm "$KUMA_DIR/package.json"
  run_cli uptime-kuma list
  [ "$status" -eq 1 ]
  assert_output_contains "Uptime Kuma CLI not found in $KUMA_DIR. Check KUMA_CLI_DIR."
  [ -z "$(stub_calls)" ]
}

@test "fails when node is older than 20" {
  export NODE_STUB_MAJOR=18
  run_cli uptime-kuma list
  [ "$status" -eq 1 ]
  assert_output_contains "Uptime Kuma CLI needs node 20 or newer, found v18.0.0. Run: nvm install --lts"
  refute_stub_called 'cli\.js'
}

@test "first use runs npm ci before the CLI, in that order" {
  run_cli uptime-kuma list
  [ "$status" -eq 0 ]
  assert_output_contains "Installing Uptime Kuma CLI dependencies"
  [ "$(calls | sed -n 1p)" = "npm --prefix $KUMA_DIR ci --silent --no-audit --no-fund" ]
  [ "$(calls | sed -n 2p)" = "node $KUMA_DIR/src/cli.js list" ]
}

@test "a second use does not run npm ci again" {
  install_node_modules
  run_cli uptime-kuma list
  [ "$status" -eq 0 ]
  refute_stub_called '^npm'
}

@test "npm ci runs again when package-lock.json is newer than the install" {
  install_node_modules
  touch -t 202001010000 "$KUMA_DIR/node_modules/.package-lock.json"
  run_cli uptime-kuma list
  [ "$status" -eq 0 ]
  assert_stub_called "$NPM_CI_PATTERN"
}

@test "a failing npm ci stops before the CLI runs" {
  stub npm 'exit 1'
  run_cli uptime-kuma list
  [ "$status" -eq 1 ]
  assert_output_contains "npm ci failed in $KUMA_DIR."
  refute_stub_called 'cli\.js'
}

@test "all arguments are forwarded unchanged, --help included" {
  install_node_modules
  run_cli uptime-kuma delete --domain "a.nl,b.nl" --yes
  [ "$status" -eq 0 ]
  assert_stub_called 'cli\.js delete --domain a\.nl,b\.nl --yes$'
  run_cli uptime-kuma list --help
  assert_stub_called 'cli\.js list --help$'
}

@test "state dir defaults to ~/.config/labelvier/uptime-kuma and follows KUMA_STATE_DIR" {
  install_node_modules
  unset KUMA_STATE_DIR
  run_cli uptime-kuma status
  assert_output_contains "KUMA_STATE_DIR=$HOME/.config/labelvier/uptime-kuma"
  export KUMA_STATE_DIR="$TEST_TMP/state"
  run_cli uptime-kuma status
  assert_output_contains "KUMA_STATE_DIR=$TEST_TMP/state"
}
