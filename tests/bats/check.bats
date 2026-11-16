#!/usr/bin/env bats
# inc/check.sh: `check php` runs PHP_CodeSniffer on the theme of a Label Vier project.
# php, composer and brew are stubs; PHPCS_DIR points at a fake php/phpcs checkout in
# the sandbox whose vendor/bin/phpcs records its arguments and exits with
# $PHPCS_STUB_STATUS. One test at the end runs the real phpcs when it is installed.

load test_helper

THEME="wp-content/themes/mytheme"

setup() {
  setup_sandbox
  PHPCS_FAKE="$TEST_TMP/phpcs"
  export PHPCS_DIR="$PHPCS_FAKE"
  mkdir -p "$PHPCS_FAKE"
  echo '{}' > "$PHPCS_FAKE/composer.json"
  echo '{}' > "$PHPCS_FAKE/composer.lock"
  echo '<ruleset name="Fake"/>' > "$PHPCS_FAKE/ruleset.xml"

  stub php
  stub brew
  # composer install puts the fake phpcs in place, like the real install would.
  # The stub runs in its own process, so it sources the helper from a file.
  stub composer '. "$STUB_DIR/.make_fake_phpcs"; make_fake_phpcs "${2#--working-dir=}"'
  cat > "$STUB_DIR/.make_fake_phpcs" <<'EOF'
make_fake_phpcs() {
  mkdir -p "$1/vendor/bin" "$1/vendor/composer"
  echo '[]' > "$1/vendor/composer/installed.json"
  cat > "$1/vendor/bin/phpcs" <<'PHPCS'
#!/usr/bin/env bash
printf '%s\n' "phpcs $*" >> "$STUB_LOG"
exit "${PHPCS_STUB_STATUS:-0}"
PHPCS
  chmod +x "$1/vendor/bin/phpcs"
}
EOF
}
teardown() { teardown_sandbox; }

# A Label Vier project in the cwd: .env with DEV_THEME_PATH and the theme folder.
make_project() {
  make_env "DEV_THEME_PATH=/$THEME"
  mkdir -p "$THEME/inc"
}

# phpcs already installed from the current composer.lock.
install_fake_phpcs() {
  # shellcheck disable=SC1091
  . "$STUB_DIR/.make_fake_phpcs"
  make_fake_phpcs "$PHPCS_FAKE"
}

# The recorded phpcs call (there is only one per run).
phpcs_call() { stub_calls | grep '^phpcs '; }

# --- dispatch ---------------------------------------------------------------

@test "bare check prints its documentation" {
  run_cli check
  [ "$status" -eq 0 ]
  assert_output_contains "Available functions:"
  assert_output_contains "php - Check changed theme PHP for security issues and bugs"
}

@test "check php --help prints the description without running anything" {
  make_project
  run_cli check php --help
  [ "$status" -eq 0 ]
  assert_output_contains "php - Check changed theme PHP for security issues and bugs"
  [ -z "$(stub_calls)" ]
}

@test "unknown check subcommand is reported and fails" {
  run_cli check nope
  [ "$status" -ne 0 ]
  assert_output_contains "Unknown command: nope"
}

@test "check php rejects an unknown option" {
  make_project
  run_cli check php --bogus
  [ "$status" -eq 1 ]
  assert_output_contains "Unknown option: --bogus"
  [ -z "$(stub_calls)" ]
}

# --- project detection ------------------------------------------------------

@test "check php fails outside a project" {
  run_cli check php --all
  [ "$status" -eq 1 ]
  assert_output_contains "No .env found. Run this from the root of a Label Vier project."
  [ -z "$(stub_calls)" ]
}

@test "check php fails when DEV_THEME_PATH is not set" {
  make_env "SOMETHING=else"
  run_cli check php --all
  [ "$status" -eq 1 ]
  assert_output_contains "DEV_THEME_PATH is not set in the .env file."
}

