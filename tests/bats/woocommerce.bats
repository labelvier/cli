#!/usr/bin/env bats
# inc/woocommerce.sh: add/remove the WooCommerce scss submodule in a starter kit theme.

load test_helper
setup()    { setup_sandbox; }
teardown() { teardown_sandbox; }

UPSTREAM="./wp-content/themes/foo/src/scss/g-plugins/woocommerce/upstream"
MODULES="\.git/modules/wp-content/themes/foo/src/scss/g-plugins/woocommerce/upstream"

# Succeeds when the stub log contains a line matching each pattern, in this order.
assert_calls_in_order() {
  local last=0 n pattern
  for pattern in "$@"; do
    n=$(grep -nE -- "$pattern" "$STUB_LOG" | awk -F: -v last="$last" '$1 > last {print $1; exit}')
    if [ -z "$n" ]; then
      echo "expected a stub call after line $last matching: $pattern" >&2
      echo "recorded calls:" >&2
      cat "$STUB_LOG" >&2
      return 1
    fi
    last=$n
  done
}

# A starter kit project root: .env, the theme's style.scss, a package.json.
make_project() {
  make_env "DEV_THEME_PATH=wp-content/themes/foo" "THEME_FOLDER_NAME=foo"
  mkdir -p wp-content/themes/foo/src/scss
  touch wp-content/themes/foo/src/scss/style.scss
  echo '{"scripts":{"dev":"gulp dev"}}' > package.json
}

# --- docs & help ------------------------------------------------------------

@test "bare woocommerce prints its functions" {
  run_cli woocommerce
  assert_output_contains "Available functions:"
  assert_output_contains "add"
  assert_output_contains "remove"
}

@test "add --help and remove --help print descriptions without running" {
  stub git
  run_cli woocommerce add --help
  [ "$status" -eq 0 ]
  assert_output_contains "Enable woocommerce scss compilation"
  run_cli woocommerce remove --help
  [ "$status" -eq 0 ]
  assert_output_contains "Disable woocommerce scss compilation"
  refute_stub_called '^git'
}

# --- add ----------------------------------------------------------------------

@test "add outside a project exits before touching git" {
  stub git
  stub npm
  run_cli woocommerce add
  [ "$status" -eq 1 ]
  assert_output_contains "You are not in the right directory"
  refute_stub_called '^git'
}

@test "add without the theme style.scss exits 1" {
  stub git
  make_env "DEV_THEME_PATH=wp-content/themes/foo" "THEME_FOLDER_NAME=foo"
  run_cli woocommerce add
  [ "$status" -eq 1 ]
  assert_output_contains "You are not in the right directory"
  refute_stub_called '^git'
}

@test "add without THEME_FOLDER_NAME in .env exits 1" {
  stub git
  make_env "DEV_THEME_PATH=wp-content/themes/foo"
  mkdir -p wp-content/themes/foo/src/scss
  touch wp-content/themes/foo/src/scss/style.scss
  run_cli woocommerce add
  [ "$status" -eq 1 ]
  assert_output_contains "THEME_FOLDER_NAME is not set in the .env file"
  refute_stub_called '^git'
}

@test "add clones the sparse submodule into the theme and patches the dev script" {
  make_project
  # the real absorbgitdirs creates the module dir the sparse-checkout line is appended to
  stub git 'case "$1" in submodule) [ "$2" = absorbgitdirs ] && mkdir -p .git/modules/wp-content/themes/foo/src/scss/g-plugins/woocommerce/upstream/info ;; esac; exit 0'
  stub npm
  stub node 'echo "gulp dev"'
  run_cli woocommerce add
  [ "$status" -eq 0 ]
  assert_output_contains "Adding woocommerce styling"
  assert_output_contains "Adding git submodule update --remote to dev script"
  assert_output_contains "Now go import the woocommerce scss files"
  assert_calls_in_order \
    "^git submodule deinit -f $UPSTREAM$" \
    "^git rm -f $UPSTREAM$" \
    "^git clone --depth=1 --no-checkout https://github.com/woocommerce/woocommerce.git $UPSTREAM$" \
    "^git submodule add https://github.com/woocommerce/woocommerce.git $UPSTREAM$" \
    '^git submodule absorbgitdirs$' \
    "^git -C $UPSTREAM config core.sparseCheckout true$" \
    '^git submodule update --force --checkout$' \
    '^npm pkg set scripts.dev=git submodule update --remote && gulp dev$'
  [ "$(cat .git/modules/wp-content/themes/foo/src/scss/g-plugins/woocommerce/upstream/info/sparse-checkout)" = 'plugins/woocommerce/client/legacy/css/*' ]
}

@test "add leaves the dev script alone when it already updates the submodule" {
  make_project
  stub git
  stub npm
  stub node 'echo "git submodule update --remote && gulp dev"'
  run_cli woocommerce add
  [ "$status" -eq 0 ]
  refute_stub_called '^npm'
  refute_output_contains "Adding git submodule update --remote"
}

# --- remove -------------------------------------------------------------------

@test "remove outside a project exits before touching git" {
  stub git
  run_cli woocommerce remove
  [ "$status" -eq 1 ]
  assert_output_contains "You are not in the right directory"
  refute_stub_called '^git'
}

@test "remove without THEME_FOLDER_NAME in .env exits 1" {
  stub git
  make_env "DEV_THEME_PATH=wp-content/themes/foo"
  run_cli woocommerce remove
  [ "$status" -eq 1 ]
  assert_output_contains "THEME_FOLDER_NAME is not set in the .env file"
  refute_stub_called '^git'
}

@test "remove deinits the submodule, removes its git dir and strips the dev script" {
  make_project
  mkdir -p ".git/modules/wp-content/themes/foo/src/scss/g-plugins/woocommerce/upstream"
  stub git
  stub npm
  stub node 'echo "git submodule update --remote && gulp dev"'
  run_cli woocommerce remove
  [ "$status" -eq 0 ]
  assert_output_contains "Removing woocommerce styling"
  assert_output_contains "Removing git submodule update --remote from dev script"
  assert_calls_in_order \
    "^git submodule deinit -f $UPSTREAM$" \
    "^git rm -f $UPSTREAM$" \
    '^npm pkg set scripts.dev gulp dev$'
  [ ! -d ".git/modules/wp-content/themes/foo/src/scss/g-plugins/woocommerce/upstream" ]
}

@test "remove leaves the dev script alone when it has no submodule update" {
  make_project
  stub git
  stub npm
  stub node 'echo "gulp dev"'
  run_cli woocommerce remove
  [ "$status" -eq 0 ]
  refute_stub_called '^npm'
}
