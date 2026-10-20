#!/usr/bin/env bats
# inc/setup.sh: the new-colleague walkthrough. Every tool it checks is a stub,
# and the sandbox PATH holds only the stubs plus symlinks to the base utilities,
# so a tool is "absent" simply by not stubbing it, on any machine.
#
# `_confirm` asks on /dev/tty, not stdin. The CLI runs in its own session
# (perl setsid) so there is no controlling terminal: _confirm answers "no
# terminal to ask on" and nothing is ever installed, also when the suite runs
# from an interactive shell.

load test_helper

setup() {
  setup_sandbox
  minimal_path
  stub uname 'echo Darwin'
  stub xcode-select 'exit 0'
}
teardown() { teardown_sandbox; }

# PATH = stubs + symlinks to the base utilities the CLI and the asserts need.
minimal_path() {
  local bin="$TEST_TMP/bin" cmd path
  mkdir -p "$bin"
  for cmd in bash sh env cat grep sed awk cut tr dirname basename date head tail sort ls mkdir chmod touch rm cp mv wc tput; do
    path="$(command -v "$cmd" 2>/dev/null)" || continue
    [ -x "$path" ] && ln -sf "$path" "$bin/$cmd"
  done
  export PATH="$STUB_DIR:$bin"
}

# Run the CLI without a controlling terminal, so _confirm cannot block.
run_cli_notty() {
  run /usr/bin/perl -e 'use POSIX; POSIX::setsid(); exec @ARGV or die "exec: $!"' -- "$CLI" "$@"
}

# All required tools present: brew, git, jq, node, docker, composer as stubs and nvm as a fake nvm.sh.
stub_all_tools() {
  stub brew
  stub git
  stub jq
  stub node 'case "$1" in --version) echo v22.0.0 ;; esac'
  stub docker
  stub composer
  make_fake_nvm
}

# nvm is a shell function loaded from $NVM_DIR/nvm.sh; the fake one records its calls.
make_fake_nvm() {
  export NVM_DIR="$TEST_TMP/nvm"
  mkdir -p "$NVM_DIR"
  cat > "$NVM_DIR/nvm.sh" <<'EOF'
nvm() { printf '%s\n' "nvm $*" >> "$STUB_LOG"; }
EOF
}

# An empty NVM_DIR; nvm is then only found when Homebrew's nvm.sh exists on this machine.
no_nvm() {
  export NVM_DIR="$TEST_TMP/nvm-empty"
  mkdir -p "$NVM_DIR"
  for f in /opt/homebrew/opt/nvm/nvm.sh /usr/local/opt/nvm/nvm.sh; do
    [ -s "$f" ] && skip "Homebrew's nvm.sh at $f makes nvm present on this machine"
  done
  return 0
}

refute_installs() {
  refute_stub_called '^brew install'
  refute_stub_called '^nvm install'
  refute_stub_called '^xcode-select --install'
}

# --- dispatch ---------------------------------------------------------------

@test "bare setup runs the whole walkthrough instead of printing the docs" {
  stub uname 'echo Linux'
  stub_all_tools
  run_cli_notty setup
  [ "$status" -eq 0 ]
  refute_output_contains "Available functions:"
  assert_output_contains "Label Vier CLI setup"
  assert_output_contains "Nothing is installed without your yes."
  assert_output_contains "Tools"
  assert_output_contains "All required tools are installed."
  assert_output_contains "Notifications"
  assert_output_contains "Notifications are only supported on macOS."
  assert_output_contains "AI"
  assert_output_contains "Check and install the AI setup (Claude Code config, skills, Basecamp, rtk) now? [Y/n] (no terminal to ask on, skipped)"
  assert_output_contains "Ok, run it later with: labelvier ai update"
  refute_installs
}

@test "setup --help prints the docs" {
  run_cli_notty setup --help
  assert_output_contains "Available functions:"
  assert_output_contains "all"
  assert_output_contains "tools"
  refute_output_contains "Label Vier CLI setup"
}

@test "all --help and tools --help print their descriptions without running checks" {
  run_cli_notty setup all --help
  [ "$status" -eq 0 ]
  assert_output_contains "Walk through the whole setup"
  refute_output_contains "Label Vier CLI setup"

  run_cli_notty setup tools --help
  [ "$status" -eq 0 ]
  assert_output_contains "Check the required tools (Homebrew, git, jq, nvm, Node, Docker, Composer)"
  [ -z "$(stub_calls)" ]
}

@test "unknown subcommand is reported" {
  run_cli_notty setup nope
  [ "$status" -eq 1 ]
  assert_output_contains "Unknown command: nope"
  assert_output_contains "Available functions:"
}

# --- tools: everything present ----------------------------------------------

@test "tools reports every tool present on macOS and installs nothing" {
  stub_all_tools
  run_cli_notty setup tools
  [ "$status" -eq 0 ]
  assert_output_contains "✓ brew"
  assert_output_contains "✓ git"
  assert_output_contains "✓ jq"
  assert_output_contains "✓ nvm"
  assert_output_contains "✓ node (v22.0.0)"
  assert_output_contains "✓ docker"
  assert_output_contains "✓ composer"
  assert_output_contains "All required tools are installed."
  refute_output_contains "✗"
  assert_stub_called '^xcode-select -p$'
  assert_stub_called '^node --version$'
  refute_installs
}

