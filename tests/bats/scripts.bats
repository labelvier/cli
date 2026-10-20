#!/usr/bin/env bats
# scripts/changelog-section.sh and scripts/install.sh, fully offline.

bats_require_minimum_version 1.5.0
load test_helper
setup()    { setup_sandbox; }
teardown() { teardown_sandbox; }

# --- changelog-section.sh ---------------------------------------------------

# The script reads CHANGELOG.md from its own parent directory, so a copy of it
# goes into a fake project in the sandbox next to a changelog we control.
make_changelog_project() {
  PROJECT="$TEST_TMP/project"
  mkdir -p "$PROJECT/scripts"
  cp "$CLI_ROOT/scripts/changelog-section.sh" "$PROJECT/scripts/"
  cat > "$PROJECT/CHANGELOG.md" <<'EOF'
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Something not released yet

## [1.1.0] - 2026-10-20

### Added
- First feature of 1.1.0

### Fixed
- A bug in 1.1.0

## [1.0.1] - 2026-09-01

### Fixed
- Patch fix

## [1.0.0] - 2026-08-01

### Added
- Initial release
EOF
  CHANGELOG_SECTION="$PROJECT/scripts/changelog-section.sh"
}

@test "changelog-section prints the body of a middle version without its heading" {
  make_changelog_project
  run bash "$CHANGELOG_SECTION" 1.0.1
  [ "$status" -eq 0 ]
  [ "$output" = $'### Fixed\n- Patch fix' ]
}

@test "changelog-section: the first section stops before the next version and excludes Unreleased" {
  make_changelog_project
  run bash "$CHANGELOG_SECTION" 1.1.0
  [ "$status" -eq 0 ]
  assert_output_contains "First feature of 1.1.0"
  assert_output_contains "A bug in 1.1.0"
  refute_output_contains "Patch fix"
  refute_output_contains "not released yet"
  refute_output_contains "## ["
}

@test "changelog-section: the last section runs to the end of the file, trimmed" {
  make_changelog_project
  run bash "$CHANGELOG_SECTION" 1.0.0
  [ "$status" -eq 0 ]
  [ "$output" = $'### Added\n- Initial release' ]
}

@test "changelog-section fails for a version that is not in the changelog" {
  make_changelog_project
  run bash "$CHANGELOG_SECTION" 9.9.9
  [ "$status" -eq 1 ]
  assert_output_contains "No changelog section found for 9.9.9"
}

@test "changelog-section does not strip a v prefix (tags carry none)" {
  make_changelog_project
  run bash "$CHANGELOG_SECTION" v1.0.1
  [ "$status" -eq 1 ]
  assert_output_contains "No changelog section found for v1.0.1"
}

@test "changelog-section treats an empty section as missing" {
  make_changelog_project
  printf '\n## [2.0.0] - 2026-11-01\n\n\n' >> "$PROJECT/CHANGELOG.md"
  run bash "$CHANGELOG_SECTION" 2.0.0
  [ "$status" -eq 1 ]
  assert_output_contains "No changelog section found for 2.0.0"
}

@test "changelog-section without a version prints usage and exits 1" {
  make_changelog_project
  run bash "$CHANGELOG_SECTION"
  [ "$status" -eq 1 ]
  assert_output_contains "Usage: changelog-section.sh <version>"
}

@test "changelog-section fails when there is no CHANGELOG.md" {
  make_changelog_project
  rm "$PROJECT/CHANGELOG.md"
  run bash "$CHANGELOG_SECTION" 1.0.0
  [ "$status" -eq 1 ]
  assert_output_contains "No CHANGELOG.md found"
}

# --- install.sh --------------------------------------------------------------

INSTALL_SH="$CLI_ROOT/scripts/install.sh"

