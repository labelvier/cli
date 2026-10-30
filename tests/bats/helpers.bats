#!/usr/bin/env bats
# Unit tests for every helper in inc/helpers.sh, loaded with load_cli.
#
# Helpers that ask on /dev/tty (_confirm and everything built on it) are run in
# a child bash: without a controlling terminal (perl setsid) for the "no
# terminal" path, and under expect for the y/n paths. Helpers that look for
# brew/node/npm on PATH get a PATH without the developer's real tools.

load test_helper

setup() {
  setup_sandbox
  load_cli
  # The same functions, re-sourced inside a child bash (see run_in_cli).
  CLI_PRELUDE="__dir=\"$CLI_ROOT\"; __red=\"$__red\"; __blue=\"$__blue\"; __green=\"$__green\"; __bold=\"$__bold\"; __reset=\"$__reset\"; for f in \"$CLI_ROOT\"/inc/*.sh; do source \"\$f\"; done"
  # PATH with the stubs and the base system only: no Homebrew, nvm, node or npm.
  BARE_PATH="$STUB_DIR:/usr/bin:/bin"
  cat > "$TEST_TMP/confirm.exp" <<'EXP'
set timeout 10
set answer [lindex $argv 0]
set cmd [lindex $argv 1]
spawn bash -c $cmd
expect "Y/n"
send "$answer\r"
expect eof
EXP
}
teardown() { teardown_sandbox; }

# run_in_cli <bash code>: run it in a child bash with the CLI functions loaded.
run_in_cli() { run bash -c "$CLI_PRELUDE; $1"; }

# Same, but detached from any controlling terminal, so /dev/tty cannot be opened.
run_in_cli_notty() {
  run perl -e 'use POSIX; POSIX::setsid(); exec @ARGV' -- bash -c "$CLI_PRELUDE; $1"
}

# run_in_cli_tty <answer> <bash code>: run it on a pty and answer the [Y/n] question.
run_in_cli_tty() {
  command -v expect >/dev/null 2>&1 || skip "expect is not installed"
  run expect "$TEST_TMP/confirm.exp" "$1" "$CLI_PRELUDE; $2"
}

# A fake nvm.sh in $NVM_DIR: defines an nvm function that logs its calls and,
# on `nvm install`, drops a node stub on PATH.
make_fake_nvm() {
  export NVM_DIR="$HOME/.nvm"
  mkdir -p "$NVM_DIR"
  cat > "$NVM_DIR/nvm.sh" <<'NVM'
nvm() {
  printf '%s\n' "nvm $*" >> "$STUB_LOG"
  if [ "$1" = "install" ]; then
    printf '#!/bin/bash\necho v22.0.0\n' > "$STUB_DIR/node"
    chmod +x "$STUB_DIR/node"
  fi
}
NVM
}

# Replacement _load_nvm that only looks in $NVM_DIR. The real one also tries
# Homebrew's nvm.sh, which exists on a developer Mac and would always load.
LOAD_NVM_FROM_NVM_DIR='_load_nvm() { type nvm >/dev/null 2>&1 && return 0; [ -s "$NVM_DIR/nvm.sh" ] || return 1; . "$NVM_DIR/nvm.sh"; }'

# ---------------------------------------------------------------- _dispatch

@test "_dispatch without a subcommand prints the file's documentation" {
  run _dispatch hello.sh
  [ "$status" -eq 0 ]
  assert_output_contains "Available functions:"
  assert_output_contains "world - Echo hello with possible arguments"
  refute_output_contains "Unknown command"
}

@test "_dispatch with a flag-like subcommand prints the documentation without an error" {
  run _dispatch hello.sh --help
  [ "$status" -eq 0 ]
  assert_output_contains "Available functions:"
  refute_output_contains "Unknown command"
  run _dispatch hello.sh -x
  [ "$status" -eq 0 ]
  assert_output_contains "Available functions:"
  refute_output_contains "Unknown command"
}

@test "_dispatch returns 0 when it only prints the documentation" {
  run _dispatch hello.sh
  [ "$status" -eq 0 ]
  run _dispatch hello.sh --help
  [ "$status" -eq 0 ]
}

@test "_dispatch reports an unknown subcommand, shows the docs and fails" {
  run _dispatch hello.sh nope
  [ "$status" -eq 1 ]
  assert_output_contains "✗ Unknown command: nope"
  assert_output_contains "Available functions:"
}