# --- tools: absent paths ----------------------------------------------------

@test "tools: missing Xcode Command Line Tools block git and offer the installer" {
  stub_all_tools
  stub xcode-select 'exit 2'
  run_cli_notty setup tools
  [ "$status" -eq 1 ]
  assert_output_contains "✗ git needs the Xcode Command Line Tools, which are not installed."
  assert_output_contains "Open the installer for the Command Line Tools now? [Y/n] (no terminal to ask on, skipped)"
  assert_output_contains "Still missing: git. Run 'labelvier setup tools' again after fixing them."
  refute_stub_called '^xcode-select --install'
  refute_installs
}

@test "tools: a missing brew tool is offered via brew install and skipped without a yes" {
  stub_all_tools
  unstub jq
  run_cli_notty setup tools
  [ "$status" -eq 1 ]
  assert_output_contains "✗ jq is not installed (edits Claude Code settings and Zed config)."
  assert_output_contains "Install it now with 'brew install jq'? [Y/n] (no terminal to ask on, skipped)"
  assert_output_contains "Skipped."
  assert_output_contains "Still missing: jq."
  refute_installs
}

@test "tools: without Homebrew the missing tools point to a manual brew install" {
  stub_all_tools
  unstub brew
  unstub composer
  run_cli_notty setup tools
  [ "$status" -eq 1 ]
  assert_output_contains "Homebrew is not installed."
  assert_output_contains "Install Homebrew now? [Y/n] (no terminal to ask on, skipped)"
  assert_output_contains "✗ composer is not installed (needed by the zed commands)."
  assert_output_contains "Install Homebrew first, then run: brew install composer"
  assert_output_contains "Still missing: brew composer."
  refute_stub_called '^curl'
  refute_installs
}

@test "tools: missing node with nvm present offers nvm install --lts and skips without a yes" {
  stub_all_tools
  unstub node
  run_cli_notty setup tools
  [ "$status" -eq 1 ]
  assert_output_contains "✓ nvm"
  assert_output_contains "✗ node is not installed (npm builds the themes and installs the toon tool)."
  assert_output_contains "Install the latest LTS version with 'nvm install --lts'? [Y/n] (no terminal to ask on, skipped)"
  assert_output_contains "Skipped."
  assert_output_contains "Still missing: node."
  refute_installs
}

@test "tools: missing nvm and node reports both and sends node to nvm" {
  stub_all_tools
  unstub node
  no_nvm
  run_cli_notty setup tools
  [ "$status" -eq 1 ]
  assert_output_contains "✗ nvm is not installed (manages the Node.js version per project)."
  assert_output_contains "Install it now with 'brew install nvm'? [Y/n] (no terminal to ask on, skipped)"
  assert_output_contains "Skipped. Install it yourself: https://github.com/nvm-sh/nvm#installing-and-updating"
  assert_output_contains "✗ node is not installed"
  assert_output_contains "Install nvm first, then run: nvm install --lts"
  assert_output_contains "Still missing: nvm node."
  refute_installs
}

@test "tools: missing docker on Linux is a manual install" {
  [ -d /Applications/Docker.app ] && skip "/Applications/Docker.app exists on this machine and is checked before the OS"
  stub uname 'echo Linux'
  stub_all_tools
  unstub docker
  run_cli_notty setup tools
  [ "$status" -eq 1 ]
  assert_output_contains "✗ docker is not installed. Install it yourself: https://docs.docker.com/engine/install/"
  assert_output_contains "Still missing: docker."
  refute_stub_called 'docker-desktop'
  refute_installs
}

@test "tools: missing docker on macOS with Docker Desktop installed asks to open the app" {
  [ -d /Applications/Docker.app ] || skip "no /Applications/Docker.app on this machine"
  stub_all_tools
  unstub docker
  run_cli_notty setup tools
  [ "$status" -eq 1 ]
  assert_output_contains "✗ Docker Desktop is installed, but the docker command is not on your PATH yet."
  assert_output_contains "Open Docker Desktop once (open -a Docker), then run 'labelvier setup tools' again."
  assert_output_contains "Still missing: docker."
  refute_installs
}

@test "tools: missing docker on macOS without Docker Desktop offers the cask" {
  [ -d /Applications/Docker.app ] && skip "/Applications/Docker.app exists on this machine"
  stub_all_tools
  unstub docker
  run_cli_notty setup tools
  [ "$status" -eq 1 ]
  assert_output_contains "✗ docker is not installed (the WordPress projects run in Docker)."
  assert_output_contains "Install it now with 'brew install --cask docker-desktop'? [Y/n] (no terminal to ask on, skipped)"
  assert_output_contains "Skipped."
  assert_output_contains "Still missing: docker."
  refute_installs
}

@test "tools lists every missing tool at the end" {
  stub_all_tools
  unstub jq
  unstub composer
  run_cli_notty setup tools
  [ "$status" -eq 1 ]
  assert_output_contains "Still missing: jq composer."
  refute_installs
}