# git stub: `git clone <url> <dir>` materialises a fake checkout; every other
# git call (fetch, checkout, pull, symbolic-ref) just succeeds. Pass "pinned"
# to make `symbolic-ref` fail, i.e. a detached HEAD.
stub_git() {
  local mode="${1:-branch}"
  stub git '
    if [ "$1" = clone ]; then
      mkdir -p "$3/.git"
      printf "#!/bin/bash\necho fake labelvier\n" > "$3/labelvier"
      exit 0
    fi
    if [ "$1" = -C ] && [ "$3" = symbolic-ref ]; then exit '"$([ "$mode" = pinned ] && echo 1 || echo 0)"'; fi
    exit 0'
}

# A pre-existing install, as a second run of the installer finds it.
make_existing_install() {
  local dir="$1"
  mkdir -p "$dir/.git"
  printf '#!/bin/bash\necho fake labelvier\n' > "$dir/labelvier"
}

install_setup() {
  stub_git "$@"
  stub brew
  stub curl
  stub node
  stub npm
  export SHELL=/bin/zsh
  unset LABELVIER_CLI_DIR LABELVIER_CLI_REF
}

@test "install clones the repo into ~/.labelvier and adds it to .zshrc" {
  install_setup
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  assert_stub_called "^git clone https://github.com/labelvier/cli.git $HOME/.labelvier$"
  refute_stub_called '^git -C .* checkout'
  [ -x "$HOME/.labelvier/labelvier" ]
  assert_output_contains "Label Vier CLI"
  assert_output_contains "Cloning labelvier/cli to $HOME/.labelvier..."
  assert_output_contains "Added $HOME/.labelvier to \$PATH in $HOME/.zshrc."
  assert_output_contains "Installed! Run 'labelvier setup'"
  assert_output_contains "source $HOME/.zshrc"
  refute_output_contains "Pinned to"
  [ "$(cat "$HOME/.zshrc")" = "export PATH=\$PATH:$HOME/.labelvier" ]
  refute_stub_called '^(brew|curl|node|npm) '
}

@test "install honours LABELVIER_CLI_DIR as the target directory" {
  install_setup
  export LABELVIER_CLI_DIR="$TEST_TMP/elsewhere/cli"
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  assert_stub_called "^git clone https://github.com/labelvier/cli.git $TEST_TMP/elsewhere/cli$"
  [ -x "$TEST_TMP/elsewhere/cli/labelvier" ]
  [ ! -d "$HOME/.labelvier" ]
  grep -qF "$TEST_TMP/elsewhere/cli" "$HOME/.zshrc"
}

@test "install checks out the version given as argument (bash -s -- <tag>)" {
  install_setup
  run bash -s -- 1.2.3 < "$INSTALL_SH"
  [ "$status" -eq 0 ]
  assert_stub_called '^git clone '
  assert_stub_called "^git -C $HOME/.labelvier checkout --quiet 1.2.3$"
  assert_output_contains "Pinned to 1.2.3."
}

@test "install checks out the version given through LABELVIER_CLI_REF" {
  install_setup
  export LABELVIER_CLI_REF=1.0.9
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  assert_stub_called "^git -C $HOME/.labelvier checkout --quiet 1.0.9$"
  assert_output_contains "Pinned to 1.0.9."
}

@test "install: the argument wins over LABELVIER_CLI_REF" {
  install_setup
  export LABELVIER_CLI_REF=1.0.9
  run bash "$INSTALL_SH" 2.0.0
  [ "$status" -eq 0 ]
  assert_stub_called "checkout --quiet 2.0.0$"
  refute_stub_called "checkout --quiet 1.0.9"
}

@test "install fails and installs nothing when git is missing" {
  stub brew; stub curl; stub node; stub npm
  export SHELL=/bin/zsh
  # Only the stub dir on PATH: no git anywhere.
  run -127 env PATH="$STUB_DIR" bash "$INSTALL_SH"
  [ "$status" -ne 0 ]
  [ ! -d "$HOME/.labelvier" ]
  [ ! -f "$HOME/.zshrc" ]
  refute_output_contains "Installed!"
}