@test "_dispatch <sub> --help prints the description instead of running the function" {
  world() { echo "RAN world with: $*"; }
  run _dispatch hello.sh world --help
  assert_output_contains "world - Echo hello with possible arguments"
  refute_output_contains "RAN world"
}

@test "_dispatch runs the subcommand with the remaining arguments" {
  world() { echo "RAN world with: $*"; return 7; }
  run _dispatch hello.sh world one --two "three four"
  [ "$status" -eq 7 ]
  [ "$output" = "RAN world with: one --two three four" ]
}

@test "_dispatch only treats --help specially right after the subcommand" {
  world() { echo "RAN world with: $*"; }
  run _dispatch hello.sh world arg --help
  [ "$output" = "RAN world with: arg --help" ]
}

# ------------------------------------------------------ _echo_documentation

@test "_echo_documentation lists every @function with its @description" {
  run _echo_documentation release.sh
  assert_output_contains "Available functions:"
  assert_output_contains "start"
  assert_output_contains "finish"
  assert_output_contains "cancel"
  [ "$(plain_output | grep -c ' - ')" -gt 3 ]
}

@test "_echo_documentation keeps usage arguments that follow the function name" {
  run _echo_documentation hello.sh
  [ "$(plain_output | sed -n 2p)" = "  world - Echo hello with possible arguments" ]
}

# ------------------------------------------------ _echo_function_description

@test "_echo_function_description prints the matching description and returns 0" {
  run _echo_function_description hello.sh world
  [ "$status" -eq 0 ]
  [ "$(plain_output)" = "world - Echo hello with possible arguments" ]
}

@test "_echo_function_description matches on the first word of the @function line" {
  run _echo_function_description cron.sh deploy
  [ "$status" -eq 0 ]
  assert_output_contains "deploy - Deploy the cron job to a server"
}

@test "_echo_function_description prints only the name and returns 1 when undocumented" {
  run _echo_function_description hello.sh nope
  [ "$status" -eq 1 ]
  [ "$(plain_output)" = "nope" ]
}

# --------------------------------------------------------- _flag_is_present

@test "_flag_is_present finds a flag anywhere in the arguments" {
  run _flag_is_present force --force
  [ "$status" -eq 0 ]
  run _flag_is_present force start 1.2.3 --force
  [ "$status" -eq 0 ]
  run _flag_is_present force --force start 1.2.3
  [ "$status" -eq 0 ]
}

@test "_flag_is_present fails when the flag is absent" {
  run _flag_is_present force
  [ "$status" -eq 1 ]
  run _flag_is_present force start --minor
  [ "$status" -eq 1 ]
}

@test "_flag_is_present wants the exact --flag form" {
  run _flag_is_present force force
  [ "$status" -eq 1 ]
  run _flag_is_present force -force
  [ "$status" -eq 1 ]
  run _flag_is_present force --force=yes
  [ "$status" -eq 1 ]
  run _flag_is_present force --forced
  [ "$status" -eq 1 ]
}

@test "_flag_is_present also matches a flag given as another option's value" {
  run _flag_is_present force --name --force
  [ "$status" -eq 0 ]
}

# ----------------------------------------------------- _is_semantic_version

@test "_is_semantic_version accepts MAJOR.MINOR.PATCH" {
  run _is_semantic_version 1.2.3
  [ "$status" -eq 0 ]
  run _is_semantic_version 0.0.0
  [ "$status" -eq 0 ]
  run _is_semantic_version 10.200.3000
  [ "$status" -eq 0 ]
}

@test "_is_semantic_version ignores a dash or space suffix" {
  run _is_semantic_version 1.2.3-beta.1
  [ "$status" -eq 0 ]
  run _is_semantic_version "1.2.3 (final)"
  [ "$status" -eq 0 ]
}

@test "_is_semantic_version rejects anything else" {
  run _is_semantic_version banana
  [ "$status" -eq 1 ]
  run _is_semantic_version 1.2
  [ "$status" -eq 1 ]
  run _is_semantic_version 1.2.3.4
  [ "$status" -eq 1 ]
  run _is_semantic_version ""
  [ "$status" -eq 1 ]
  run _is_semantic_version "1.2.x"
  [ "$status" -eq 1 ]
}

@test "_is_semantic_version does not accept a v prefix" {
  run _is_semantic_version v1.2.3
  [ "$status" -eq 1 ]
}

# ----------------------------------------------------------------- _confirm