@test "check php fails when the theme folder does not exist" {
  make_env "DEV_THEME_PATH=/wp-content/themes/missing"
  run_cli check php --all
  [ "$status" -eq 1 ]
  assert_output_contains "Theme folder wp-content/themes/missing (DEV_THEME_PATH in .env) does not exist."
}

@test "check php reads a quoted DEV_THEME_PATH with a trailing slash" {
  make_project
  make_env "DEV_THEME_PATH=\"/$THEME/\""
  install_fake_phpcs
  run_cli check php --all
  [ "$status" -eq 0 ]
  [[ "$(phpcs_call)" == *" $THEME" ]]
}

# --- php and composer -------------------------------------------------------

@test "check php stops when php and composer are missing and there is no brew" {
  make_project
  unstub php
  unstub composer
  unstub brew
  PATH="$(bare_path php composer brew)" run "$CLI" check php --all
  [ "$status" -eq 1 ]
  assert_output_contains "Missing: php composer"
  assert_output_contains "Install it yourself: brew install php composer"
}

@test "check php installs PHP_CodeSniffer on first use" {
  make_project
  run_cli check php --all
  [ "$status" -eq 0 ]
  assert_output_contains "Installing PHP_CodeSniffer"
  assert_stub_called "^composer install --working-dir=$PHPCS_FAKE --no-interaction --no-progress --quiet$"
  [ -x "$PHPCS_FAKE/vendor/bin/phpcs" ]
}

@test "check php skips composer when vendor matches composer.lock" {
  make_project
  install_fake_phpcs
  run_cli check php --all
  [ "$status" -eq 0 ]
  refute_stub_called '^composer'
}

@test "check php reinstalls when composer.lock is newer than vendor" {
  make_project
  install_fake_phpcs
  touch -t 202001010000 "$PHPCS_FAKE/vendor/composer/installed.json"
  run_cli check php --all
  [ "$status" -eq 0 ]
  assert_stub_called '^composer install'
}

@test "check php fails when PHPCS_DIR has no composer.json" {
  make_project
  rm "$PHPCS_FAKE/composer.json"
  run_cli check php --all
  [ "$status" -eq 1 ]
  assert_output_contains "PHP_CodeSniffer setup not found in $PHPCS_FAKE. Check PHPCS_DIR."
}

# --- --all ------------------------------------------------------------------

@test "check php --all runs phpcs on the theme with the Label Vier ruleset" {
  make_project
  install_fake_phpcs
  run_cli check php --all
  [ "$status" -eq 0 ]
  assert_output_contains "Checking $THEME with the Label Vier ruleset"
  assert_output_contains "No security issues or bugs found."
  [ "$(phpcs_call)" = "phpcs --standard=$PHPCS_FAKE/ruleset.xml --basepath=$TEST_TMP -q $THEME" ]
}

@test "check php --all fails with the phpcs exit code when phpcs finds errors" {
  make_project
  install_fake_phpcs
  PHPCS_STUB_STATUS=2 run "$CLI" check php --all
  [ "$status" -eq 2 ]
  assert_output_contains "PHP_CodeSniffer found errors (see above)."
}

@test "a phpcs.xml.dist in the project wins over the Label Vier ruleset" {
  make_project
  install_fake_phpcs
  echo '<ruleset name="Project"/>' > phpcs.xml.dist
  run_cli check php --all
  [ "$status" -eq 0 ]
  assert_output_contains "Checking $THEME with phpcs.xml.dist"
  [[ "$(phpcs_call)" == "phpcs --standard=$TEST_TMP/phpcs.xml.dist "* ]]
}

# --- changed files ----------------------------------------------------------

# Git repo in the sandbox with a project on develop and a feature branch checked out.
make_project_repo() {
  local repo
  repo="$(make_git_repo)"
  cd "$repo"
  make_project
  echo '<?php' > "$THEME/functions.php"
  echo '<?php' > "$THEME/inc/old.php"
  echo '<?php' > "$THEME/inc/untouched.php"
  git add -A
  git commit -q -m "theme"
  git branch -f develop
  git checkout -q -b feature/test
  install_fake_phpcs
}

