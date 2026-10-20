#!/usr/bin/env bats
# inc/siteground.sh: the bash wrapper around the Node CLI in node/siteground.
# node, npm and npx are stubs; SG_CLI_DIR points at a fake checkout in the
# sandbox and SG_STATE_DIR (when set) at a sandbox state directory.

load test_helper

setup() {
  setup_sandbox
  SG_DIR="$TEST_TMP/sg"
  export SG_CLI_DIR="$SG_DIR"
  mkdir -p "$SG_DIR/src"
  echo '{"name":"siteground"}' > "$SG_DIR/package.json"
  echo '{}' > "$SG_DIR/package-lock.json"
  : > "$SG_DIR/src/cli.js"

  # node: version from NODE_STUB_MAJOR (default 22), the `-e` major check from the
  # same number, and anything else (the CLI itself) echoes its args and the env.
  export NODE_STUB_MAJOR=22
  stub node 'major="${NODE_STUB_MAJOR:-22}"
case "$1" in
  --version) echo "v$major.0.0" ;;
  -e) [ "$major" -ge 20 ] ;;
  *) echo "node $*"; echo "SG_STATE_DIR=${SG_STATE_DIR:-unset}" ;;
esac'
  # npm ci leaves the marker file real npm leaves behind.
  stub npm 'case "$*" in *" ci "*) mkdir -p "$2/node_modules" && touch "$2/node_modules/.package-lock.json" ;; esac; exit 0'
  stub npx
}
teardown() { teardown_sandbox; }

# Marks node_modules as installed from the current package-lock.json.
install_node_modules() {
  mkdir -p "$SG_DIR/node_modules"
  touch "$SG_DIR/node_modules/.package-lock.json"
}

# Recorded calls without the node version probe (`node -e ...` and `node --version`).
calls() { stub_calls | grep -vE "^node (-e|--version)"; }

NPM_CI_PATTERN='^npm --prefix .*/sg ci --silent --no-audit --no-fund$'

# --- preconditions ----------------------------------------------------------

@test "fails when the Node CLI is not at SG_CLI_DIR" {
  rm "$SG_DIR/package.json"
  run_cli siteground sites
  [ "$status" -eq 1 ]
  assert_output_contains "SiteGround CLI not found in $SG_DIR. Check SG_CLI_DIR."
  [ -z "$(stub_calls)" ]
}

@test "fails when node is older than 20" {
  export NODE_STUB_MAJOR=18
  run_cli siteground sites
  [ "$status" -eq 1 ]
  assert_output_contains "SiteGround CLI needs node 20 or newer, found v18.0.0. Run: nvm install --lts"
  refute_stub_called "$NPM_CI_PATTERN"
  refute_stub_called 'cli\.js'
}

@test "node 20 is accepted" {
  export NODE_STUB_MAJOR=20
  run_cli siteground sites
  [ "$status" -eq 0 ]
  assert_stub_called 'cli\.js sites$'
}

# --- dependencies -----------------------------------------------------------

@test "first use runs npm ci before the CLI, in that order" {
  run_cli siteground sites
  [ "$status" -eq 0 ]
  assert_output_contains "Installing SiteGround CLI dependencies"
  [ "$(calls | sed -n 1p)" = "npm --prefix $SG_DIR ci --silent --no-audit --no-fund" ]
  [ "$(calls | sed -n 2p)" = "node $SG_DIR/src/cli.js sites" ]
  [ -f "$SG_DIR/node_modules/.package-lock.json" ]
}

@test "a second use does not run npm ci again" {
  install_node_modules
  run_cli siteground sites
  [ "$status" -eq 0 ]
  refute_output_contains "Installing SiteGround CLI dependencies"
  refute_stub_called '^npm'
  assert_stub_called 'cli\.js sites$'
}

@test "npm ci runs again when package-lock.json is newer than the install" {
  install_node_modules
  touch -t 202001010000 "$SG_DIR/node_modules/.package-lock.json"
  run_cli siteground sites
  [ "$status" -eq 0 ]
  assert_output_contains "Installing SiteGround CLI dependencies"
  assert_stub_called "$NPM_CI_PATTERN"
  assert_stub_called 'cli\.js sites$'
}

@test "a failing npm ci stops before the CLI runs" {
  stub npm 'exit 1'
  run_cli siteground sites
  [ "$status" -eq 1 ]
  assert_output_contains "npm ci failed in $SG_DIR."
  refute_stub_called 'cli\.js'
}

# --- chromium (login only) --------------------------------------------------

@test "login installs Chromium through playwright before the CLI" {
  install_node_modules
  mkdir -p "$SG_DIR/node_modules/playwright"
  run_cli siteground login
  [ "$status" -eq 0 ]
  [ "$(calls | sed -n 1p)" = "npx --no-install playwright install chromium" ]
  [ "$(calls | sed -n 2p)" = "node $SG_DIR/src/cli.js login" ]
}