@test "_confirm returns 0 on y" {
  run_in_cli_tty y '_confirm "Go?"; echo "rc=$?"'
  assert_output_contains "Go? [Y/n]"
  assert_output_contains "rc=0"
}

@test "_confirm returns 1 on n" {
  run_in_cli_tty n '_confirm "Go?"; echo "rc=$?"'
  assert_output_contains "rc=1"
}

@test "_confirm treats an empty answer as yes" {
  run_in_cli_tty "" '_confirm "Go?"; echo "rc=$?"'
  assert_output_contains "rc=0"
}

@test "_confirm default-no treats an empty answer as no" {
  run_in_cli_tty "" '_confirm "Go?" default-no; echo "rc=$?"'
  assert_output_contains "Go? [y/N]"
  assert_output_contains "rc=1"
}

@test "_confirm default-no returns 0 on y" {
  run_in_cli_tty y '_confirm "Go?" default-no; echo "rc=$?"'
  assert_output_contains "rc=0"
}

@test "_confirm_remembered default-no stores a no on Enter" {
  run_in_cli_tty "" '_confirm_remembered fa "Go?" only-no default-no; echo "rc=$?"'
  assert_output_contains "rc=1"
  [ "$(sed -n 's/^fa=//p' "$HOME/.config/labelvier/choices")" = "no" ]
}

@test "_confirm returns 2 and says so when there is no terminal" {
  run_in_cli_notty '_confirm "Go?"; echo "rc=$?"'
  assert_output_contains "Go? [Y/n] (no terminal to ask on, skipped)"
  assert_output_contains "rc=2"
}

@test "_confirm does not read its answer from stdin" {
  run_in_cli_notty '_confirm "Go?" <<< "n"; echo "rc=$?"'
  assert_output_contains "rc=2"
}

# -------------------------------------------- _needs_active_wptakeoff_project

@test "_needs_active_wptakeoff_project passes silently in a project root" {
  make_env "DEV_THEME_PATH=wp-content/themes/mytheme"
  mkdir -p wp-content/themes/mytheme/src/scss
  touch wp-content/themes/mytheme/src/scss/style.scss
  run _needs_active_wptakeoff_project
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_needs_active_wptakeoff_project exits 1 when DEV_THEME_PATH is empty" {
  make_env "DEV_THEME_PATH="
  run _needs_active_wptakeoff_project
  [ "$status" -eq 1 ]
  assert_output_contains "DEV_THEME_PATH is not set in the .env file"
}

@test "_needs_active_wptakeoff_project exits 1 when the theme has no style.scss" {
  make_env "DEV_THEME_PATH=wp-content/themes/mytheme"
  mkdir -p wp-content/themes/mytheme
  run _needs_active_wptakeoff_project
  [ "$status" -eq 1 ]
  assert_output_contains "You are not in the right directory."
  assert_output_contains "./wp-content/themes/mytheme/src/scss/style.scss"
}

@test "_needs_active_wptakeoff_project exits 1 without a .env file" {
  run _needs_active_wptakeoff_project
  [ "$status" -eq 1 ]
  assert_output_contains "You are not in the right directory."
}

# ------------------------------------------------------------ _require_brew

@test "_require_brew is silent and succeeds when brew is on PATH" {
  stub brew
  run _require_brew
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(stub_calls)" ]
}

@test "_require_brew returns 1 without installing when there is no terminal to ask on" {
  stub curl 'exit 1'
  PATH="$BARE_PATH" run_in_cli_notty '_require_brew; echo "rc=$?"'
  assert_output_contains "Homebrew is not installed."
  assert_output_contains "Install Homebrew now? [Y/n] (no terminal to ask on, skipped)"
  assert_output_contains "rc=1"
  refute_stub_called '^curl'
}

@test "_require_brew returns 1 without installing when the install is declined" {
  stub curl 'exit 1'
  PATH="$BARE_PATH" run_in_cli_tty n '_require_brew; echo "rc=$?"'
  assert_output_contains "Homebrew is not installed."
  assert_output_contains "rc=1"
  refute_stub_called '^curl'
}

# ---------------------------------------------------------------- _load_nvm

@test "_load_nvm succeeds at once when nvm is already a function" {
  nvm() { :; }
  export NVM_DIR="$TEST_TMP/no-such-nvm"
  run _load_nvm
  [ "$status" -eq 0 ]
}

