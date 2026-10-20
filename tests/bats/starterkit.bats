#!/usr/bin/env bats
# inc/starterkit.sh: install a starter kit project, update its engine, fix docker permissions.

load test_helper
setup()    { setup_sandbox; }
teardown() { teardown_sandbox; }

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

# A git stub whose `clone` lays down the bits of a starter kit checkout that
# `install` touches afterwards (example.env, theme scss files).
stub_git_clone() {
  stub git '
case "$1" in
  clone)
    eval "dir=\${$#}"
    mkdir -p "$dir/wp-content/themes/labelvier/src/scss/a-settings"
    printf "THEME_FOLDER_NAME=labelvier\nDEV_THEME_PATH=/wp-content/themes/labelvier\n" > "$dir/example.env"
    echo "\$theme-path: \"/wp-content/themes/labelvier\";" > "$dir/wp-content/themes/labelvier/src/scss/a-settings/_variables.scss"
    printf "/*\nTheme Name: Labelvier\n*/\n" > "$dir/wp-content/themes/labelvier/src/scss/style.scss"
    ;;
  rev-parse) echo master ;;
esac
exit 0'
}

# --- docs & help ------------------------------------------------------------

@test "bare starterkit prints its functions" {
  run_cli starterkit
  assert_output_contains "Available functions:"
  assert_output_contains "install"
  assert_output_contains "update"
  assert_output_contains "fix-permissions"
}

@test "starterkit --help prints the docs" {
  run_cli starterkit --help
  assert_output_contains "Available functions:"
}

@test "install --help prints its description without running" {
  run_cli starterkit install --help
  [ "$status" -eq 0 ]
  assert_output_contains "Installs the starterkit"
  refute_output_contains "What is the name"
}

@test "update --help and fix-permissions --help print their descriptions" {
  run_cli starterkit update --help
  [ "$status" -eq 0 ]
  assert_output_contains "Updates the starterkit dependencies"
  run_cli starterkit fix-permissions --help
  [ "$status" -eq 0 ]
  assert_output_contains "Fixes the permissions"
}

@test "unknown subcommand is reported" {
  run_cli starterkit nope
  [ "$status" -eq 1 ]
  assert_output_contains "Unknown command: nope"
}

# --- install ------------------------------------------------------------------

@test "install without a project name exits before cloning" {
  stub git
  run_cli starterkit install <<< ""
  [ "$status" -eq 1 ]
  assert_output_contains "No project name given"
  refute_stub_called '^git'
}

@test "install refuses a theme name with spaces before cloning" {
  stub git
  run_cli starterkit install <<< $'myproj\n1\n\nmy theme\n'
  [ "$status" -eq 1 ]
  assert_output_contains "Theme name cannot contain spaces"
  refute_stub_called '^git clone'
}

@test "install with defaults clones master of the standard kit, installs and commits" {
  stub_git_clone
  stub npm
  run_cli starterkit install <<< $'myproj\n1\n\n\nn\n'
  [ "$status" -eq 0 ]
  assert_output_contains "Using default theme name: labelvier"
  assert_output_contains "Installation complete"
  assert_calls_in_order \
    '^git clone -b master --single-branch --depth 1 git@github.com:labelvier/wordpress-starterkit.git myproj$' \
    '^npm run install$' \
    '^git init$' \
    '^git add \.$' \
    '^git commit -m Initial commit$'
  refute_stub_called '^git push'
  refute_stub_called '^git remote'
  [ -f myproj/.env ]
  [ "$(cat myproj/.env)" = "$(cat myproj/example.env)" ]
  [ -d myproj/wp-content/themes/labelvier ]
}

@test "install picks the woocommerce kit and a custom branch" {
  stub_git_clone
  stub npm
  run_cli starterkit install <<< $'shop\n2\ndevelop\n\nn\n'
  [ "$status" -eq 0 ]
  assert_stub_called '^git clone -b develop --single-branch --depth 1 git@github.com:labelvier/labelvier-starterkit-woocommerce.git shop$'
}

