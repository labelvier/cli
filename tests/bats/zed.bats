#!/usr/bin/env bats
# inc/zed.sh: WordPress autocompletion for the Zed editor (settings, composer stubs, gitignore).
# Runs in the sandbox cwd with the sandbox $HOME; composer and git are always stubbed.

load test_helper
setup()    { setup_sandbox; }
teardown() { teardown_sandbox; }

TEMPLATES="$CLI_ROOT/templates/zed"

# A PATH where jq cannot be found but the tools the CLI needs still can
# (macOS ships jq in /usr/bin, so /usr/bin as a whole has to go).
path_without_jq() {
  local bin="$TEST_TMP/bin" tool
  mkdir -p "$bin"
  for tool in dirname basename grep cut sed awk mktemp tput env head tail tr sort uniq wc touch find; do
    [ -x "/usr/bin/$tool" ] && ln -sf "/usr/bin/$tool" "$bin/$tool"
  done
  echo "$STUB_DIR:$bin:/bin"
}

# --- docs & help ------------------------------------------------------------

@test "bare zed prints its functions" {
  run_cli zed
  assert_output_contains "Available functions:"
  assert_output_contains "autocomplete - Enable PHP autocompletion for Zed editor"
}

@test "autocomplete --help prints the description without running" {
  stub composer
  run_cli zed autocomplete --help
  assert_output_contains "Enable PHP autocompletion for Zed editor"
  refute_output_contains "Setting up"
  refute_stub_called '^composer'
  [ ! -d .zed ]
}

@test "unknown subcommand is reported" {
  run_cli zed nope
  [ "$status" -eq 1 ]
  assert_output_contains "Unknown command: nope"
}

# --- provider selection ---------------------------------------------------------

@test "autocomplete asks for a provider and Cancel exits 0 without touching anything" {
  stub composer
  run_cli zed autocomplete <<< "2"
  [ "$status" -eq 0 ]
  assert_output_contains "Which autocompletion do you want to enable?"
  refute_stub_called '^composer'
  [ ! -d .zed ]
  [ ! -f composer.json ]
}

@test "autocomplete menu option 1 is WordPress" {
  stub composer
  stub git
  run_cli zed autocomplete <<< $'1\nn\n'
  [ "$status" -eq 0 ]
  assert_output_contains "Setting up WordPress autocompletion for Zed..."
  [ -f .zed/settings.json ]
}

# --- requirements -------------------------------------------------------------------

@test "autocomplete --wordpress exits 1 when composer is not installed" {
  [ -x /usr/bin/composer ] && skip "composer lives in /usr/bin on this machine"
  stub git
  run env PATH="$STUB_DIR:/usr/bin:/bin" "$CLI" zed autocomplete --wordpress
  [ "$status" -eq 1 ]
  assert_output_contains "Composer is not installed or not in your PATH"
  [ ! -d .zed ]
  [ ! -f composer.json ]
}

@test "autocomplete --wordpress stops when composer install fails" {
  stub composer 'exit 1'
  stub git
  run_cli zed autocomplete --wordpress
  [ "$status" -eq 1 ]
  assert_output_contains "Composer install failed"
  assert_stub_called '^composer install --no-interaction$'
  [ ! -e autocomplete ]
  refute_output_contains "has been set up successfully"
}

# --- fresh project --------------------------------------------------------------------

@test "autocomplete --wordpress in a fresh project copies the templates and links the global autocomplete dir" {
  stub composer
  stub git
  run_cli zed autocomplete --wordpress <<< "n"
  [ "$status" -eq 0 ]
  assert_output_contains "Created .zed/settings.json"
  assert_output_contains "Created composer.json"
  assert_output_contains "Created .gitignore"
  assert_output_contains "has been set up successfully"
  cmp -s .zed/settings.json "$TEMPLATES/settings.json"
  cmp -s composer.json "$TEMPLATES/composer.json"
  cmp -s .gitignore "$TEMPLATES/gitignore-additions.txt"
  assert_stub_called '^composer install --no-interaction$'
  refute_stub_called '^composer require'
  # the autocompletion files live in the sandbox $HOME, the project only gets a symlink there
  [ -d "$HOME/.zed/autocomplete" ]
  [ -L autocomplete ]
  [ "$(readlink autocomplete)" = "$HOME/.zed/autocomplete" ]
  # nothing was committed because the answer was n
  refute_stub_called '^git'
}