@test "_load_nvm sources nvm.sh from NVM_DIR and defaults NVM_DIR to ~/.nvm" {
  make_fake_nvm
  unset NVM_DIR
  run_in_cli '_load_nvm && type nvm | head -1 && echo "NVM_DIR=$NVM_DIR"'
  [ "$status" -eq 0 ]
  assert_output_contains "nvm is a function"
  assert_output_contains "NVM_DIR=$HOME/.nvm"
}

@test "_load_nvm returns 1 when no nvm.sh exists anywhere" {
  if [ -s /opt/homebrew/opt/nvm/nvm.sh ] || [ -s /usr/local/opt/nvm/nvm.sh ]; then
    skip "this machine has Homebrew's nvm.sh, which _load_nvm always finds"
  fi
  export NVM_DIR="$TEST_TMP/no-such-nvm"
  PATH="$BARE_PATH" run_in_cli '_load_nvm; echo "rc=$?"'
  assert_output_contains "rc=1"
}

# ------------------------------------------------------------- _require_nvm

@test "_require_nvm reports a check mark when nvm loads" {
  make_fake_nvm
  run_in_cli '_require_nvm'
  [ "$status" -eq 0 ]
  assert_output_contains "✓ nvm"
}

@test "_require_nvm points at Homebrew first when neither nvm nor brew exist" {
  export NVM_DIR="$TEST_TMP/no-such-nvm"
  PATH="$BARE_PATH" run_in_cli "$LOAD_NVM_FROM_NVM_DIR; _require_nvm; echo rc=\$?"
  assert_output_contains "✗ nvm is not installed"
  assert_output_contains "Install Homebrew first, then run: brew install nvm"
  assert_output_contains "rc=1"
}

@test "_require_nvm skips the brew install when there is no terminal to ask on" {
  stub brew
  export NVM_DIR="$TEST_TMP/no-such-nvm"
  PATH="$BARE_PATH" run_in_cli_notty "$LOAD_NVM_FROM_NVM_DIR; _require_nvm; echo rc=\$?"
  assert_output_contains "Skipped. Install it yourself:"
  assert_output_contains "rc=1"
  refute_stub_called '^brew install'
}

@test "_require_nvm skips the brew install when declined" {
  stub brew
  export NVM_DIR="$TEST_TMP/no-such-nvm"
  PATH="$BARE_PATH" run_in_cli_tty n "$LOAD_NVM_FROM_NVM_DIR; _require_nvm; echo rc=\$?"
  assert_output_contains "Skipped. Install it yourself:"
  assert_output_contains "rc=1"
  refute_stub_called '^brew install'
}

@test "_require_nvm installs nvm with brew, loads it and persists the profile when accepted" {
  export NVM_DIR="$HOME/.nvm"
  export SHELL=/bin/zsh
  # `brew install nvm` drops the fake nvm.sh into NVM_DIR; `brew --prefix nvm` has none.
  stub brew 'case "$*" in "install nvm") mkdir -p "$NVM_DIR"; echo "nvm() { :; }" > "$NVM_DIR/nvm.sh" ;; "--prefix nvm") echo "$TEST_TMP/no-brew-nvm" ;; esac'
  PATH="$BARE_PATH" run_in_cli_tty y "$LOAD_NVM_FROM_NVM_DIR; _require_nvm; echo rc=\$?"
  assert_output_contains "✓ nvm installed"
  assert_output_contains "nvm added to $HOME/.zshrc"
  assert_output_contains "rc=0"
  assert_stub_called '^brew install nvm$'
  grep -q 'export NVM_DIR="$HOME/.nvm"' "$HOME/.zshrc"
}

@test "_require_nvm fails when brew install nvm fails" {
  stub brew 'case "$*" in "install nvm") exit 1 ;; esac'
  export NVM_DIR="$TEST_TMP/no-such-nvm"
  PATH="$BARE_PATH" run_in_cli_tty y "$LOAD_NVM_FROM_NVM_DIR; _require_nvm; echo rc=\$?"
  assert_output_contains "rc=1"
  refute_output_contains "nvm installed"
}

# ------------------------------------------------------ _persist_nvm_profile

