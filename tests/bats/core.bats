#!/usr/bin/env bats
# inc/core.sh: package version, generate, alias, the update checker (against
# a sandbox copy of the CLI with its own git repo and bare remote), the
# pinned-release and auto-update paths, and notifications with every
# external tool stubbed. Nothing here touches the real checkout, Homebrew,
# launchd or the network.

load test_helper
setup() {
  setup_sandbox
  export GIT_EDITOR=true
  NOTIFIER_SHA="$(sed -n 's/.*notifier_sha256="\([0-9a-f]*\)".*/\1/p' "$CLI_ROOT/inc/core.sh")"
}
teardown() { teardown_sandbox; }

# A copy of the CLI (entry script, inc, templates, package.json) in $1, with
# tiny stand-ins for `setup` and `ai`: _auto_update runs both after an update
# and the real ones would go looking for brew, nvm, Claude and so on.
make_cli_copy() {
  local dir="$1"
  mkdir -p "$dir/inc"
  cp "$CLI_ROOT/labelvier" "$dir/labelvier"
  cp "$CLI_ROOT"/inc/*.sh "$dir/inc/"
  cp -R "$CLI_ROOT/templates" "$dir/templates"
  cp "$CLI_ROOT/package.json" "$dir/package.json"
  ln -s labelvier "$dir/l4"
  cat > "$dir/inc/setup.sh" <<'EOF'
#!/bin/bash
setup() (
  echo "fake setup $*"
  exit "${FAKE_SETUP_STATUS:-0}"
)
EOF
  cat > "$dir/inc/ai.sh" <<'EOF'
#!/bin/bash
ai() (
  echo "fake ai $*"
  echo "${FAKE_AI_RESULT:-✓ all good}"
)
EOF
}

# Sandbox CLI copy as a git clone of a bare origin, like a real install:
# $CLI_SRC (the "upstream" working copy), $CLI_ORIGIN (bare) and $CLI_COPY
# (the clone that the tests update). Commits in $CLI_SRC pushed with
# push_upstream make the remote ahead of $CLI_COPY.
make_cli_git() {
  CLI_SRC="$TEST_TMP/src"
  CLI_ORIGIN="$TEST_TMP/origin.git"
  CLI_COPY="$TEST_TMP/cli"
  make_cli_copy "$CLI_SRC"
  git -C "$CLI_SRC" init -q -b master
  git -C "$CLI_SRC" config user.name Test
  git -C "$CLI_SRC" config user.email test@example.com
  git -C "$CLI_SRC" add -A
  git -C "$CLI_SRC" commit -q -m "v1"
  git clone -q --bare "$CLI_SRC" "$CLI_ORIGIN"
  git clone -q "$CLI_ORIGIN" "$CLI_COPY"
  git -C "$CLI_COPY" config user.name Test
  git -C "$CLI_COPY" config user.email test@example.com
}

# Commit (empty) in $CLI_SRC and push it to the bare origin, optionally tagged.
push_upstream() {
  git -C "$CLI_SRC" commit -q --allow-empty -m "$1"
  [ -n "${2:-}" ] && git -C "$CLI_SRC" tag -a "$2" -m "$2"
  git -C "$CLI_SRC" push -q --tags "$CLI_ORIGIN" master
}

# Source the sandbox copy's functions into this shell (like load_cli, but for
# $CLI_COPY) so `core _helper` runs against the copy. _confirm reads /dev/tty,
# which a test must never do: it is replaced by one that answers from
# $CONFIRM (yes|no, default no).
load_cli_copy() {
  main_function="labelvier"
  __red="\033[0;31m"; __blue="\033[0;34m"; __green="\033[0;32m"; __bold="\033[1m"; __reset="\033[0m"
  __dir="$CLI_COPY"
  local file
  for file in "$CLI_COPY"/inc/*.sh; do
    # shellcheck disable=SC1090
    source "$file"
  done
  _confirm() {
    echo "$1 [Y/n] (test answers: ${CONFIRM:-no})"
    [ "${CONFIRM:-no}" = "yes" ]
  }
}

# terminal-notifier stub whose -diagnose reports the given authorization.
stub_notifier() {
  mkdir -p "$TEST_TMP/tn.app"
  stub terminal-notifier "case \"\$1\" in
    -diagnose)
      printf '  bundle path  %s\n' '$TEST_TMP/tn.app'
      if [ -f '$STUB_DIR/.granted' ]; then printf '  authorization  authorized\n'; else printf '  authorization  $1\n'; fi
      printf '  alert style  ${2:-alerts}\n' ;;
  esac"
}

# --- docs and dispatch -----------------------------------------------------

@test "core without a subcommand prints its documentation" {
  run_cli core
  [ "$status" -eq 0 ]
  assert_output_contains "Available functions:"
  assert_output_contains "update"
  assert_output_contains "generate"
  assert_output_contains "alias"
  assert_output_contains "notifications"
}

@test "core generate --help prints the description without generating" {
  run_cli core generate --help
  [ "$status" -eq 0 ]
  assert_output_contains "generate <optional-command-name> <optional-first-command-name>"
  refute_output_contains "Generated"
}

# --- _get_package_version --------------------------------------------------

@test "_get_package_version reads the version from the CLI's package.json" {
  local expected
  expected="$(sed -nE 's/.*"version": *"([^"]+)".*/\1/p' "$CLI_ROOT/package.json")"
  [ -n "$expected" ]
  run_cli core _get_package_version
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "_get_package_version follows the package.json next to the inc folder" {
  make_cli_copy "$TEST_TMP/cli"
  printf '{\n  "name": "x",\n  "version": "9.8.7"\n}\n' > "$TEST_TMP/cli/package.json"
  run "$TEST_TMP/cli/labelvier" core _get_package_version
  [ "$status" -eq 0 ]
  [ "$output" = "9.8.7" ]
}

@test "the usage banner shows the package.json version" {
  make_cli_copy "$TEST_TMP/cli"
  printf '{\n  "version": "9.8.7"\n}\n' > "$TEST_TMP/cli/package.json"
  run "$TEST_TMP/cli/labelvier"
  [ "$status" -eq 1 ]
  assert_output_contains "(version 9.8.7)"
}

# --- generate --------------------------------------------------------------

@test "generate scaffolds inc/<command>.sh from the template" {
  make_cli_copy "$TEST_TMP/cli"
  run "$TEST_TMP/cli/labelvier" core generate foo bar
  [ "$status" -eq 0 ]
  assert_output_contains "Generated"
  assert_output_contains "foo.sh"
  local file="$TEST_TMP/cli/inc/foo.sh"
  [ -f "$file" ]
  bash -n "$file"
  grep -q '^foo() ($' "$file"
  grep -q 'local filename="foo.sh"' "$file"
  grep -q '# @function bar$' "$file"
  grep -q 'function bar() {' "$file"
  grep -q '_dispatch "$filename" "$@"' "$file"
  ! grep -q 'global_command_name' "$file"
  ! grep -q 'first_command_name' "$file"
  # The real checkout is untouched.
  [ ! -f "$CLI_ROOT/inc/foo.sh" ]
}

@test "a generated command dispatches through the copied CLI" {
  make_cli_copy "$TEST_TMP/cli"
  "$TEST_TMP/cli/labelvier" core generate foo bar >/dev/null
  run "$TEST_TMP/cli/labelvier" foo bar
  [ "$status" -eq 0 ]
  assert_output_contains "Hello world!"
  run "$TEST_TMP/cli/labelvier" foo bar Eric
  [ "$status" -eq 0 ]
  assert_output_contains "Hello Eric!"
  run "$TEST_TMP/cli/labelvier" foo
  assert_output_contains "bar - Description"
  run "$TEST_TMP/cli/labelvier" foo bar --help
  [ "$status" -eq 0 ]
  assert_output_contains "bar - Description"
  refute_output_contains "Hello"
  run "$TEST_TMP/cli/labelvier"
  assert_output_contains "  foo"
}

@test "generate asks for the names when they are not given" {
  make_cli_git
  load_cli_copy
  run core generate < <(printf 'baz\nqux\n')
  [ "$status" -eq 0 ]
  assert_output_contains "What is the name of the command collection"
  assert_output_contains "What is the name of the first command"
  [ -f "$CLI_COPY/inc/baz.sh" ]
  grep -q 'function qux() {' "$CLI_COPY/inc/baz.sh"
}

@test "generate refuses a command name with other characters than letters, numbers, _ and -" {
  make_cli_copy "$TEST_TMP/cli"
  run "$TEST_TMP/cli/labelvier" core generate "bad name" sub
  [ "$status" -eq 1 ]
  assert_output_contains "can only contain letters, numbers, underscores and dashes"
  [ ! -f "$TEST_TMP/cli/inc/bad name.sh" ]
  run "$TEST_TMP/cli/labelvier" core generate "foo/bar" sub
  [ "$status" -eq 1 ]
}

@test "generate refuses a first command name with other characters than letters, numbers, _ and -" {
  make_cli_copy "$TEST_TMP/cli"
  run "$TEST_TMP/cli/labelvier" core generate okname "bad name"
  [ "$status" -eq 1 ]
  assert_output_contains "can only contain letters, numbers, underscores and dashes"
}

# --- alias -----------------------------------------------------------------

@test "alias appends the alias to the sandbox .zshrc" {
  load_cli
  run core alias < <(printf 'lv\n2\n')
  [ "$status" -eq 0 ]
  assert_output_contains "What do you want to use as an alias for the CLI?"
  assert_output_contains "The alias lv is added to the .zshrc file"
  grep -qx "alias lv='labelvier'" "$HOME/.zshrc"
  [ ! -f "$HOME/.bashrc" ]
}

@test "alias can target .bashrc" {
  load_cli
  run core alias < <(printf 'lv\n1\n')
  [ "$status" -eq 0 ]
  grep -qx "alias lv='labelvier'" "$HOME/.bashrc"
  [ ! -f "$HOME/.zshrc" ]
}

@test "alias can be cancelled" {
  load_cli
  run core alias < <(printf 'lv\n3\n')
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.zshrc" ]
  [ ! -f "$HOME/.bashrc" ]
}

@test "alias is idempotent" {
  load_cli
  core alias < <(printf 'lv\n2\n') >/dev/null
  run core alias < <(printf 'lv\n2\n')
  [ "$status" -eq 0 ]
  assert_output_contains "The alias lv is already in use"
  [ "$(grep -c "alias lv=" "$HOME/.zshrc")" -eq 1 ]
}

@test "_add_alias_to_shell writes once and keeps other content" {
  load_cli
  echo "export FOO=bar" > "$HOME/.bashrc"
  run core _add_alias_to_shell l4x .bashrc
  [ "$status" -eq 0 ]
  assert_output_contains "The alias l4x is added to the .bashrc file"
  run core _add_alias_to_shell l4x .bashrc
  [ "$status" -eq 0 ]
  assert_output_contains "The alias l4x is already in use"
  grep -qx "export FOO=bar" "$HOME/.bashrc"
  [ "$(grep -c "alias l4x='labelvier'" "$HOME/.bashrc")" -eq 1 ]
}

# --- _run_update_checker ---------------------------------------------------

@test "_run_update_checker returns immediately when LABELVIER_AUTO_UPDATE is set" {
  make_cli_git
  load_cli_copy
  touch -t 202001010000 "$CLI_COPY/.last_git_check"
  stub git 'exit 1'
  export LABELVIER_AUTO_UPDATE=1
  run core _run_update_checker
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  refute_stub_called '^git'
  # the stamp was not touched either
  [ "$(date -r "$CLI_COPY/.last_git_check" +%Y)" = "2020" ]
}

@test "_run_update_checker does nothing when the last check is recent" {
  make_cli_git
  load_cli_copy
  touch "$CLI_COPY/.last_git_check"
  stub git 'exit 1'
  unset LABELVIER_AUTO_UPDATE
  run core _run_update_checker
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  refute_stub_called '^git'
}

@test "_run_update_checker checks when the last check is older than 12 hours" {
  make_cli_git
  load_cli_copy
  touch -t 202001010000 "$CLI_COPY/.last_git_check"
  unset LABELVIER_AUTO_UPDATE
  run core _run_update_checker
  [ "$status" -eq 0 ]
  assert_output_contains "Checking for updates..."
  assert_output_contains "Up-to-date"
  # and stamps the check
  [ "$(date -r "$CLI_COPY/.last_git_check" +%Y)" != "2020" ]
}

@test "_run_update_checker checks when there is no .last_git_check yet" {
  make_cli_git
  load_cli_copy
  rm -f "$CLI_COPY/.last_git_check"
  unset LABELVIER_AUTO_UPDATE
  run core _run_update_checker
  [ "$status" -eq 0 ]
  assert_output_contains "Up-to-date"
  [ -f "$CLI_COPY/.last_git_check" ]
}

@test "_run_update_checker is skipped when the CLI is not a git checkout" {
  CLI_COPY="$TEST_TMP/cli"
  make_cli_copy "$CLI_COPY"
  load_cli_copy
  unset LABELVIER_AUTO_UPDATE
  run core _run_update_checker
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$CLI_COPY/.last_git_check" ]
}

@test "_run_update_checker asks when the remote is ahead and a no leaves the CLI alone" {
  make_cli_git
  push_upstream "v2"
  load_cli_copy
  touch -t 202001010000 "$CLI_COPY/.last_git_check"
  unset LABELVIER_AUTO_UPDATE
  local before
  before="$(git -C "$CLI_COPY" rev-parse HEAD)"
  run core _run_update_checker <<< "n"
  [ "$status" -eq 0 ]
  assert_output_contains "Need to pull"
  assert_output_contains "There is an update available for the CLI. Do you want to update? (y/n)"
  refute_output_contains "Update complete"
  [ "$(git -C "$CLI_COPY" rev-parse HEAD)" = "$before" ]
}

@test "_run_update_checker pulls after a yes and returns 10" {
  make_cli_git
  push_upstream "v2"
  load_cli_copy
  touch -t 202001010000 "$CLI_COPY/.last_git_check"
  unset LABELVIER_AUTO_UPDATE
  run core _run_update_checker <<< "y"
  [ "$status" -eq 10 ]
  assert_output_contains "v2"
  assert_output_contains "Update complete."
  assert_output_contains "Run it later with: labelvier setup"
  [ "$(git -C "$CLI_COPY" rev-parse HEAD)" = "$(git -C "$CLI_ORIGIN" rev-parse master)" ]
}

@test "_run_update_checker runs setup after a pull when that is confirmed" {
  make_cli_git
  push_upstream "v2"
  load_cli_copy
  touch -t 202001010000 "$CLI_COPY/.last_git_check"
  unset LABELVIER_AUTO_UPDATE
  export CONFIRM=yes
  run core _run_update_checker <<< "y"
  [ "$status" -eq 10 ]
  assert_output_contains "fake setup"
  # The yes is remembered for the next update.
  grep -qx 'setup_after_update=yes' "$HOME/.config/labelvier/choices"
}

@test "_run_update_checker reuses a remembered answer about running setup" {
  make_cli_git
  push_upstream "v2"
  load_cli_copy
  touch -t 202001010000 "$CLI_COPY/.last_git_check"
  unset LABELVIER_AUTO_UPDATE
  mkdir -p "$HOME/.config/labelvier"
  printf 'setup_after_update=yes\n' > "$HOME/.config/labelvier/choices"
  # CONFIRM=no would refuse if it were asked.
  export CONFIRM=no
  run core _run_update_checker <<< "y"
  [ "$status" -eq 10 ]
  assert_output_contains "Run 'labelvier setup' now to install what this update needs? [remembered: yes]"
  assert_output_contains "fake setup"

  printf 'setup_after_update=no\n' > "$HOME/.config/labelvier/choices"
  git -C "$CLI_COPY" reset -q --hard HEAD~1
  touch -t 202001010000 "$CLI_COPY/.last_git_check"
  export CONFIRM=yes
  run core _run_update_checker <<< "y"
  [ "$status" -eq 10 ]
  assert_output_contains "[remembered: no]"
  assert_output_contains "Run it later with: labelvier setup"
  refute_output_contains "fake setup"
}

# --- choices ---------------------------------------------------------------

@test "choices says so when nothing is remembered" {
  run_cli core choices
  [ "$status" -eq 0 ]
  assert_output_contains "No remembered answers."
}

@test "choices lists the remembered answers" {
  mkdir -p "$HOME/.config/labelvier"
  printf 'fa=no\nsetup_ai=yes\n' > "$HOME/.config/labelvier/choices"
  run_cli core choices
  [ "$status" -eq 0 ]
  assert_output_contains "Remembered answers ($HOME/.config/labelvier/choices):"
  assert_output_contains "  fa: no"
  assert_output_contains "  setup_ai: yes"
}

@test "choices --reset forgets everything" {
  mkdir -p "$HOME/.config/labelvier"
  printf 'fa=no\nsetup_ai=yes\n' > "$HOME/.config/labelvier/choices"
  run_cli core choices --reset
  [ "$status" -eq 0 ]
  assert_output_contains "Forgot all remembered answers"
  [ ! -e "$HOME/.config/labelvier/choices" ]
  run_cli core choices
  assert_output_contains "No remembered answers."
}

@test "choices --reset <key> forgets only that answer" {
  mkdir -p "$HOME/.config/labelvier"
  printf 'fa=no\nsetup_ai=yes\n' > "$HOME/.config/labelvier/choices"
  run_cli core choices --reset fa
  [ "$status" -eq 0 ]
  assert_output_contains "Forgot the answer for fa"
  run_cli core choices
  refute_output_contains "fa: no"
  assert_output_contains "setup_ai: yes"
}

@test "choices --reset on a single last key leaves an empty list" {
  mkdir -p "$HOME/.config/labelvier"
  printf 'fa=no\n' > "$HOME/.config/labelvier/choices"
  run_cli core choices --reset fa
  [ "$status" -eq 0 ]
  run_cli core choices
  assert_output_contains "No remembered answers."
}

@test "choices --help prints only the description" {
  run_cli core choices --help
  [ "$status" -eq 0 ]
  assert_output_contains "choices - Show the remembered answers"
  refute_output_contains "Remembered answers ("
  refute_output_contains "No remembered answers."
}

@test "update --disable-auto remembers that the daily update is not wanted" {
  load_cli
  stub launchctl
  run core update --disable-auto
  [ "$status" -eq 0 ]
  grep -qx 'auto_update=no' "$HOME/.config/labelvier/choices"
}

@test "the entry script stops after a self-update" {
  make_cli_git
  push_upstream "v2"
  load_cli_copy
  touch -t 202001010000 "$CLI_COPY/.last_git_check"
  unset LABELVIER_AUTO_UPDATE
  # The entry script minus its final `main "$@"` and with __dir pointing at
  # the copy (it normally derives that from $0, which is bats here), sourced
  # so main() runs in this shell with the tty-reading _confirm replaced.
  # hello must not run with the old code.
  [ "$(tail -n 1 "$CLI_COPY/labelvier")" = 'main "$@"' ]
  grep -q '^__dir=' "$CLI_COPY/labelvier"
  sed -e '$d' -e "s|^__dir=.*|__dir=\"$CLI_COPY\"|" "$CLI_COPY/labelvier" > "$TEST_TMP/entry.sh"
  # shellcheck disable=SC1090
  source "$TEST_TMP/entry.sh"
  _confirm() { return 1; }
  run main hello world <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "Update complete."
  assert_output_contains "Run your command again to use the new version."
  refute_output_contains "Hello world!"
}

@test "the entry script checks for updates before running a command" {
  make_cli_git
  touch -t 202001010000 "$CLI_COPY/.last_git_check"
  run env LABELVIER_AUTO_UPDATE= "$CLI_COPY/labelvier" hello world
  [ "$status" -eq 0 ]
  assert_output_contains "Checking for updates..."
  assert_output_contains "Up-to-date"
  assert_output_contains "Hello world!"
}

@test "the entry script skips the update check with LABELVIER_AUTO_UPDATE set" {
  make_cli_git
  touch -t 202001010000 "$CLI_COPY/.last_git_check"
  run "$CLI_COPY/labelvier" hello world
  [ "$status" -eq 0 ]
  refute_output_contains "Checking for updates"
  assert_output_contains "Hello world!"
}

# --- update ----------------------------------------------------------------

@test "update reports an up-to-date CLI" {
  make_cli_git
  run "$CLI_COPY/labelvier" core update
  [ "$status" -eq 0 ]
  assert_output_contains "Checking for updates..."
  assert_output_contains "Up-to-date"
}

@test "update exits 0 when the CLI is up-to-date" {
  make_cli_git
  run "$CLI_COPY/labelvier" core update
  [ "$status" -eq 0 ]
}

@test "update pulls after a yes and exits 0" {
  make_cli_git
  push_upstream "v2"
  load_cli_copy
  run core update <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "Update complete."
  [ "$(git -C "$CLI_COPY" rev-parse HEAD)" = "$(git -C "$CLI_ORIGIN" rev-parse master)" ]
  [ -f "$CLI_COPY/.last_git_check" ]
}

@test "update reports a diverged CLI without pulling" {
  make_cli_git
  push_upstream "v2"
  git -C "$CLI_COPY" commit -q --allow-empty -m "local"
  load_cli_copy
  run core update <<< "n"
  assert_output_contains "Diverged"
  assert_output_contains "There is an update available"
}

@test "update returns 1 when the pull fails" {
  make_cli_git
  push_upstream "v2"
  # A conflicting local change makes the pull refuse.
  echo "local" >> "$CLI_COPY/package.json"
  git -C "$CLI_SRC" checkout -q master
  echo "remote" >> "$CLI_SRC/package.json"
  git -C "$CLI_SRC" commit -q -am "remote package.json"
  git -C "$CLI_SRC" push -q "$CLI_ORIGIN" master
  load_cli_copy
  run core _check_and_ask_for_update <<< "y"
  [ "$status" -eq 1 ]
  refute_output_contains "Update complete"
}

@test "update --disable-auto reports when automatic updates were never enabled" {
  load_cli
  stub launchctl
  run core update --disable-auto
  [ "$status" -eq 0 ]
  assert_output_contains "Automatic updates were not enabled."
  refute_stub_called '^launchctl'
}

@test "update --disable-auto unloads and removes the launch agent" {
  load_cli
  stub launchctl
  local plist="$HOME/Library/LaunchAgents/nl.labelvier.cli-update.plist"
  mkdir -p "$(dirname "$plist")" && echo "<plist/>" > "$plist"
  run core update --disable-auto
  [ "$status" -eq 0 ]
  assert_output_contains "Automatic updates disabled."
  assert_stub_called "^launchctl unload $plist\$"
  [ ! -f "$plist" ]
}

@test "update --enable-auto writes the launch agent, loads it and checks notifications" {
  make_cli_git
  load_cli_copy
  stub uname 'echo Darwin'
  stub launchctl
  stub_notifier authorized
  mkdir -p "$HOME/.config/labelvier"
  echo "auto_update=no" > "$HOME/.config/labelvier/choices"
  run core update --enable-auto
  [ "$status" -eq 0 ]
  ! grep -q '^auto_update=' "$HOME/.config/labelvier/choices"
  local plist="$HOME/Library/LaunchAgents/nl.labelvier.cli-update.plist"
  [ -f "$plist" ]
  grep -q "<string>$CLI_COPY/labelvier</string>" "$plist"
  grep -q "<string>--auto</string>" "$plist"
  grep -q "<key>LABELVIER_AUTO_UPDATE</key><string>1</string>" "$plist"
  grep -q "<key>PATH</key><string>$STUB_DIR:" "$plist"
  grep -q "<integer>86400</integer>" "$plist"
  assert_stub_called "^launchctl unload $plist\$"
  assert_stub_called "^launchctl load $plist\$"
  assert_output_contains "Automatic updates enabled"
  assert_output_contains "terminal-notifier may show notifications"
  [ -d "$HOME/.labelvier-auto-update" ]
}

@test "update --enable-auto refuses outside macOS" {
  load_cli
  stub uname 'echo Linux'
  stub launchctl
  run core update --enable-auto
  [ "$status" -eq 1 ]
  assert_output_contains "only supported on macOS"
  refute_stub_called '^launchctl'
  [ ! -d "$HOME/Library/LaunchAgents" ]
}

# --- update --auto (_auto_update) ------------------------------------------

@test "update --auto logs an up-to-date CLI and stays quiet" {
  make_cli_git
  load_cli_copy
  stub osascript
  stub terminal-notifier
  run core update --auto
  [ "$status" -eq 0 ]
  local log="$HOME/.labelvier-auto-update/update.log"
  grep -q "up-to-date at" "$log"
  refute_stub_called '^osascript'
  refute_stub_called '^terminal-notifier'
  # the lock is released again
  [ ! -d "$HOME/.labelvier-auto-update/lock" ]
}

@test "update --auto fast-forwards to the remote and notifies about the new version" {
  make_cli_git
  push_upstream "v2" "1.2.3"
  load_cli_copy
  stub osascript
  local before
  before="$(git -C "$CLI_COPY" rev-parse --short HEAD)"
  run core update --auto
  [ "$status" -eq 0 ]
  local after
  after="$(git -C "$CLI_COPY" rev-parse --short HEAD)"
  [ "$after" = "$(git -C "$CLI_ORIGIN" rev-parse --short master)" ]
  grep -q "updated $before -> $after" "$HOME/.labelvier-auto-update/update.log"
  assert_stub_called '^osascript -e display notification "Updated to version 1.2.3, all checks passed." with title "Label Vier CLI"'
}

@test "update --auto never pulls over local changes" {
  make_cli_git
  push_upstream "v2"
  echo "edited" >> "$CLI_COPY/package.json"
  load_cli_copy
  stub osascript
  local before
  before="$(git -C "$CLI_COPY" rev-parse HEAD)"
  run core update --auto
  [ "$status" -eq 0 ]
  [ "$(git -C "$CLI_COPY" rev-parse HEAD)" = "$before" ]
  grep -q "skip update: working directory has local changes" "$HOME/.labelvier-auto-update/update.log"
}

@test "update --auto moves a pinned install to the newest tag" {
  make_cli_git
  git -C "$CLI_SRC" tag -a 1.0.0 -m 1.0.0
  push_upstream "v2" "1.1.0"
  git -C "$CLI_COPY" fetch -q --tags
  git -C "$CLI_COPY" checkout -q 1.0.0
  load_cli_copy
  stub osascript
  run core update --auto
  [ "$status" -eq 0 ]
  [ "$(git -C "$CLI_COPY" describe --tags --exact-match)" = "1.1.0" ]
  assert_stub_called 'Updated to version 1.1.0'
}

@test "update --auto notifies with a click action when ai check finds problems" {
  make_cli_git
  load_cli_copy
  stub osascript
  stub terminal-notifier
  export FAKE_AI_RESULT="✗ something is outdated"
  run core update --auto
  [ "$status" -eq 0 ]
  grep -q "ai check found problems" "$HOME/.labelvier-auto-update/update.log"
  assert_stub_called '^terminal-notifier -title Label Vier CLI -message Something needs attention. Open the terminal and type: labelvier ai update -execute open '
  local launcher="$HOME/.labelvier-auto-update/notification-action.command"
  [ -x "$launcher" ]
  grep -q "labelvier ai update$" "$launcher"
  refute_stub_called '^osascript'
}

@test "update --auto points at setup when tools are missing" {
  make_cli_git
  load_cli_copy
  stub osascript
  stub terminal-notifier 'exit 1'
  export FAKE_SETUP_STATUS=1
  run core update --auto
  [ "$status" -eq 0 ]
  grep -q "setup tools found missing tools" "$HOME/.labelvier-auto-update/update.log"
  assert_stub_called 'labelvier setup" with title "Label Vier CLI"'
}

@test "update --auto skips when another run holds the lock" {
  make_cli_git
  load_cli_copy
  mkdir -p "$HOME/.labelvier-auto-update/lock"
  stub git 'exit 1'
  run core update --auto
  [ "$status" -eq 0 ]
  grep -q "skip: another run is active" "$HOME/.labelvier-auto-update/update.log"
  refute_stub_called '^git'
  [ -d "$HOME/.labelvier-auto-update/lock" ]
}

@test "update --auto skips when the CLI is not a git checkout" {
  CLI_COPY="$TEST_TMP/cli"
  make_cli_copy "$CLI_COPY"
  load_cli_copy
  run core update --auto
  [ "$status" -eq 0 ]
  grep -q "is not a git checkout" "$HOME/.labelvier-auto-update/update.log"
}

@test "update --auto skips when the fetch fails" {
  make_cli_git
  git -C "$CLI_COPY" remote set-url origin "$TEST_TMP/does-not-exist.git"
  load_cli_copy
  run core update --auto
  [ "$status" -eq 0 ]
  grep -q "skip: git fetch failed" "$HOME/.labelvier-auto-update/update.log"
}

# --- _check_pinned_release -------------------------------------------------

@test "_check_pinned_release is up-to-date on the newest tag" {
  make_cli_git
  git -C "$CLI_SRC" tag -a 1.0.0 -m 1.0.0
  git -C "$CLI_SRC" push -q --tags "$CLI_ORIGIN"
  git -C "$CLI_COPY" fetch -q --tags
  git -C "$CLI_COPY" checkout -q 1.0.0
  load_cli_copy
  cd "$CLI_COPY"
  run core _check_pinned_release
  [ "$status" -eq 0 ]
  assert_output_contains "Up-to-date"
}

@test "_check_pinned_release offers a newer tag and a no keeps the current one" {
  make_cli_git
  git -C "$CLI_SRC" tag -a 1.0.0 -m 1.0.0
  push_upstream "v2" "1.1.0"
  git -C "$CLI_COPY" fetch -q --tags
  git -C "$CLI_COPY" checkout -q 1.0.0
  load_cli_copy
  cd "$CLI_COPY"
  run core _check_pinned_release <<< "n"
  [ "$status" -eq 0 ]
  assert_output_contains "You are on release 1.0.0, 1.1.0 is available. Do you want to update? (y/n)"
  [ "$(git describe --tags --exact-match)" = "1.0.0" ]
}

@test "_check_pinned_release checks out the newer tag after a yes" {
  make_cli_git
  git -C "$CLI_SRC" tag -a 1.0.0 -m 1.0.0
  push_upstream "v2" "1.1.0"
  git -C "$CLI_COPY" fetch -q --tags
  git -C "$CLI_COPY" checkout -q 1.0.0
  load_cli_copy
  cd "$CLI_COPY"
  run core _check_pinned_release <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "v2"
  assert_output_contains "Now on 1.1.0. Please restart the CLI."
  [ "$(git describe --tags --exact-match)" = "1.1.0" ]
}

@test "_check_pinned_release leaves a detached HEAD that is not a tag alone" {
  make_cli_git
  git -C "$CLI_SRC" tag -a 1.0.0 -m 1.0.0
  push_upstream "v2" "1.1.0"
  git -C "$CLI_COPY" fetch -q --tags
  git -C "$CLI_COPY" checkout -q --detach master
  git -C "$CLI_COPY" commit -q --allow-empty -m "stray"
  load_cli_copy
  cd "$CLI_COPY"
  run core _check_pinned_release <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "detached HEAD that is not a release tag, leaving it alone"
}

@test "update on a pinned install goes through the tag check" {
  make_cli_git
  git -C "$CLI_SRC" tag -a 1.0.0 -m 1.0.0
  git -C "$CLI_SRC" push -q --tags "$CLI_ORIGIN"
  git -C "$CLI_COPY" fetch -q --tags
  git -C "$CLI_COPY" checkout -q 1.0.0
  # The newer tag is only on the remote: update must fetch it first.
  push_upstream "v2" "1.1.0"
  load_cli_copy
  run core update <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "You are on release 1.0.0, 1.1.0 is available"
  assert_output_contains "Now on 1.1.0"
  [ "$(git -C "$CLI_COPY" describe --tags --exact-match)" = "1.1.0" ]
}

# --- _migrate_remote_if_needed ---------------------------------------------

@test "_migrate_remote_if_needed rewrites a Bitbucket origin to GitHub" {
  load_cli
  local repo
  repo="$(make_git_repo)"
  cd "$repo"
  git remote add origin git@bitbucket.org:labelvier/wp-takeoff-cli.git
  run core _migrate_remote_if_needed
  [ "$status" -eq 0 ]
  assert_output_contains "Migrating the CLI remote from Bitbucket to GitHub"
  assert_output_contains "Remote updated"
  [ "$(git remote get-url origin)" = "git@github.com:labelvier/cli.git" ]
  [ "$(git remote get-url --push origin)" = "git@github.com:labelvier/cli.git" ]
}

@test "_migrate_remote_if_needed leaves other origins alone" {
  load_cli
  local repo
  repo="$(make_git_repo)"
  cd "$repo"
  git remote add origin git@github.com:labelvier/cli.git
  run core _migrate_remote_if_needed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(git remote get-url origin)" = "git@github.com:labelvier/cli.git" ]
}

@test "_migrate_remote_if_needed is quiet without a remote" {
  load_cli
  cd "$(make_git_repo)"
  run core _migrate_remote_if_needed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- _notify ---------------------------------------------------------------

@test "_notify falls back to osascript without a click action" {
  load_cli
  stub osascript
  stub terminal-notifier
  run core _notify "Title" "Message"
  [ "$status" -eq 0 ]
  assert_stub_called '^osascript -e display notification "Message" with title "Title"$'
  refute_stub_called '^terminal-notifier'
}

@test "_notify uses terminal-notifier with a launcher for the click action" {
  load_cli
  stub osascript
  stub terminal-notifier
  run core _notify "Title" "Message" "labelvier setup"
  [ "$status" -eq 0 ]
  local launcher="$HOME/.labelvier-auto-update/notification-action.command"
  [ -x "$launcher" ]
  [ "$(sed -n 2p "$launcher")" = "labelvier setup" ]
  assert_stub_called "^terminal-notifier -title Title -message Message -execute open $launcher\$"
  refute_stub_called '^osascript'
}

@test "_notify falls back to osascript when terminal-notifier is missing or fails" {
  load_cli
  stub osascript
  stub terminal-notifier 'exit 1'
  run core _notify "Title" "Message" "labelvier setup"
  [ "$status" -eq 0 ]
  assert_stub_called '^terminal-notifier -title Title'
  assert_stub_called '^osascript -e display notification "Message" with title "Title"$'
  : > "$STUB_LOG"
  unstub terminal-notifier
  export PATH="$STUB_DIR:/usr/bin:/bin"
  run core _notify "Title" "Message" "labelvier setup"
  [ "$status" -eq 0 ]
  refute_stub_called '^terminal-notifier'
  assert_stub_called '^osascript'
}

@test "_notify is a no-op without osascript" {
  load_cli
  # A PATH without /usr/bin (osascript lives there on macOS) and without a
  # terminal-notifier, with just the tools the dispatcher itself needs.
  mkdir -p "$TEST_TMP/bin"
  local tool
  for tool in dirname grep sed cut cat; do
    ln -s "$(command -v "$tool")" "$TEST_TMP/bin/$tool"
  done
  export PATH="$STUB_DIR:$TEST_TMP/bin"
  run core _notify "Title" "Message"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(stub_calls)" ]
}

# --- notifications ---------------------------------------------------------

@test "notifications is a no-op outside macOS" {
  load_cli
  stub uname 'echo Linux'
  stub brew
  run core notifications
  [ "$status" -eq 0 ]
  assert_output_contains "Notifications are only supported on macOS."
  refute_stub_called '^brew'
}

@test "notifications confirms an authorized terminal-notifier and tips about persistent banners" {
  load_cli
  stub uname 'echo Darwin'
  stub open
  stub_notifier authorized banners
  run core notifications
  [ "$status" -eq 0 ]
  assert_output_contains "terminal-notifier may show notifications"
  assert_output_contains "set the banner style to Persistent"
  refute_stub_called '^open'
}

@test "notifications skips the banner tip when alerts are already persistent" {
  load_cli
  stub uname 'echo Darwin'
  stub_notifier authorized alerts
  run core notifications
  [ "$status" -eq 0 ]
  refute_output_contains "set the banner style to Persistent"
}

@test "notifications explains denied permission and opens System Settings" {
  load_cli
  stub uname 'echo Darwin'
  stub open
  stub_notifier denied
  run core notifications
  [ "$status" -eq 1 ]
  assert_output_contains "Notifications from terminal-notifier are turned off."
  assert_stub_called '^open x-apple.systempreferences:com.apple.Notifications-Settings.extension$'
}

@test "notifications launches the app bundle once to trigger the permission prompt" {
  load_cli
  stub uname 'echo Darwin'
  # `open` of the bundle is the moment macOS asks; the stub grants it.
  stub open "touch \"$STUB_DIR/.granted\""
  stub_notifier "not determined"
  run core notifications
  [ "$status" -eq 0 ]
  assert_output_contains "macOS asks for permission to show notifications from terminal-notifier now."
  assert_stub_called "^open -W -n $TEST_TMP/tn.app --args -title Label Vier CLI -message Notifications are on.\$"
  assert_output_contains "terminal-notifier may show notifications"
}

@test "notifications reports when permission is still not given after the prompt" {
  load_cli
  stub uname 'echo Darwin'
  stub open
  stub_notifier "not determined"
  run core notifications
  [ "$status" -eq 1 ]
  assert_output_contains "Permission is still not given (status: not determined)"
}

@test "notifications installs terminal-notifier with brew when there is a bottle" {
  make_cli_git
  load_cli_copy
  export PATH="$STUB_DIR:/usr/bin:/bin"
  stub uname 'echo Darwin'
  stub brew 'case "$1" in ruby) echo bottle;; esac'
  export CONFIRM=yes
  run core notifications
  assert_output_contains "terminal-notifier is not installed."
  assert_output_contains "Install it now with 'brew install terminal-notifier'?"
  assert_stub_called '^brew install terminal-notifier$'
  refute_stub_called '^curl'
}

@test "notifications stays plain when installing terminal-notifier is declined" {
  make_cli_git
  load_cli_copy
  export PATH="$STUB_DIR:/usr/bin:/bin"
  stub uname 'echo Darwin'
  stub brew 'case "$1" in ruby) echo bottle;; esac'
  export CONFIRM=no
  run core notifications
  [ "$status" -eq 1 ]
  assert_output_contains "Skipped. Update notifications stay plain (no click action)."
  refute_stub_called '^brew install'
}

@test "notifications points at the GitHub page when Homebrew is missing and declined" {
  make_cli_git
  load_cli_copy
  export PATH="$STUB_DIR:/usr/bin:/bin"
  stub uname 'echo Darwin'
  stub curl 'exit 1'
  export CONFIRM=no
  run core notifications
  [ "$status" -eq 1 ]
  assert_output_contains "Homebrew is not installed."
  assert_output_contains "Install it yourself: https://github.com/julienXX/terminal-notifier"
  refute_stub_called '^curl'
}

@test "notifications takes the GitHub release build when brew has no bottle" {
  make_cli_git
  load_cli_copy
  export PATH="$STUB_DIR:/usr/bin:/bin"
  mkdir -p "$TEST_TMP/brew/bin"
  stub uname 'echo Darwin'
  stub brew "case \"\$1\" in ruby) echo source;; --prefix) echo '$TEST_TMP/brew';; esac"
  stub curl 'while [ $# -gt 0 ]; do [ "$1" = "-o" ] && echo "fake zip" > "$2"; shift; done'
  stub shasum "echo '$NOTIFIER_SHA  \$3'"
  stub ditto 'mkdir -p "$4/terminal-notifier.app/Contents/MacOS" && touch "$4/terminal-notifier.app/Contents/MacOS/terminal-notifier" && chmod +x "$4/terminal-notifier.app/Contents/MacOS/terminal-notifier"'
  export CONFIRM=yes
  run core notifications
  assert_output_contains "Install the official ready-made terminal-notifier"
  assert_output_contains "installed in $HOME/Applications/terminal-notifier.app"
  refute_stub_called '^brew install'
  assert_stub_called '^curl -fsSL https://github.com/julienXX/terminal-notifier/releases/download/'
  [ -x "$TEST_TMP/brew/bin/terminal-notifier" ]
}

# --- _install_notifier_release ---------------------------------------------

@test "_install_notifier_release downloads, verifies, unpacks and writes a wrapper" {
  load_cli
  mkdir -p "$TEST_TMP/brew/bin"
  stub brew "case \"\$1\" in --prefix) echo '$TEST_TMP/brew';; esac"
  stub curl 'while [ $# -gt 0 ]; do [ "$1" = "-o" ] && echo "fake zip" > "$2"; shift; done'
  stub shasum "echo '$NOTIFIER_SHA  \$3'"
  stub ditto 'mkdir -p "$4/terminal-notifier.app/Contents/MacOS" && touch "$4/terminal-notifier.app/Contents/MacOS/terminal-notifier" && chmod +x "$4/terminal-notifier.app/Contents/MacOS/terminal-notifier"'
  run core _install_notifier_release
  [ "$status" -eq 0 ]
  assert_output_contains "Downloading terminal-notifier 3.1.0"
  assert_output_contains "terminal-notifier 3.1.0 installed in $HOME/Applications/terminal-notifier.app"
  assert_stub_called '^curl -fsSL https://github.com/julienXX/terminal-notifier/releases/download/3.1.0/terminal-notifier-3.1.0.zip -o .*/terminal-notifier.zip$'
  assert_stub_called '^shasum -a 256 '
  assert_stub_called '^ditto -x -k '
  [ -x "$HOME/Applications/terminal-notifier.app/Contents/MacOS/terminal-notifier" ]
  local wrapper="$TEST_TMP/brew/bin/terminal-notifier"
  [ -x "$wrapper" ]
  [ "$(sed -n 1p "$wrapper")" = "#!/bin/bash" ]
  grep -q "^exec $HOME/Applications/terminal-notifier.app/Contents/MacOS/terminal-notifier \"\$@\"$" "$wrapper"
}

@test "_install_notifier_release refuses a download with the wrong checksum" {
  load_cli
  mkdir -p "$TEST_TMP/brew/bin"
  stub brew "case \"\$1\" in --prefix) echo '$TEST_TMP/brew';; esac"
  stub curl 'while [ $# -gt 0 ]; do [ "$1" = "-o" ] && echo "tampered" > "$2"; shift; done'
  stub shasum 'echo "0000000000000000000000000000000000000000000000000000000000000000  $3"'
  stub ditto
  run core _install_notifier_release
  [ "$status" -eq 1 ]
  assert_output_contains "The download does not match the expected checksum, not installing it."
  refute_stub_called '^ditto'
  [ ! -d "$HOME/Applications/terminal-notifier.app" ]
  [ ! -e "$TEST_TMP/brew/bin/terminal-notifier" ]
}

@test "_install_notifier_release reports a failed download" {
  load_cli
  mkdir -p "$TEST_TMP/brew/bin"
  stub brew "case \"\$1\" in --prefix) echo '$TEST_TMP/brew';; esac"
  stub curl 'exit 22'
  stub shasum
  stub ditto
  run core _install_notifier_release
  [ "$status" -eq 1 ]
  assert_output_contains "Download failed: https://github.com/julienXX/terminal-notifier/releases/download/3.1.0/terminal-notifier-3.1.0.zip"
  refute_stub_called '^shasum'
  refute_stub_called '^ditto'
}

@test "_install_notifier_release reports a failed unpack" {
  load_cli
  mkdir -p "$TEST_TMP/brew/bin"
  stub brew "case \"\$1\" in --prefix) echo '$TEST_TMP/brew';; esac"
  stub curl 'while [ $# -gt 0 ]; do [ "$1" = "-o" ] && echo "fake zip" > "$2"; shift; done'
  stub shasum "echo '$NOTIFIER_SHA  \$3'"
  stub ditto 'exit 1'
  run core _install_notifier_release
  [ "$status" -eq 1 ]
  assert_output_contains "Installing terminal-notifier failed."
  [ ! -e "$TEST_TMP/brew/bin/terminal-notifier" ]
}

# --- install ---------------------------------------------------------------

@test "install recognises an existing ~/.labelvier that is already on the PATH" {
  make_cli_git
  load_cli_copy
  mkdir -p "$HOME/.labelvier"
  export PATH="$HOME/.labelvier:$PATH"
  export CONFIRM=no
  run core install
  [ "$status" -eq 0 ]
  assert_output_contains "The CLI is already installed in $HOME/.labelvier"
  assert_output_contains "labelvier is already present in the \$PATH variable"
  assert_output_contains "Run it later with: labelvier setup"
  # nothing was moved
  [ -f "$CLI_COPY/labelvier" ]
}

@test "install offers the shell profiles for the PATH and respects Cancel" {
  make_cli_git
  load_cli_copy
  mkdir -p "$HOME/.labelvier"
  export CONFIRM=no
  run core install <<< "4"
  [ "$status" -eq 0 ]
  assert_output_contains "To which shell do you want to add the CLI to the \$PATH variable?"
  assert_output_contains "The CLI is not added to the \$PATH variable"
  [ ! -f "$HOME/.zshrc" ]
}

@test "install adds ~/.labelvier to the chosen shell profile" {
  make_cli_git
  load_cli_copy
  mkdir -p "$HOME/.labelvier"
  export CONFIRM=no
  run core install <<< "2"
  [ "$status" -eq 0 ]
  grep -qx 'export PATH=$PATH:$HOME/.labelvier' "$HOME/.zshrc"
  assert_output_contains "now restart your zsh shell"
}