@test "check php fails outside a git repository without --all" {
  make_project
  install_fake_phpcs
  run_cli check php
  [ "$status" -eq 1 ]
  assert_output_contains "Not a git repository"
  [ -z "$(phpcs_call)" ]
}

@test "check php without changes says so and does not run phpcs" {
  make_project_repo
  run_cli check php
  [ "$status" -eq 0 ]
  assert_output_contains "No changed PHP files in $THEME compared to develop."
  [ -z "$(phpcs_call)" ]
}

@test "check php checks committed, uncommitted and new theme PHP files only" {
  make_project_repo
  echo '<?php // changed' > "$THEME/functions.php"
  git commit -q -am "committed change"
  echo '<?php // changed' > "$THEME/inc/old.php"   # uncommitted
  echo '<?php' > "$THEME/inc/new.php"             # untracked
  echo 'body {}' > "$THEME/style.css"             # not PHP
  mkdir -p wp-content/plugins/foo
  echo '<?php' > wp-content/plugins/foo/foo.php   # outside the theme
  run_cli check php
  [ "$status" -eq 0 ]
  assert_output_contains "Checking 3 changed file(s) compared to develop"
  local call
  call="$(phpcs_call)"
  [[ "$call" == *" $THEME/functions.php"* ]]
  [[ "$call" == *" $THEME/inc/old.php"* ]]
  [[ "$call" == *" $THEME/inc/new.php"* ]]
  [[ "$call" != *"untouched.php"* ]]
  [[ "$call" != *"style.css"* ]]
  [[ "$call" != *"plugins"* ]]
}

@test "check php --committed checks only files changed in commits" {
  make_project_repo
  echo '<?php // changed' > "$THEME/functions.php"
  git commit -q -am "committed change"
  echo '<?php // changed' > "$THEME/inc/old.php"   # uncommitted
  echo '<?php' > "$THEME/inc/new.php"             # untracked
  run_cli check php --committed
  [ "$status" -eq 0 ]
  assert_output_contains "Checking 1 changed file(s) compared to develop"
  [ "$(phpcs_call)" = "phpcs --standard=$PHPCS_FAKE/ruleset.xml --basepath=$PWD -q $THEME/functions.php" ]
}

@test "check php --committed without commits ignores uncommitted work" {
  make_project_repo
  echo '<?php' > "$THEME/inc/new.php"
  run_cli check php --committed
  [ "$status" -eq 0 ]
  assert_output_contains "No changed PHP files"
  [ -z "$(phpcs_call)" ]
}

@test "check php skips deleted files" {
  make_project_repo
  git rm -q "$THEME/inc/old.php"
  git commit -q -m "delete"
  run_cli check php
  [ "$status" -eq 0 ]
  assert_output_contains "No changed PHP files"
  [ -z "$(phpcs_call)" ]
}

@test "check php falls back to main when there is no develop branch" {
  make_project_repo
  git branch -q -m develop main
  echo '<?php' > "$THEME/inc/new.php"
  run_cli check php
  [ "$status" -eq 0 ]
  assert_output_contains "compared to main"
}

@test "check php --base compares with the given branch" {
  make_project_repo
  git branch -q release
  echo '<?php' > "$THEME/inc/new.php"
  run_cli check php --base=release
  [ "$status" -eq 0 ]
  assert_output_contains "compared to release"
}

@test "check php --base fails for a branch that does not exist" {
  make_project_repo
  run_cli check php --base=nope
  [ "$status" -eq 1 ]
  assert_output_contains "Branch nope not found. Use --base=<branch> or --all."
  [ -z "$(phpcs_call)" ]
}

# --- pre-push hook ----------------------------------------------------------

HOOK=".git/hooks/pre-push"

@test "install-hook writes an executable pre-push hook that calls this CLI" {
  make_project_repo
  run_cli check install-hook
  [ "$status" -eq 0 ]
  assert_output_contains "Pre-push hook installed"
  [ -x "$HOOK" ]
  grep -qF "# labelvier check php pre-push hook" "$HOOK"
  grep -qF "\"$CLI_ROOT/labelvier\" check php --committed < /dev/null" "$HOOK"
}