@test "_persist_nvm_profile appends the nvm lines to .zshrc for zsh" {
  export SHELL=/bin/zsh NVM_DIR="$HOME/.nvm"
  stub brew 'echo "$TEST_TMP/no-brew-nvm"'
  run _persist_nvm_profile
  [ "$status" -eq 0 ]
  assert_output_contains "✓ nvm added to $HOME/.zshrc"
  grep -q '# Added by labelvier: load nvm' "$HOME/.zshrc"
  grep -q 'export NVM_DIR="$HOME/.nvm"' "$HOME/.zshrc"
  grep -qF "[ -s \"$HOME/.nvm/nvm.sh\" ] && . \"$HOME/.nvm/nvm.sh\"" "$HOME/.zshrc"
}

@test "_persist_nvm_profile writes to .bash_profile for bash" {
  export SHELL=/bin/bash NVM_DIR="$HOME/.nvm"
  stub brew 'echo "$TEST_TMP/no-brew-nvm"'
  run _persist_nvm_profile
  [ "$status" -eq 0 ]
  assert_output_contains "nvm added to $HOME/.bash_profile"
  grep -q NVM_DIR "$HOME/.bash_profile"
  [ ! -f "$HOME/.zshrc" ]
}

@test "_persist_nvm_profile prefers Homebrew's nvm.sh when it exists" {
  export SHELL=/bin/zsh NVM_DIR="$HOME/.nvm"
  mkdir -p "$TEST_TMP/brew-nvm"
  echo 'nvm() { :; }' > "$TEST_TMP/brew-nvm/nvm.sh"
  stub brew "echo \"$TEST_TMP/brew-nvm\""
  run _persist_nvm_profile
  [ "$status" -eq 0 ]
  grep -qF "$TEST_TMP/brew-nvm/nvm.sh" "$HOME/.zshrc"
}

@test "_persist_nvm_profile is idempotent" {
  export SHELL=/bin/zsh NVM_DIR="$HOME/.nvm"
  stub brew 'echo "$TEST_TMP/no-brew-nvm"'
  _persist_nvm_profile >/dev/null
  run _persist_nvm_profile
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(grep -c NVM_DIR "$HOME/.zshrc")" -eq 1 ]
}

@test "_persist_nvm_profile leaves the profile alone when another profile already has NVM_DIR" {
  export SHELL=/bin/zsh NVM_DIR="$HOME/.nvm"
  echo 'export NVM_DIR="$HOME/.nvm"' > "$HOME/.zprofile"
  run _persist_nvm_profile
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$HOME/.zshrc" ]
}

# ------------------------------------------------------------ _require_node

@test "_require_node reports the node version when node is on PATH" {
  stub node 'echo v20.1.0'
  run _require_node
  [ "$status" -eq 0 ]
  [ "$(plain_output)" = "✓ node (v20.1.0)" ]
}

@test "_require_node asks for nvm first when neither node nor nvm exist" {
  export NVM_DIR="$TEST_TMP/no-such-nvm"
  PATH="$BARE_PATH" run_in_cli "$LOAD_NVM_FROM_NVM_DIR; _require_node; echo rc=\$?"
  assert_output_contains "✗ node is not installed"
  assert_output_contains "Install nvm first, then run: nvm install --lts"
  assert_output_contains "rc=1"
}

@test "_require_node skips the install when there is no terminal to ask on" {
  make_fake_nvm
  PATH="$BARE_PATH" run_in_cli_notty "$LOAD_NVM_FROM_NVM_DIR; _require_node; echo rc=\$?"
  assert_output_contains "Skipped."
  assert_output_contains "rc=1"
  refute_stub_called '^nvm install'
}

@test "_require_node installs the LTS release through nvm when accepted" {
  make_fake_nvm
  PATH="$BARE_PATH" run_in_cli_tty y "$LOAD_NVM_FROM_NVM_DIR; _require_node; echo rc=\$?"
  assert_output_contains "✓ node v22.0.0 installed"
  assert_output_contains "rc=0"
  assert_stub_called '^nvm install --lts$'
  assert_stub_called '^nvm alias default lts/\*$'
}

# ------------------------------------------------------------- _require_npm

@test "_require_npm is silent and succeeds when npm is on PATH" {
  stub npm
  run _require_npm
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_require_npm finds npm through nvm when it is not on PATH yet" {
  make_fake_nvm
  # Sourcing the fake nvm.sh puts an npm stub on PATH, as nvm's default Node would.
  echo "printf '#!/bin/bash\\nexit 0\\n' > \"$STUB_DIR/npm\"; chmod +x \"$STUB_DIR/npm\"" >> "$NVM_DIR/nvm.sh"
  PATH="$BARE_PATH" run_in_cli "$LOAD_NVM_FROM_NVM_DIR; _require_npm; echo rc=\$?"
  [ "$(plain_output)" = "rc=0" ]
}