@test "autocomplete --wordpress commits the generated files on y" {
  stub composer
  stub git
  run_cli zed autocomplete --wordpress <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "Changes committed"
  assert_stub_called '^git add \.zed/settings\.json composer\.json composer\.lock \.gitignore$'
  assert_stub_called '^git commit -m build: add Zed autocompletion for wordpress via labelvier$'
}

@test "running autocomplete twice replaces the existing symlink and keeps the gitignore entries once" {
  stub composer
  stub git
  run_cli zed autocomplete --wordpress <<< "n"
  [ "$status" -eq 0 ]
  # second run: Skip settings.json, Skip composer.json, no commit
  run_cli zed autocomplete --wordpress <<< $'3\n3\nn\n'
  [ "$status" -eq 0 ]
  assert_output_contains "Skipping .zed/settings.json (kept existing file)"
  assert_output_contains "Skipping composer.json (kept existing file)"
  assert_output_contains ".gitignore already contains autocomplete entries"
  refute_output_contains "File exists"
  [ -L autocomplete ]
  [ "$(readlink autocomplete)" = "$HOME/.zed/autocomplete" ]
  [ "$(grep -c 'managed by labelvier zed' .gitignore)" -eq 1 ]
  cmp -s .gitignore "$TEMPLATES/gitignore-additions.txt"
}

# --- existing .zed/settings.json ---------------------------------------------------------

@test "existing settings.json: Overwrite replaces it with the template" {
  stub composer
  stub git
  mkdir -p .zed
  echo '{"theme":"One Dark"}' > .zed/settings.json
  run_cli zed autocomplete --wordpress <<< $'2\nn\n'
  [ "$status" -eq 0 ]
  assert_output_contains "Found existing .zed/settings.json"
  assert_output_contains "Overwritten .zed/settings.json"
  cmp -s .zed/settings.json "$TEMPLATES/settings.json"
}

@test "existing settings.json: Skip keeps the file untouched" {
  stub composer
  stub git
  mkdir -p .zed
  echo '{"theme":"One Dark"}' > .zed/settings.json
  run_cli zed autocomplete --wordpress <<< $'3\nn\n'
  [ "$status" -eq 0 ]
  [ "$(cat .zed/settings.json)" = '{"theme":"One Dark"}' ]
}

@test "existing settings.json: Merge keeps existing keys and adds the template's" {
  command -v jq >/dev/null || skip "jq not installed"
  stub composer
  stub git
  mkdir -p .zed
  echo '{"theme":"One Dark","lsp":{"intelephense":{"settings":{"licenceKey":"abc"}}}}' > .zed/settings.json
  run_cli zed autocomplete --wordpress <<< $'1\nn\n'
  [ "$status" -eq 0 ]
  assert_output_contains "Merged .zed/settings.json"
  [ "$(jq -r .theme .zed/settings.json)" = "One Dark" ]
  [ "$(jq -r '.lsp.intelephense.settings.licenceKey' .zed/settings.json)" = "abc" ]
  [ "$(jq -r '.lsp.intelephense.settings["environment.includePaths"][0]' .zed/settings.json)" = "vendor/php-stubs/wp-cli-stubs" ]
  [ "$(jq -r '.languages.PHP.language_servers[0]' .zed/settings.json)" = "intelephense" ]
}

@test "existing settings.json: Merge without jq and no install falls back to overwrite" {
  stub composer
  stub git
  mkdir -p .zed
  echo '{"theme":"One Dark"}' > .zed/settings.json
  run env PATH="$(path_without_jq)" "$CLI" zed autocomplete --wordpress <<< $'1\nn\nn\n'
  [ "$status" -eq 0 ]
  assert_output_contains "jq is required for merging JSON files but is not installed."
  assert_output_contains "Falling back to overwrite."
  assert_output_contains "Overwritten .zed/settings.json"
  cmp -s .zed/settings.json "$TEMPLATES/settings.json"
  refute_stub_called '^brew'
}

# --- existing composer.json ------------------------------------------------------------