@test "install-hook fails outside a project" {
  make_git_repo >/dev/null
  cd "$TEST_TMP/repo"
  run_cli check install-hook
  [ "$status" -eq 1 ]
  assert_output_contains "No .env found"
  [ ! -e "$HOOK" ]
}

@test "install-hook fails outside a git repository" {
  make_project
  run_cli check install-hook
  [ "$status" -eq 1 ]
  assert_output_contains "Not a git repository."
}

@test "install-hook leaves a pre-push hook from someone else alone" {
  make_project_repo
  printf '#!/bin/sh\necho mine\n' > "$HOOK"
  run_cli check install-hook
  [ "$status" -eq 1 ]
  assert_output_contains "already a pre-push hook"
  assert_output_contains "check php --committed"
  [ "$(cat "$HOOK")" = "$(printf '#!/bin/sh\necho mine')" ]
}

@test "install-hook updates its own hook" {
  make_project_repo
  run_cli check install-hook
  echo "# old line" >> "$HOOK"
  run_cli check install-hook
  [ "$status" -eq 0 ]
  # `! cmd` does not fail a bats test, so assert on the status instead.
  run grep -qF "# old line" "$HOOK"
  [ "$status" -ne 0 ]
}

@test "install-hook refuses when core.hooksPath is set" {
  make_project_repo
  git config core.hooksPath .husky
  run_cli check install-hook
  [ "$status" -eq 1 ]
  assert_output_contains "core.hooksPath = .husky"
  [ ! -e .husky/pre-push ]
  [ ! -e "$HOOK" ]
}

@test "uninstall-hook removes its own hook" {
  make_project_repo
  run_cli check install-hook
  run_cli check uninstall-hook
  [ "$status" -eq 0 ]
  assert_output_contains "Pre-push hook removed"
  [ ! -e "$HOOK" ]
}

@test "uninstall-hook leaves a pre-push hook from someone else alone" {
  make_project_repo
  printf '#!/bin/sh\necho mine\n' > "$HOOK"
  run_cli check uninstall-hook
  [ "$status" -eq 1 ]
  assert_output_contains "was not written by labelvier"
  [ -e "$HOOK" ]
}

@test "uninstall-hook without a hook does nothing" {
  make_project_repo
  run_cli check uninstall-hook
  [ "$status" -eq 0 ]
  assert_output_contains "nothing to remove"
}

@test "the hook blocks the push when the committed changes have errors" {
  make_project_repo
  run_cli check install-hook
  echo '<?php // changed' > "$THEME/functions.php"
  git commit -q -am "change"
  echo '<?php' > "$THEME/inc/new.php"   # untracked, not pushed
  PHPCS_STUB_STATUS=1 run sh "$HOOK" origin git@example.com:repo.git <<< "refs/heads/feature/test abc refs/heads/feature/test def"
  [ "$status" -eq 1 ]
  assert_output_contains "PHP_CodeSniffer found errors"
  # Only the committed file; with a terminal around the hook also adds --report-width.
  local call
  call="$(phpcs_call)"
  [[ "$call" == "phpcs --standard=$PHPCS_FAKE/ruleset.xml --basepath=$PWD -q "* ]]
  [[ "$call" == *" $THEME/functions.php" ]]
  [[ "$call" != *"new.php"* ]]
}

@test "the hook asks the terminal for colours and width" {
  make_project_repo
  run_cli check install-hook
  grep -qF 'export FORCE_COLOR=1' "$HOOK"
  grep -qF 'stty size < /dev/tty' "$HOOK"
}

@test "FORCE_COLOR keeps colours in the CLI and phpcs when stdout is not a terminal" {
  make_project
  install_fake_phpcs
  run env -u NO_COLOR FORCE_COLOR=1 "$CLI" check php --all
  [ "$status" -eq 0 ]
  [[ "$(phpcs_call)" == *" --colors "* ]]
  [[ "$output" == *$'\033['* ]]
}