@test "_require_npm walks brew, nvm and node and fails when nothing can be installed" {
  export NVM_DIR="$TEST_TMP/no-such-nvm"
  stub curl 'exit 1'
  PATH="$BARE_PATH" run_in_cli_notty "$LOAD_NVM_FROM_NVM_DIR; _require_npm; echo rc=\$?"
  assert_output_contains "Homebrew is not installed."
  assert_output_contains "✗ nvm is not installed"
  assert_output_contains "Install Homebrew first, then run: brew install nvm"
  assert_output_contains "rc=1"
  refute_stub_called '^curl'
}

# ------------------------------------------------ remembered choices

@test "_choice_set stores an answer, replaces it and keeps the others" {
  export LABELVIER_CHOICES_FILE="$TEST_TMP/choices"
  _choice_set fa no
  _choice_set auto_update yes
  _choice_set fa yes
  [ "$(_choice_get fa)" = "yes" ]
  [ "$(_choice_get auto_update)" = "yes" ]
  [ "$(grep -c '^fa=' "$LABELVIER_CHOICES_FILE")" -eq 1 ]
}

@test "_choice_get prints nothing without a stored answer or file" {
  export LABELVIER_CHOICES_FILE="$TEST_TMP/nope/choices"
  [ -z "$(_choice_get fa)" ]
}

@test "the choices file defaults to ~/.config/labelvier/choices" {
  unset LABELVIER_CHOICES_FILE
  _choice_set fa no
  [ -f "$HOME/.config/labelvier/choices" ]
  grep -qx 'fa=no' "$HOME/.config/labelvier/choices"
}

@test "_choice_reset forgets one key or all of them" {
  export LABELVIER_CHOICES_FILE="$TEST_TMP/choices"
  _choice_set fa no
  _choice_set setup_ai yes
  _choice_reset fa
  [ -z "$(_choice_get fa)" ]
  [ "$(_choice_get setup_ai)" = "yes" ]
  _choice_reset
  [ ! -e "$LABELVIER_CHOICES_FILE" ]
}

@test "_confirm_remembered asks, then stores a no and does not ask again" {
  export LABELVIER_CHOICES_FILE="$TEST_TMP/choices"
  run_in_cli_tty n '_confirm_remembered fa "Install fa?"; echo "rc=$?"'
  assert_output_contains "Install fa? [Y/n]"
  assert_output_contains "rc=1"
  [ "$(_choice_get fa)" = "no" ]

  run_in_cli_notty '_confirm_remembered fa "Install fa?"; echo "rc=$?"'
  assert_output_contains "Install fa? [remembered: no] (ask again with: labelvier core choices --reset fa)"
  assert_output_contains "rc=1"
  refute_output_contains "no terminal to ask on"
}

@test "_confirm_remembered stores a yes and reuses it" {
  export LABELVIER_CHOICES_FILE="$TEST_TMP/choices"
  run_in_cli_tty y '_confirm_remembered setup_ai "Run setup?"; echo "rc=$?"'
  assert_output_contains "rc=0"
  [ "$(_choice_get setup_ai)" = "yes" ]

  run_in_cli_notty '_confirm_remembered setup_ai "Run setup?"; echo "rc=$?"'
  assert_output_contains "Run setup? [remembered: yes]"
  assert_output_contains "rc=0"
}

@test "_confirm_remembered with only-no does not store a yes" {
  export LABELVIER_CHOICES_FILE="$TEST_TMP/choices"
  run_in_cli_tty y '_confirm_remembered fa "Install fa?" only-no; echo "rc=$?"'
  assert_output_contains "rc=0"
  [ -z "$(_choice_get fa)" ]

  # An old yes in the file does not skip the question either.
  _choice_set fa yes
  run_in_cli_notty '_confirm_remembered fa "Install fa?" only-no; echo "rc=$?"'
  assert_output_contains "no terminal to ask on"
  assert_output_contains "rc=2"
}

@test "_confirm_remembered stores nothing without a terminal" {
  export LABELVIER_CHOICES_FILE="$TEST_TMP/choices"
  run_in_cli_notty '_confirm_remembered fa "Install fa?"; echo "rc=$?"'
  assert_output_contains "rc=2"
  [ ! -e "$LABELVIER_CHOICES_FILE" ]
}