@test "install fails when the clone fails" {
  stub git 'echo "fatal: could not resolve host" >&2; exit 128'
  export SHELL=/bin/zsh
  run bash "$INSTALL_SH"
  [ "$status" -eq 128 ]
  [ ! -f "$HOME/.labelvier/labelvier" ]
  [ ! -f "$HOME/.zshrc" ]
}

@test "install run twice updates in place and adds the PATH line only once" {
  install_setup
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  : > "$STUB_LOG"
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  assert_output_contains "Already installed at $HOME/.labelvier — updating..."
  refute_stub_called '^git clone'
  assert_stub_called "^git -C $HOME/.labelvier fetch --tags --force --quiet$"
  assert_stub_called "^git -C $HOME/.labelvier pull --ff-only$"
  assert_output_contains "$HOME/.zshrc already points at $HOME/.labelvier."
  [ "$(grep -c "$HOME/.labelvier" "$HOME/.zshrc")" -eq 1 ]
  refute_output_contains "Cloning"
}

@test "install over an existing install with a version checks out that version" {
  install_setup
  make_existing_install "$HOME/.labelvier"
  run bash "$INSTALL_SH" 1.5.0
  [ "$status" -eq 0 ]
  refute_stub_called '^git clone'
  assert_stub_called "^git -C $HOME/.labelvier checkout --quiet 1.5.0$"
  refute_stub_called 'pull --ff-only'
  assert_output_contains "Pinned to 1.5.0."
}

@test "install over a pinned install without a version moves back to master" {
  install_setup pinned
  make_existing_install "$HOME/.labelvier"
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  assert_output_contains "Was pinned to a release — moving back to master."
  assert_stub_called "^git -C $HOME/.labelvier checkout --quiet master$"
  assert_stub_called "^git -C $HOME/.labelvier pull --ff-only$"
}

@test "install writes to .bash_profile for bash" {
  install_setup
  export SHELL=/bin/bash
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.bash_profile")" = "export PATH=\$PATH:$HOME/.labelvier" ]
  [ ! -f "$HOME/.profile" ]
  assert_output_contains "in $HOME/.bash_profile."
}

@test "install prefers an existing .profile for bash when there is no .bash_profile" {
  install_setup
  export SHELL=/bin/bash
  echo "# existing" > "$HOME/.profile"
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  grep -qF "export PATH=\$PATH:$HOME/.labelvier" "$HOME/.profile"
  [ ! -f "$HOME/.bash_profile" ]
}

@test "install writes a fish-style line to config.fish for fish" {
  install_setup
  export SHELL=/opt/homebrew/bin/fish
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.config/fish/config.fish")" = "set -gx PATH \$PATH $HOME/.labelvier" ]
  assert_output_contains "source $HOME/.config/fish/config.fish"
}

@test "install tells the user what to add for an unknown shell" {
  install_setup
  export SHELL=/bin/tcsh
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  assert_output_contains "Could not detect your shell (\$SHELL=/bin/tcsh)"
  assert_output_contains "export PATH=\$PATH:$HOME/.labelvier"
  [ ! -f "$HOME/.zshrc" ]
  refute_output_contains "Run this to use labelvier in this terminal"
}

@test "install skips the profile when the target is already on PATH" {
  install_setup
  run env PATH="$PATH:$HOME/.labelvier" bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  assert_output_contains "labelvier is already on your \$PATH."
  [ ! -f "$HOME/.zshrc" ]
  refute_output_contains "Run this to use labelvier in this terminal"
}

@test "install never starts a new shell when output is not a terminal" {
  install_setup
  export SHELL="$STUB_DIR/zsh"
  stub zsh 'echo "NEW SHELL STARTED"'
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  refute_stub_called '^zsh'
  refute_output_contains "Starting a new shell"
}