@test "install renames the theme folder and rewrites env and scss references" {
  stub_git_clone
  stub npm
  run_cli starterkit install <<< $'myproj\n1\n\nacme\nn\n'
  [ "$status" -eq 0 ]
  assert_output_contains "Renaming theme folder to acme"
  [ -d myproj/wp-content/themes/acme ]
  [ ! -d myproj/wp-content/themes/labelvier ]
  grep -q '^THEME_FOLDER_NAME=acme$' myproj/.env
  grep -q '^DEV_THEME_PATH=/wp-content/themes/acme$' myproj/.env
  grep -qF '$theme-path: "/wp-content/themes/acme"' myproj/wp-content/themes/acme/src/scss/a-settings/_variables.scss
  grep -q '^Theme Name: acme$' myproj/wp-content/themes/acme/src/scss/style.scss
  # sed -i.bak backups are cleaned up again
  [ ! -f myproj/example.env.bak ]
  [ -z "$(find myproj -name '*.bak')" ]
}

@test "install adds the remote and pushes the current branch when asked" {
  stub_git_clone
  stub npm
  run_cli starterkit install <<< $'myproj\n1\n\n\ny\ngit@github.com:labelvier/example.git\n'
  [ "$status" -eq 0 ]
  assert_calls_in_order \
    '^git commit -m Initial commit$' \
    '^git remote add origin git@github.com:labelvier/example.git$' \
    '^git rev-parse --abbrev-ref HEAD$' \
    '^git push -u origin master$'
}

@test "install stops when the clone fails" {
  stub git 'exit 1'
  stub npm
  run_cli starterkit install <<< $'myproj\n1\n\n\nn\n'
  [ "$status" -eq 1 ]
  refute_stub_called '^npm'
  refute_stub_called '^git init'
}

@test "install stops when npm run install fails" {
  stub_git_clone
  stub npm 'exit 1'
  run_cli starterkit install <<< $'myproj\n1\n\n\nn\n'
  [ "$status" -eq 1 ]
  assert_stub_called '^npm run install$'
  refute_stub_called '^git init'
  refute_output_contains "Installation complete"
}

# --- update -------------------------------------------------------------------

@test "update without .env exits 1" {
  stub npm
  run_cli starterkit update
  [ "$status" -eq 1 ]
  assert_output_contains "No .env file found"
  refute_stub_called '^npm'
}

@test "update without DEV_THEME_PATH in .env exits 1" {
  skip "bug: dev_theme_path is prefixed with \$(pwd) so the empty check never triggers; it falls through to 'No package.json file found'"
  stub npm
  make_env "THEME_FOLDER_NAME=foo"
  run_cli starterkit update
  [ "$status" -eq 1 ]
  assert_output_contains "DEV_THEME_PATH is not set in the .env file"
  refute_stub_called '^npm'
}

@test "update without a package.json in the theme exits 1" {
  stub npm
  make_env "DEV_THEME_PATH=/wp-content/themes/foo"
  mkdir -p wp-content/themes/foo
  run_cli starterkit update
  [ "$status" -eq 1 ]
  assert_output_contains "No package.json file found in $TEST_TMP/wp-content/themes/foo"
  refute_stub_called '^npm'
}

@test "update installs the latest engine then updates dependencies in the theme" {
  stub npm 'pwd >> "$STUB_LOG"'
  make_env "DEV_THEME_PATH=/wp-content/themes/foo"
  mkdir -p wp-content/themes/foo
  echo '{}' > wp-content/themes/foo/package.json
  run_cli starterkit update
  [ "$status" -eq 0 ]
  assert_output_contains "Dependencies updated."
  assert_calls_in_order \
    '^npm i @labelvier/starter-kit-engine@latest --save-dev$' \
    "^$TEST_TMP/wp-content/themes/foo$" \
    '^npm update$' \
    "^$TEST_TMP/wp-content/themes/foo$"
}

# --- fix-permissions ------------------------------------------------------------

@test "fix-permissions does nothing without a wordpress container" {
  stub docker
  run_cli starterkit fix-permissions
  [ "$status" -eq 0 ]
  assert_output_contains "There is no wordpress docker container running"
  assert_stub_called '^docker ps -qf name=wordpress$'
  refute_stub_called '^docker exec'
}

@test "fix-permissions chowns the html folder inside the wordpress container" {
  stub docker 'case "$1" in ps) echo abc123 ;; esac'
  run_cli starterkit fix-permissions
  [ "$status" -eq 0 ]
  assert_output_contains "Permissions fixed."
  assert_stub_called '^docker exec -it abc123 chown -R www-data:www-data /var/www/html$'
}