@test "NO_COLOR wins over FORCE_COLOR" {
  make_project
  install_fake_phpcs
  run env NO_COLOR=1 FORCE_COLOR=1 "$CLI" check php --all
  [ "$status" -eq 0 ]
  [[ "$(phpcs_call)" != *"--colors"* ]]
  [[ "$output" != *$'\033['* ]]
}

@test "LABELVIER_REPORT_WIDTH sets the phpcs report width" {
  make_project
  install_fake_phpcs
  LABELVIER_REPORT_WIDTH=180 run "$CLI" check php --all
  [ "$status" -eq 0 ]
  [[ "$(phpcs_call)" == *" --report-width=180 "* ]]
}

@test "the hook lets the push through when the committed changes are clean" {
  make_project_repo
  run_cli check install-hook
  echo '<?php // changed' > "$THEME/functions.php"
  git commit -q -am "change"
  run sh "$HOOK" origin git@example.com:repo.git < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "No security issues or bugs found."
}

# --- the real PHP_CodeSniffer ------------------------------------------------

@test "the Label Vier ruleset flags unsanitized user input and passes editor output" {
  local real="$CLI_ROOT/php/phpcs"
  [ -x "$real/vendor/bin/phpcs" ] || skip "php/phpcs/vendor not installed (run labelvier check php once)"
  export PATH="$ORIGINAL_PATH"
  command -v php >/dev/null || skip "php not installed"
  export PHPCS_DIR="$real"
  make_project

  # Echoed variables and function results are not reported (editor content),
  # nor _e(), nor sanitized input read without a nonce.
  cat > "$THEME/clean.php" <<'PHP'
<?php
$title = get_field( 'title' );
echo $title;
echo get_row_index();
_e( 'Read more', 'labelvier' );
$search = isset( $_GET['s'] ) ? sanitize_text_field( wp_unslash( $_GET['s'] ) ) : '';
PHP
  run "$CLI" check php --all
  [ "$status" -eq 0 ]
  assert_output_contains "No security issues or bugs found."
  refute_output_contains "NonceVerification"
  refute_output_contains "WARNING"

  echo '<?php echo $_GET["x"];' > "$THEME/xss.php"
  run "$CLI" check php --all
  [ "$status" -ne 0 ]
  # User input echoed straight away is still caught.
  assert_output_contains "WordPress.Security.ValidatedSanitizedInput.InputNotSanitized"
  assert_output_contains "xss.php"
}

@test "the Label Vier ruleset wants a labelvier_ prefix on functions in inc/ and functions.php only" {
  local real="$CLI_ROOT/php/phpcs"
  [ -x "$real/vendor/bin/phpcs" ] || skip "php/phpcs/vendor not installed (run labelvier check php once)"
  export PATH="$ORIGINAL_PATH"
  command -v php >/dev/null || skip "php not installed"
  export PHPCS_DIR="$real"
  make_project
  mkdir -p "$THEME/template-parts" "$THEME/modules/Menu"

  # Allowed: prefixed functions, namespaced functions, unprefixed classes and
  # constants, and functions outside inc/ and functions.php.
  cat > "$THEME/inc/fine.php" <<'PHP'
<?php
function labelvier_menu_items() {}
class Menu_Walker {}
const VERSION = '1.0';
PHP
  cat > "$THEME/modules/Menu/helpers.php" <<'PHP'
<?php
namespace Labelvier\Menu;
function items() {}
PHP
  echo '<?php function render_card() {}' > "$THEME/template-parts/card.php"
  run "$CLI" check php --all
  [ "$status" -eq 0 ]
  refute_output_contains "PrefixAllGlobals"

  echo '<?php function get_menu_items() {}' > "$THEME/inc/menu.php"
  echo '<?php function theme_setup() {}' > "$THEME/functions.php"
  run "$CLI" check php --all
  [ "$status" -ne 0 ]
  # phpcs wraps long messages at 80 columns, so match the name only.
  assert_output_contains '"get_menu_items"'
  assert_output_contains '"theme_setup"'
  refute_output_contains "render_card"
}