@test "existing composer.json: Overwrite and Skip" {
  stub composer
  stub git
  echo '{"name":"acme/site"}' > composer.json
  run_cli zed autocomplete --wordpress <<< $'2\nn\n'
  [ "$status" -eq 0 ]
  assert_output_contains "Found existing composer.json"
  assert_output_contains "Overwritten composer.json"
  cmp -s composer.json "$TEMPLATES/composer.json"
  refute_stub_called '^composer require'

  echo '{"name":"acme/site"}' > composer.json
  run_cli zed autocomplete --wordpress <<< $'3\n3\nn\n'
  [ "$status" -eq 0 ]
  [ "$(cat composer.json)" = '{"name":"acme/site"}' ]
}

@test "existing composer.json: Merge requires the stub packages and merges config, extra and scripts" {
  command -v jq >/dev/null || skip "jq not installed"
  stub composer
  stub git
  echo '{"name":"acme/site","scripts":{"post-install-cmd":["echo hi"]}}' > composer.json
  run_cli zed autocomplete --wordpress <<< $'1\nn\n'
  [ "$status" -eq 0 ]
  assert_output_contains "Merging packages into existing composer.json"
  assert_output_contains "Merged composer.json"
  assert_stub_called '^composer require --dev --no-install --no-interaction johnpbloch/wordpress-core-installer:\^2\.0 johnpbloch/wordpress:\^6\.9 php-stubs/wp-cli-stubs:\^2\.12$'
  assert_stub_called '^composer install --no-interaction$'
  [ "$(jq -r .name composer.json)" = "acme/site" ]
  [ "$(jq -r '.config["allow-plugins"]["johnpbloch/wordpress-core-installer"]' composer.json)" = "true" ]
  [ "$(jq -r '.extra["wordpress-install-dir"]' composer.json)" = "autocomplete/wordpress" ]
  [ "$(jq -r '.scripts["post-install-cmd"] | index("echo hi")' composer.json)" != "null" ]
  [ "$(jq -r '.scripts["post-install-cmd"] | index("rm -rf autocomplete/wordpress/wp-content")' composer.json)" != "null" ]
  [ "$(jq -r '.scripts["post-install-cmd"] | index("rm -rf vendor/php-stubs/wordpress-stubs")' composer.json)" != "null" ]
  [ "$(jq -r '.scripts["post-install-cmd"] | length' composer.json)" -eq 3 ]
}

# --- .gitignore -----------------------------------------------------------------------------

@test "existing .gitignore gets the autocomplete entries appended once" {
  stub composer
  stub git
  printf 'node_modules\n' > .gitignore
  run_cli zed autocomplete --wordpress <<< "n"
  [ "$status" -eq 0 ]
  assert_output_contains "Updated .gitignore with autocomplete entries"
  [ "$(head -1 .gitignore)" = "node_modules" ]
  grep -q '^autocomplete$' .gitignore
  grep -q '^vendor$' .gitignore
  grep -q '^!\.zed/settings\.json$' .gitignore
  [ "$(grep -c 'managed by labelvier zed' .gitignore)" -eq 1 ]
}

@test "a .gitignore that already has the marker is left alone" {
  stub composer
  stub git
  cp "$TEMPLATES/gitignore-additions.txt" .gitignore
  echo 'extra' >> .gitignore
  before="$(cat .gitignore)"
  run_cli zed autocomplete --wordpress <<< "n"
  [ "$status" -eq 0 ]
  assert_output_contains ".gitignore already contains autocomplete entries"
  [ "$(cat .gitignore)" = "$before" ]
}

# --- sandbox hygiene ------------------------------------------------------------------------

@test "autocomplete writes only into the project dir and the sandbox HOME" {
  stub composer
  stub git
  run_cli zed autocomplete --wordpress <<< "n"
  [ "$status" -eq 0 ]
  # everything the command created is inside the sandbox
  [ -d "$HOME/.zed/autocomplete" ]
  [ -d "$TEST_TMP/.zed" ]
  case "$(readlink autocomplete)" in
    "$TEST_TMP"/*) ;;
    *) echo "symlink points outside the sandbox: $(readlink autocomplete)" >&2; return 1 ;;
  esac
  # the templates it copied from are untouched
  git -C "$CLI_ROOT" diff --quiet -- templates/zed
}