@test "login fails when playwright is not installed" {
  install_node_modules
  run_cli siteground login
  [ "$status" -eq 1 ]
  assert_output_contains "Playwright is not installed in $SG_DIR, the login needs it."
  refute_stub_called '^npx'
  refute_stub_called 'cli\.js'
}

@test "login fails when the Chromium install fails" {
  install_node_modules
  mkdir -p "$SG_DIR/node_modules/playwright"
  stub npx 'exit 1'
  run_cli siteground login
  [ "$status" -eq 1 ]
  assert_output_contains "Installing Chromium for Playwright failed."
  refute_stub_called 'cli\.js'
}

@test "other commands never touch playwright" {
  install_node_modules
  mkdir -p "$SG_DIR/node_modules/playwright"
  run_cli siteground sites
  [ "$status" -eq 0 ]
  refute_stub_called '^npx'
  run_cli siteground logout
  [ "$status" -eq 0 ]
  refute_stub_called '^npx'
}

# --- state migration --------------------------------------------------------

@test "state is copied once from ~/Sites/siteground into the default state dir" {
  install_node_modules
  mkdir -p "$HOME/Sites/siteground/.credentials"
  echo '{"cookie":"x"}' > "$HOME/Sites/siteground/.session.json"
  echo 'secret' > "$HOME/Sites/siteground/.credentials/example.com"
  unset SG_STATE_DIR

  run_cli siteground sites
  [ "$status" -eq 0 ]
  assert_output_contains "Copied session and credentials from $HOME/Sites/siteground to $HOME/.config/labelvier/siteground."
  [ "$(cat "$HOME/.config/labelvier/siteground/.session.json")" = '{"cookie":"x"}' ]
  [ "$(cat "$HOME/.config/labelvier/siteground/.credentials/example.com")" = "secret" ]
  [ "$(ls -ld "$HOME/.config/labelvier/siteground" | cut -c1-10)" = "drwx------" ]
  assert_output_contains "SG_STATE_DIR=$HOME/.config/labelvier/siteground"
  # the old files stay where they were
  [ -f "$HOME/Sites/siteground/.session.json" ]

  # second run: the state dir exists, nothing is copied again
  echo '{"cookie":"changed"}' > "$HOME/Sites/siteground/.session.json"
  run_cli siteground sites
  [ "$status" -eq 0 ]
  refute_output_contains "Copied session"
  [ "$(cat "$HOME/.config/labelvier/siteground/.session.json")" = '{"cookie":"x"}' ]
}

@test "state is not migrated when the state dir already exists" {
  install_node_modules
  mkdir -p "$HOME/Sites/siteground"
  echo '{"cookie":"old"}' > "$HOME/Sites/siteground/.session.json"
  export SG_STATE_DIR="$TEST_TMP/state"
  mkdir -p "$SG_STATE_DIR"

  run_cli siteground sites
  [ "$status" -eq 0 ]
  refute_output_contains "Copied session"
  [ ! -e "$SG_STATE_DIR/.session.json" ]
}

@test "no state dir is created when there is nothing to migrate" {
  install_node_modules
  unset SG_STATE_DIR
  run_cli siteground sites
  [ "$status" -eq 0 ]
  refute_output_contains "Copied session"
  [ ! -e "$HOME/.config/labelvier/siteground" ]
  assert_output_contains "SG_STATE_DIR=$HOME/.config/labelvier/siteground"
}

@test "only the credentials directory is migrated when there is no session" {
  install_node_modules
  mkdir -p "$HOME/Sites/siteground/.credentials"
  echo 'secret' > "$HOME/Sites/siteground/.credentials/example.com"
  export SG_STATE_DIR="$TEST_TMP/state"
  run_cli siteground sites
  [ "$status" -eq 0 ]
  assert_output_contains "Copied session and credentials"
  [ "$(cat "$SG_STATE_DIR/.credentials/example.com")" = "secret" ]
  [ ! -e "$SG_STATE_DIR/.session.json" ]
}

# --- forwarding -------------------------------------------------------------

@test "arguments are forwarded verbatim, flags included, with SG_STATE_DIR set" {
  install_node_modules
  export SG_STATE_DIR="$TEST_TMP/custom-state"
  run_cli siteground sites list --json --site example.com --force
  [ "$status" -eq 0 ]
  [ "$(calls)" = "node $SG_DIR/src/cli.js sites list --json --site example.com --force" ]
  assert_output_contains "node $SG_DIR/src/cli.js sites list --json --site example.com --force"
  assert_output_contains "SG_STATE_DIR=$TEST_TMP/custom-state"
}

@test "a bare call forwards no arguments so the Node CLI prints its own help" {
  install_node_modules
  run_cli siteground
  [ "$status" -eq 0 ]
  [ "$(calls)" = "node $SG_DIR/src/cli.js" ]
}

@test "the Node CLI exit code is passed through" {
  install_node_modules
  stub node 'case "$1" in --version) echo v22.0.0 ;; -e) exit 0 ;; *) exit 42 ;; esac'
  run_cli siteground sites
  [ "$status" -eq 42 ]
}
