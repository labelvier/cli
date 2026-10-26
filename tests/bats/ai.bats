#!/usr/bin/env bats
# inc/ai.sh: Claude Code setup (ai check / update / claude install|uninstall / basecamp).
#
# Two things shape these tests:
# - The sandbox PATH is cut down to the stubs plus the system dirs, so the
#   developer's own claude/rtk/toon/basecamp/npm are never found (and never run).
# - `_confirm` and the token prompt read /dev/tty, not stdin. Every CLI call
#   therefore runs through `run_ai`, which detaches from the controlling
#   terminal (setsid) so a test can never block on the developer's keyboard.
#   The yes-paths that need a terminal run under `expect`, which gives a pty.

load test_helper

setup() {
  setup_sandbox
  export PATH="$STUB_DIR:/usr/bin:/bin:/usr/sbin:/sbin"
  # _load_nvm would otherwise source the developer's nvm and find the real npm.
  export NVM_DIR="$HOME/.nvm"
  type -P jq >/dev/null 2>&1 || skip "jq is not installed (ai.sh needs it for settings.json)"

  CLAUDE_DIR="$HOME/.claude"
  ENV_FILE="$CLAUDE_DIR/.env"
  TPL_DIR="$CLI_ROOT/templates/claude"
  HOOK="$CLAUDE_DIR/hooks/basecamp-toon.sh"
  SETTINGS="$CLAUDE_DIR/settings.json"
  SKILL_DIR="$CLAUDE_DIR/skills/timesheet"
  DASH_SKILL="$CLAUDE_DIR/skills/label-vier-dashboard-api/SKILL.md"
  PLUGINS="$TEST_TMP/plugins"
  mkdir -p "$PLUGINS"

  # Never let a prompt or an installer reach the network or the machine.
  stub curl
  stub brew
  stub open
  stub osascript
  stub launchctl
  stub gh
  stub node
}

teardown() { teardown_sandbox; }

# --- helpers ---------------------------------------------------------------

# Runs `labelvier ai <args>` without a controlling terminal.
run_ai() {
  run perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$CLI" ai "$@"
}

# Runs `ai <args>` in a fresh shell with the CLI functions loaded, after
# eval-ing <code> (e.g. an override of _confirm), still without a terminal.
run_ai_with() {
  local code="$1"
  shift
  run perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' \
    bash -c 'source "$1"; load_cli; eval "$2"; shift 2; ai "$@"' _ \
    "$CLI_ROOT/tests/bats/test_helper.bash" "$code" "$@"
}

# The claude CLI: answers --version, keeps installed plugins as files in
# $PLUGINS, and logs "claude-stdin /dev/null" when its stdin is /dev/null.
stub_claude() {
  stub claude '
[ /dev/fd/0 -ef /dev/null ] && printf "%s\n" "claude-stdin /dev/null" >> "$STUB_LOG"
case "$1" in
  --version) echo "2.1.0 (Claude Code)" ;;
  plugin)
    case "$2" in
      list)
        sep=""; printf "["
        for f in "$TEST_TMP"/plugins/*; do
          [ -e "$f" ] || continue
          printf "%s{\"id\":\"%s\",\"enabled\":true}" "$sep" "$(basename "$f")"; sep=","
        done
        echo "]" ;;
      install) touch "$TEST_TMP/plugins/$3" ;;
      uninstall) rm -f "$TEST_TMP/plugins/$3" ;;
    esac ;;
esac
exit 0'
}

# Everything `ai claude install` and `ai check` look for, as stubs. fa stays
# missing on purpose (it is optional and its prompt reads stdin).
stub_toolchain() {
  stub_claude
  stub npm 'case "$1" in install) mkdir -p node_modules/playwright ;; esac'
  stub rtk
  stub toon
  stub basecamp
  stub terminal-notifier 'case "$1" in -diagnose) echo "    authorization authorized" ;; esac'
  touch "$PLUGINS/basecamp@37signals"
}

# A sandbox where every check passes: tokens present, auto-update "enabled".
make_everything_installed() {
  stub_toolchain
  mkdir -p "$CLAUDE_DIR" "$HOME/Library/LaunchAgents"
  printf 'TIMESHEET_API_TOKEN="t-123"\n' > "$ENV_FILE"
  touch "$HOME/Library/LaunchAgents/nl.labelvier.cli-update.plist"
  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]
  # After the install: with fa present, install would ask about updating it.
  stub fa
}

template_version() {
  sed -n 's/.*labelvier-ai-version: *\([0-9][0-9.]*\).*/\1/p' "$1" | head -n 1
}

hook_entries_in_settings() {
  jq --arg cmd "$HOOK" '[.hooks.PreToolUse[]?.hooks[]? | select(.command == $cmd)] | length' "$SETTINGS"
}

# --- dispatch and help -----------------------------------------------------

@test "bare ai prints its available functions" {
  run_ai
  # No status check: _echo_documentation ends on a failed read (EOF), so every
  # bare command collection exits 1 — docs, not an error.
  assert_output_contains "Available functions:"
  assert_output_contains "claude"
  assert_output_contains "basecamp"
  assert_output_contains "check"
  assert_output_contains "update"
}

@test "ai <sub> --help prints the description without running the check" {
  run_ai check --help
  [ "$status" -eq 0 ]
  assert_output_contains "check - Checks basecamp, npm"
  refute_output_contains "✗"
}

@test "ai nope is an unknown command" {
  run_ai nope
  [ "$status" -eq 1 ]
  assert_output_contains "Unknown command: nope"
}

@test "ai claude without a subcommand prints the nested help" {
  run_ai claude
  [ "$status" -eq 0 ]
  assert_output_contains "labelvier ai claude"
  assert_output_contains "install - Installs config files"
  assert_output_contains "uninstall - Removes the toon hook"
  assert_output_contains "labelvier ai check"
}

@test "ai claude --help prints the one-line description like any subcommand" {
  run_ai claude --help
  [ "$status" -eq 0 ]
  assert_output_contains "claude - Installs the global GLOBAL.md/WORDPRESS.md/ANGULAR.md config"
  assert_output_contains "Subcommands: install, uninstall."
  refute_output_contains "Available functions:"
}

@test "ai claude install --help prints the description and does not install" {
  stub_toolchain
  run_ai claude install --help < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "install - Installs config files, the timesheet skill"
  assert_output_contains "--force, --skip-hook"
  [ ! -e "$CLAUDE_DIR" ]
  [ ! -s "$STUB_LOG" ]
}

@test "ai claude uninstall --help prints the description and does not ask" {
  run_ai claude uninstall --help < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "uninstall - Removes the toon hook and config files"
  refute_output_contains "Warning"
}

@test "ai claude nope reports an unknown command and fails" {
  run_ai claude nope
  [ "$status" -eq 1 ]
  assert_output_contains "✗ Unknown command: nope"
  assert_output_contains "Available functions:"
}

@test "ai basecamp prints its nested help and rejects unknown subcommands" {
  run_ai basecamp
  [ "$status" -eq 0 ]
  assert_output_contains "labelvier ai basecamp"
  assert_output_contains "install - Installs the Basecamp CLI"

  run_ai basecamp install --help
  [ "$status" -eq 0 ]
  assert_output_contains "install - Installs the Basecamp CLI"
  [ ! -s "$STUB_LOG" ]

  run_ai basecamp nope
  [ "$status" -eq 1 ]
  assert_output_contains "✗ Unknown command: nope"
}

# --- ai check --------------------------------------------------------------

@test "ai check on a bare machine reports every tool, file and key as missing" {
  run_ai check
  [ "$status" -eq 0 ]
  assert_output_contains "✗ basecamp (missing"
  assert_output_contains "✗ basecamp plugin for Claude Code"
  assert_output_contains "✗ npm (missing, run: labelvier setup tools)"
  assert_output_contains "✗ fa (Font Awesome CLI) (missing, run: labelvier ai claude install)"
  assert_output_contains "✗ toon (missing"
  assert_output_contains "✗ rtk (missing"
  assert_output_contains "✗ caveman plugin (missing"
  assert_output_contains "✗ $CLAUDE_DIR/labelvier/GLOBAL.md (missing"
  assert_output_contains "✗ $CLAUDE_DIR/labelvier/WORDPRESS.md (missing"
  assert_output_contains "✗ $CLAUDE_DIR/labelvier/ANGULAR.md (missing"
  assert_output_contains "✗ $CLAUDE_DIR/CLAUDE.md (missing"
  assert_output_contains "(timesheet skill) (missing or incomplete"
  assert_output_contains "✗ TIMESHEET_API_TOKEN (not set in $ENV_FILE"
  assert_output_contains "(dashboard skill, optional, not installed)"
  assert_output_contains "(toon hook) (missing"
  # The dashboard key is only checked once that optional skill is installed.
  refute_output_contains "LV_DASHBOARD_API_KEY"
  if [ "$(uname)" = "Darwin" ]; then
    assert_output_contains "✗ terminal-notifier (missing, run: labelvier core notifications)"
  fi
}

@test "ai check on a fully installed machine is all green with versions" {
  make_everything_installed
  run_ai check
  [ "$status" -eq 0 ]
  refute_output_contains "✗"
  assert_output_contains "✓ basecamp plugin for Claude Code"
  assert_output_contains "✓ npm"
  assert_output_contains "✓ toon"
  assert_output_contains "✓ rtk wired into Claude Code"
  assert_output_contains "✓ caveman plugin"
  assert_output_contains "✓ $CLAUDE_DIR/labelvier/GLOBAL.md (version $(template_version "$TPL_DIR/labelvier/GLOBAL.md.tpl"))"
  assert_output_contains "✓ labelvier snippet in $CLAUDE_DIR/CLAUDE.md (version 1)"
  assert_output_contains "(timesheet skill, version $(template_version "$TPL_DIR/skills/timesheet/SKILL.md.tpl"))"
  assert_output_contains "✓ TIMESHEET_API_TOKEN set"
  assert_output_contains "$HOOK (toon hook, registered)"
  if [ "$(uname)" = "Darwin" ]; then
    assert_output_contains "✓ terminal-notifier (notifications allowed)"
  fi
}

@test "ai check reports the dashboard key only when the dashboard skill is installed" {
  mkdir -p "$(dirname "$DASH_SKILL")"
  cp "$TPL_DIR/skills/label-vier-dashboard-api/SKILL.md.tpl" "$DASH_SKILL"

  run_ai check
  assert_output_contains "✓ $(dirname "$DASH_SKILL") (dashboard skill, version $(template_version "$DASH_SKILL"))"
  assert_output_contains "✗ LV_DASHBOARD_API_KEY (not set in $ENV_FILE"

  mkdir -p "$CLAUDE_DIR"
  printf 'LV_DASHBOARD_API_KEY="k"\nTIMESHEET_API_TOKEN="t"\n' > "$ENV_FILE"
  run_ai check
  assert_output_contains "✓ LV_DASHBOARD_API_KEY set"
  assert_output_contains "✓ TIMESHEET_API_TOKEN set"
}

@test "ai check ignores an empty token line" {
  mkdir -p "$CLAUDE_DIR"
  printf 'TIMESHEET_API_TOKEN=\n' > "$ENV_FILE"
  run_ai check
  assert_output_contains "✗ TIMESHEET_API_TOKEN (not set"
}

@test "ai check flags outdated config, skill and snippet versions" {
  mkdir -p "$CLAUDE_DIR/labelvier" "$(dirname "$DASH_SKILL")" "$SKILL_DIR/browser/node_modules/playwright" "$SKILL_DIR/scripts"
  echo "<!-- labelvier-ai-version: 0 -->" > "$CLAUDE_DIR/labelvier/GLOBAL.md"
  echo "no stamp at all" > "$CLAUDE_DIR/labelvier/WORDPRESS.md"
  echo "<!-- labelvier-ai-version: 0 -->" > "$DASH_SKILL"
  echo "<!-- labelvier-ai-version: 0 -->" > "$SKILL_DIR/SKILL.md"
  touch "$SKILL_DIR/scripts/timesheet.sh" "$SKILL_DIR/browser/browser-get.mjs" "$SKILL_DIR/browser/package.json" "$SKILL_DIR/browser/package-lock.json"
  printf '<!-- labelvier-ai:start version=0 -->\n@labelvier/GLOBAL.md\n<!-- labelvier-ai:end -->\n' > "$CLAUDE_DIR/CLAUDE.md"

  run_ai check
  local global_v; global_v=$(template_version "$TPL_DIR/labelvier/GLOBAL.md.tpl")
  assert_output_contains "✗ $CLAUDE_DIR/labelvier/GLOBAL.md (outdated: installed 0, available $global_v; run: labelvier ai claude install)"
  assert_output_contains "✗ $CLAUDE_DIR/labelvier/WORDPRESS.md (outdated: installed unversioned, available"
  assert_output_contains "(dashboard skill) (outdated: installed 0, available $(template_version "$TPL_DIR/skills/label-vier-dashboard-api/SKILL.md.tpl")"
  assert_output_contains "(timesheet skill) (outdated: installed 0, available $(template_version "$TPL_DIR/skills/timesheet/SKILL.md.tpl")"
  assert_output_contains "✗ labelvier snippet in $CLAUDE_DIR/CLAUDE.md (outdated: installed 0, available 1"
}

@test "ai check flags a CLAUDE.md without the managed snippet" {
  mkdir -p "$CLAUDE_DIR"
  echo "# my own notes" > "$CLAUDE_DIR/CLAUDE.md"
  run_ai check
  assert_output_contains "✓ $CLAUDE_DIR/CLAUDE.md"
  assert_output_contains "✗ labelvier snippet in $CLAUDE_DIR/CLAUDE.md (missing or unversioned"
}

@test "ai check flags a hook script that is not registered in settings.json" {
  mkdir -p "$CLAUDE_DIR/hooks"
  cp "$CLI_ROOT/templates/basecamp-toon.sh.tpl" "$HOOK"
  echo '{}' > "$SETTINGS"
  run_ai check
  assert_output_contains "✗ $HOOK exists but is not registered in $SETTINGS"
}

@test "ai check asks rtk whether it is wired in and shows what it would change" {
  stub rtk 'case "$*" in *--dry-run*) echo "[dry-run] would write RTK.md"; echo "[dry-run] would patch settings.json" ;; esac'
  run_ai check
  assert_output_contains "✓ rtk"
  assert_output_contains "✗ rtk not fully wired into Claude Code"
  assert_output_contains "    [dry-run] would write RTK.md"
  assert_output_contains "    [dry-run] would patch settings.json"
  assert_stub_called '^rtk init -g --dry-run$'
}

@test "ai check reports an unauthorized terminal-notifier" {
  [ "$(uname)" = "Darwin" ] || skip "terminal-notifier is only checked on macOS"
  stub terminal-notifier 'echo "    authorization denied"'
  run_ai check
  assert_output_contains "✗ terminal-notifier (notifications not allowed: denied; run: labelvier core notifications)"
}

# --- ai claude install -----------------------------------------------------

@test "ai claude install installs config files, snippet, skill, hook, rtk and caveman" {
  stub_toolchain
  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]

  local name
  for name in GLOBAL WORDPRESS ANGULAR; do
    cmp -s "$TPL_DIR/labelvier/$name.md.tpl" "$CLAUDE_DIR/labelvier/$name.md"
    [ "$(file_mode "$CLAUDE_DIR/labelvier/$name.md")" = "600" ]
    assert_output_contains "Installed $CLAUDE_DIR/labelvier/$name.md"
  done

  assert_output_contains "Created $CLAUDE_DIR/CLAUDE.md (empty)"
  assert_output_contains "Added the labelvier snippet (version 1)"
  grep -qxF '<!-- labelvier-ai:start version=1 -->' "$CLAUDE_DIR/CLAUDE.md"
  grep -qxF '@labelvier/GLOBAL.md' "$CLAUDE_DIR/CLAUDE.md"
  grep -qxF '@labelvier/WORDPRESS.md' "$CLAUDE_DIR/CLAUDE.md"
  grep -qxF '@labelvier/ANGULAR.md' "$CLAUDE_DIR/CLAUDE.md"
  grep -qxF '<!-- labelvier-ai:end -->' "$CLAUDE_DIR/CLAUDE.md"

  cmp -s "$TPL_DIR/skills/timesheet/SKILL.md.tpl" "$SKILL_DIR/SKILL.md"
  [ -x "$SKILL_DIR/scripts/timesheet.sh" ]
  [ -f "$SKILL_DIR/browser/browser-get.mjs" ]
  [ -f "$SKILL_DIR/browser/package.json" ]
  [ -f "$SKILL_DIR/browser/package-lock.json" ]
  assert_stub_called '^npm install --no-audit --no-fund$'
  assert_output_contains "Installed timesheet skill dependencies"

  assert_stub_called '^rtk init -g --auto-patch$'
  assert_output_contains "✓ rtk wired into Claude Code"
  assert_output_contains "Skipped fa."

  assert_stub_called '^claude plugin marketplace add JuliusBrussee/caveman$'
  assert_stub_called '^claude plugin install caveman@caveman -y -s user$'
  assert_output_contains "Installed caveman plugin"
  [ -e "$PLUGINS/caveman@caveman" ]

  [ -x "$HOOK" ]
  cmp -s "$CLI_ROOT/templates/basecamp-toon.sh.tpl" "$HOOK"
  [ -f "$SETTINGS.bak" ]
  [ "$(hook_entries_in_settings)" = "1" ]
  [ "$(jq -r '.hooks.PreToolUse[0].matcher' "$SETTINGS")" = "Bash" ]
  [ "$(jq -r '.hooks.PreToolUse[0].hooks[0]["if"]' "$SETTINGS")" = "Bash(basecamp *)" ]
  assert_output_contains "Registered the hook in $SETTINGS"

  refute_stub_called '^brew'
  refute_stub_called '^curl'
}

@test "ai claude install is idempotent" {
  stub_toolchain
  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]
  : > "$STUB_LOG"

  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Up to date, skipped: $CLAUDE_DIR/labelvier/GLOBAL.md (version"
  assert_output_contains "✓ CLAUDE.md snippet is up to date (version 1)"
  assert_output_contains "Up to date, skipped: $SKILL_DIR/SKILL.md"
  assert_output_contains "✓ timesheet skill dependencies already installed"
  assert_output_contains "✓ caveman plugin already installed"
  refute_stub_called '^npm install'
  refute_stub_called '^claude plugin install'
  [ "$(grep -c 'labelvier-ai:start' "$CLAUDE_DIR/CLAUDE.md")" -eq 1 ]
  [ "$(grep -c '^@labelvier/GLOBAL.md$' "$CLAUDE_DIR/CLAUDE.md")" -eq 1 ]
  [ "$(hook_entries_in_settings)" = "1" ]
}

@test "ai claude install --force overwrites up-to-date files" {
  stub_toolchain
  run_ai claude install < /dev/null
  echo "edited" >> "$CLAUDE_DIR/labelvier/GLOBAL.md"
  echo "edited" >> "$SKILL_DIR/SKILL.md"

  run_ai claude install --force < /dev/null
  [ "$status" -eq 0 ]
  cmp -s "$TPL_DIR/labelvier/GLOBAL.md.tpl" "$CLAUDE_DIR/labelvier/GLOBAL.md"
  cmp -s "$TPL_DIR/skills/timesheet/SKILL.md.tpl" "$SKILL_DIR/SKILL.md"
  refute_output_contains "Up to date, skipped"
}

@test "ai claude install refreshes an outdated config file and keeps a .bak" {
  stub_toolchain
  mkdir -p "$CLAUDE_DIR/labelvier"
  echo "<!-- labelvier-ai-version: 0 --> old" > "$CLAUDE_DIR/labelvier/GLOBAL.md"

  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Updating $CLAUDE_DIR/labelvier/GLOBAL.md: 0 → $(template_version "$TPL_DIR/labelvier/GLOBAL.md.tpl") (old copy: $CLAUDE_DIR/labelvier/GLOBAL.md.bak)"
  cmp -s "$TPL_DIR/labelvier/GLOBAL.md.tpl" "$CLAUDE_DIR/labelvier/GLOBAL.md"
  grep -q "old" "$CLAUDE_DIR/labelvier/GLOBAL.md.bak"
}

@test "ai claude install refreshes an outdated timesheet skill as a whole" {
  stub_toolchain
  mkdir -p "$SKILL_DIR/scripts" "$SKILL_DIR/browser"
  echo "<!-- labelvier-ai-version: 0 -->" > "$SKILL_DIR/SKILL.md"
  echo "old script" > "$SKILL_DIR/scripts/timesheet.sh"

  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "timesheet skill is outdated (installed: 0, available: $(template_version "$TPL_DIR/skills/timesheet/SKILL.md.tpl")), updating."
  cmp -s "$TPL_DIR/skills/timesheet/SKILL.md.tpl" "$SKILL_DIR/SKILL.md"
  cmp -s "$TPL_DIR/skills/timesheet/scripts/timesheet.sh.tpl" "$SKILL_DIR/scripts/timesheet.sh"
}

@test "ai claude install replaces an outdated snippet and leaves personal CLAUDE.md content alone" {
  stub_toolchain
  mkdir -p "$CLAUDE_DIR"
  cat > "$CLAUDE_DIR/CLAUDE.md" <<'EOF'
# my notes
@RTK.md
@labelvier/GLOBAL.md
<!-- labelvier-ai:start version=0 -->
@labelvier/WORDPRESS.md
<!-- labelvier-ai:end -->
keep this line too
EOF

  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Updated the labelvier snippet in $CLAUDE_DIR/CLAUDE.md (version 0 → 1)"
  grep -qxF '# my notes' "$CLAUDE_DIR/CLAUDE.md"
  grep -qxF '@RTK.md' "$CLAUDE_DIR/CLAUDE.md"
  grep -qxF 'keep this line too' "$CLAUDE_DIR/CLAUDE.md"
  [ "$(grep -c 'labelvier-ai:start' "$CLAUDE_DIR/CLAUDE.md")" -eq 1 ]
  [ "$(grep -c 'version=0' "$CLAUDE_DIR/CLAUDE.md")" -eq 0 ]
  [ "$(grep -c '^@labelvier/GLOBAL.md$' "$CLAUDE_DIR/CLAUDE.md")" -eq 1 ]
  [ "$(grep -c '^@labelvier/WORDPRESS.md$' "$CLAUDE_DIR/CLAUDE.md")" -eq 1 ]
  [ -f "$CLAUDE_DIR/CLAUDE.md.bak" ]
}

@test "ai claude install --skip-hook leaves the toon hook out" {
  stub_toolchain
  run_ai claude install --skip-hook < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Skipped the toon hook (--skip-hook)."
  [ ! -e "$HOOK" ]
  [ ! -e "$SETTINGS" ]
}

@test "ai claude install without npm skips the timesheet skill and goes on" {
  stub_toolchain
  unstub npm
  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "npm is not installed."
  [ ! -e "$SKILL_DIR/SKILL.md" ]
  assert_output_contains "Installed caveman plugin"
  [ -x "$HOOK" ]
}

@test "ai claude install refuses to touch a broken settings.json" {
  stub_toolchain
  mkdir -p "$CLAUDE_DIR"
  echo '{ not json' > "$SETTINGS"
  run_ai claude install < /dev/null
  [ "$status" -eq 1 ]
  assert_output_contains "$SETTINGS is not valid JSON."
  [ "$(cat "$SETTINGS")" = "{ not json" ]
}

@test "ai claude install keeps other hooks in settings.json and appends to the Bash group" {
  stub_toolchain
  mkdir -p "$CLAUDE_DIR"
  cat > "$SETTINGS" <<'EOF'
{"theme":"dark","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/other/hook.sh"}]}]}}
EOF
  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]
  [ "$(jq -r '.theme' "$SETTINGS")" = "dark" ]
  [ "$(jq '.hooks.PreToolUse | length' "$SETTINGS")" = "1" ]
  [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$SETTINGS")" = "/other/hook.sh" ]
  [ "$(jq -r '.hooks.PreToolUse[0].hooks[1].command' "$SETTINGS")" = "$HOOK" ]
}

# --- the optional dashboard skill and the tokens ---------------------------

@test "ai claude install skips the dashboard question when there is no terminal" {
  stub_toolchain
  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Install the optional Label Vier Dashboard skill (websites, plugins, logs, contacts)? [Y/n] (no terminal to ask on, skipped)"
  assert_output_contains "Skipped the dashboard skill. Run this install again to add it later."
  [ ! -e "$DASH_SKILL" ]
  refute_output_contains "LV_DASHBOARD_API_KEY"
  # The timesheet token is not asked for either, just hinted.
  assert_output_contains "The timesheet skill needs a TIMESHEET_API_TOKEN."
  assert_output_contains "Then add it to $ENV_FILE as TIMESHEET_API_TOKEN=<token>."
  [ ! -e "$ENV_FILE" ]
}

@test "ai claude install skips the dashboard skill on 'n'" {
  stub_toolchain
  run_ai_with '_confirm() { echo "$1 -> n"; return 1; }' claude install < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Install the optional Label Vier Dashboard skill (websites, plugins, logs, contacts)? -> n"
  assert_output_contains "Skipped the dashboard skill."
  [ ! -e "$DASH_SKILL" ]
  assert_output_contains "Skipped. Add TIMESHEET_API_TOKEN=<token> to $ENV_FILE later."
  [ ! -e "$ENV_FILE" ]
}

@test "ai claude install installs the dashboard skill on 'y' and asks for its key" {
  stub_toolchain
  run_ai_with '_confirm() { echo "$1 -> y"; return 0; }' claude install < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Install the optional Label Vier Dashboard skill (websites, plugins, logs, contacts)? -> y"
  assert_output_contains "Installed $DASH_SKILL"
  cmp -s "$TPL_DIR/skills/label-vier-dashboard-api/SKILL.md.tpl" "$DASH_SKILL"
  assert_output_contains "The dashboard skill needs a LV_DASHBOARD_API_KEY."
  assert_output_contains "Set LV_DASHBOARD_API_KEY now? -> y"
  # No terminal to paste on: nothing saved, no empty entry either.
  assert_output_contains "Skipped. Add LV_DASHBOARD_API_KEY=<token> to $ENV_FILE later."
  [ ! -e "$ENV_FILE" ]
}

@test "ai claude install with a dashboard skill already there only refreshes it when outdated" {
  stub_toolchain
  mkdir -p "$(dirname "$DASH_SKILL")"
  echo "<!-- labelvier-ai-version: 0 -->" > "$DASH_SKILL"

  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]
  refute_output_contains "Install the optional Label Vier Dashboard skill"
  assert_output_contains "dashboard skill is outdated (installed: 0, available: $(template_version "$TPL_DIR/skills/label-vier-dashboard-api/SKILL.md.tpl")), updating."
  cmp -s "$TPL_DIR/skills/label-vier-dashboard-api/SKILL.md.tpl" "$DASH_SKILL"
  assert_output_contains "The dashboard skill needs a LV_DASHBOARD_API_KEY."

  run_ai claude install < /dev/null
  assert_output_contains "Up to date, skipped: $DASH_SKILL (version"
}

@test "ai claude install saves pasted tokens in ~/.claude/.env, quoted and 0600" {
  type -P expect >/dev/null 2>&1 || skip "expect is not installed (needed for a pty)"
  stub_toolchain
  stub fa
  mkdir -p "$CLAUDE_DIR"
  # An empty entry from earlier must be replaced, not duplicated.
  printf 'OTHER=1\nLV_DASHBOARD_API_KEY=\n' > "$ENV_FILE"

  run expect -c "
    set timeout 30
    spawn \"$CLI\" ai claude install
    expect \"Set TIMESHEET_API_TOKEN now?\"
    send \"y\r\"
    expect \"Paste your token here\"
    after 300
    send \"ts-token|abc\r\"
    expect \"Install the optional Label Vier Dashboard skill\"
    send \"y\r\"
    expect \"Set LV_DASHBOARD_API_KEY now?\"
    send \"\r\"
    expect \"Paste your token here\"
    after 300
    send \"dash-key-123\r\"
    expect eof
  "
  [ "$status" -eq 0 ]
  assert_output_contains "Saved the token in $ENV_FILE"
  grep -qxF 'TIMESHEET_API_TOKEN="ts-token|abc"' "$ENV_FILE"
  grep -qxF 'LV_DASHBOARD_API_KEY="dash-key-123"' "$ENV_FILE"
  grep -qxF 'OTHER=1' "$ENV_FILE"
  [ "$(grep -c '^LV_DASHBOARD_API_KEY=' "$ENV_FILE")" -eq 1 ]
  [ "$(file_mode "$ENV_FILE")" = "600" ]
  [ -f "$DASH_SKILL" ]
  refute_output_contains "dash-key-123"
}

@test "ai claude install skips a token that is pasted empty" {
  type -P expect >/dev/null 2>&1 || skip "expect is not installed (needed for a pty)"
  stub_toolchain
  stub fa
  run expect -c "
    set timeout 30
    spawn \"$CLI\" ai claude install
    expect \"Set TIMESHEET_API_TOKEN now?\"
    send \"y\r\"
    expect \"Paste your token here\"
    send \"\r\"
    expect \"Install the optional Label Vier Dashboard skill\"
    send \"n\r\"
    expect eof
  "
  [ "$status" -eq 0 ]
  assert_output_contains "Skipped. Add TIMESHEET_API_TOKEN=<token> to $ENV_FILE later."
  assert_output_contains "Skipped the dashboard skill."
  [ ! -e "$ENV_FILE" ]
}

@test "ai claude install quotes an unquoted token already in .env" {
  stub_toolchain
  mkdir -p "$CLAUDE_DIR"
  printf 'TIMESHEET_API_TOKEN=12|abc\n' > "$ENV_FILE"
  chmod 644 "$ENV_FILE"

  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "✓ Quoted TIMESHEET_API_TOKEN in $ENV_FILE"
  assert_output_contains "✓ TIMESHEET_API_TOKEN is set in $ENV_FILE"
  [ "$(cat "$ENV_FILE")" = 'TIMESHEET_API_TOKEN="12|abc"' ]
  [ "$(file_mode "$ENV_FILE")" = "600" ]
  refute_output_contains "needs a TIMESHEET_API_TOKEN"
}

@test "ai claude install leaves a quoted token alone" {
  stub_toolchain
  mkdir -p "$CLAUDE_DIR"
  printf "TIMESHEET_API_TOKEN='keep'\n" > "$ENV_FILE"
  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]
  refute_output_contains "Quoted TIMESHEET_API_TOKEN"
  assert_output_contains "✓ TIMESHEET_API_TOKEN is set in $ENV_FILE"
  [ "$(cat "$ENV_FILE")" = "TIMESHEET_API_TOKEN='keep'" ]
}

# --- external tools during install -----------------------------------------

@test "the claude CLI is always run with stdin from /dev/null" {
  stub_toolchain
  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]
  local calls devnull
  calls=$(grep -c '^claude plugin' "$STUB_LOG")
  devnull=$(grep -c '^claude-stdin /dev/null$' "$STUB_LOG")
  [ "$calls" -ge 3 ]
  [ "$calls" -eq "$devnull" ]
}

@test "ai claude install reports a caveman install that did not take" {
  stub_toolchain
  stub claude 'case "$1 $2" in "plugin list") echo "[]" ;; esac'
  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]
  assert_stub_called '^claude plugin install caveman@caveman'
  assert_output_contains "Failed to install the caveman plugin."
}

@test "ai claude install offers brew for a missing claude CLI and aborts on 'n'" {
  stub_toolchain
  unstub claude
  stub fa
  run_ai claude install <<< "n"
  [ "$status" -eq 1 ]
  assert_output_contains "The 'claude' command is not installed."
  # (read -p only shows its prompt on a terminal, so the question itself is not in the output)
  assert_output_contains "Aborted."
  refute_stub_called '^brew install'
  # The earlier steps already ran; the hook step never came.
  [ -f "$CLAUDE_DIR/labelvier/GLOBAL.md" ]
  [ ! -e "$HOOK" ]
}

@test "ai claude install runs brew for a missing claude CLI on 'y'" {
  stub_toolchain
  unstub claude
  stub fa
  run_ai claude install <<< $'n\ny'
  [ "$status" -eq 1 ]
  assert_stub_called '^brew install --cask claude-code$'
  assert_output_contains "'claude' is still not on your PATH after installing."
}

@test "ai claude install offers rtk via brew and aborts on 'n'" {
  stub_toolchain
  unstub rtk
  run_ai claude install <<< "n"
  [ "$status" -eq 1 ]
  assert_output_contains "rtk is not installed."
  assert_output_contains "Aborted."
  refute_stub_called '^brew install'
}

@test "ai claude install offers the Font Awesome CLI and runs its installer on 'y'" {
  stub_toolchain
  run_ai claude install <<< "y"
  [ "$status" -eq 1 ]
  assert_output_contains "fa is not installed."
  assert_stub_called '^curl .*https://fontawesome.com/fa-cli/install.sh$'
  assert_output_contains "fa is still not on your PATH after installing."
}

@test "ai claude install offers to update an installed fa and reruns the installer on 'y'" {
  stub_toolchain
  stub fa
  stub curl
  run_ai claude install <<< "y"
  assert_output_contains "✓ fa (Font Awesome CLI)"
  assert_stub_called '^curl .*https://fontawesome.com/fa-cli/install.sh$'
}

@test "ai claude install skips the fa update on 'n' and keeps going" {
  stub_toolchain
  stub fa
  run_ai claude install <<< "n"
  assert_output_contains "Skipped fa update."
  refute_stub_called '^curl '
}

@test "ai claude install reports a failed fa update without aborting" {
  stub_toolchain
  stub fa
  stub curl 'exit 22'
  run_ai claude install <<< "y"
  assert_output_contains "fa update failed."
  assert_output_contains "rtk wired into Claude Code"
}

@test "ai claude install reports a failed rtk init without aborting" {
  stub_toolchain
  stub rtk 'exit 1'
  run_ai claude install < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "rtk init -g failed."
  assert_output_contains "Installed caveman plugin"
}

# --- ai claude uninstall ---------------------------------------------------

@test "ai claude uninstall warns and aborts without a yes" {
  make_everything_installed
  : > "$STUB_LOG"
  run_ai claude uninstall <<< "n"
  [ "$status" -eq 1 ]
  assert_output_contains "Warning: this removes everything"
  assert_output_contains "  - $CLAUDE_DIR/labelvier/GLOBAL.md"
  assert_output_contains "Aborted."
  [ -f "$CLAUDE_DIR/labelvier/GLOBAL.md" ]
  [ -x "$HOOK" ]
  [ ! -s "$STUB_LOG" ]
}

@test "ai claude uninstall removes everything install set up but keeps CLAUDE.md and the tokens" {
  make_everything_installed
  echo "# personal" >> "$CLAUDE_DIR/CLAUDE.md"
  echo "@RTK.md" >> "$CLAUDE_DIR/CLAUDE.md"
  : > "$STUB_LOG"

  run_ai claude uninstall <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "Unregistered the hook from $SETTINGS"
  assert_output_contains "Removed $HOOK"
  assert_output_contains "Removed caveman plugin"
  assert_output_contains "Removed $SKILL_DIR"
  assert_output_contains "Removed the labelvier snippet from $CLAUDE_DIR/CLAUDE.md"
  assert_output_contains "Removed @RTK.md from $CLAUDE_DIR/CLAUDE.md"
  assert_output_contains "Removed $CLAUDE_DIR/labelvier/GLOBAL.md"
  assert_output_contains "Done."

  assert_stub_called '^claude plugin uninstall caveman@caveman -y$'
  assert_stub_called '^claude plugin marketplace remove caveman$'
  assert_stub_called '^rtk init -g --uninstall --auto-patch$'

  [ ! -e "$HOOK" ]
  [ "$(hook_entries_in_settings)" = "0" ]
  [ "$(jq '.hooks.PreToolUse // empty' "$SETTINGS")" = "" ]
  [ ! -e "$SKILL_DIR" ]
  [ ! -e "$CLAUDE_DIR/labelvier" ]
  [ ! -e "$PLUGINS/caveman@caveman" ]
  [ -f "$CLAUDE_DIR/CLAUDE.md" ]
  grep -qxF '# personal' "$CLAUDE_DIR/CLAUDE.md"
  ! grep -q 'labelvier' "$CLAUDE_DIR/CLAUDE.md"
  ! grep -q '@RTK.md' "$CLAUDE_DIR/CLAUDE.md"
  grep -qxF 'TIMESHEET_API_TOKEN="t-123"' "$ENV_FILE"
}

@test "ai claude uninstall keeps a labelvier dir that holds other files" {
  make_everything_installed
  echo "mine" > "$CLAUDE_DIR/labelvier/NOTES.md"
  run_ai claude uninstall <<< "y"
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_DIR/labelvier/NOTES.md" ]
  [ ! -e "$CLAUDE_DIR/labelvier/GLOBAL.md" ]
}

@test "ai claude uninstall on a bare machine has nothing to remove" {
  run_ai claude uninstall <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "Nothing to remove: $SETTINGS does not exist."
  assert_output_contains "No hook script found at $HOOK"
  assert_output_contains "Skipping caveman plugin removal: 'claude' is not installed."
  [ ! -s "$STUB_LOG" ]
}

# --- ai basecamp -----------------------------------------------------------

@test "ai basecamp install skips when basecamp is already there" {
  stub basecamp
  run_ai basecamp install < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "✓ basecamp is already installed."
  refute_stub_called '^curl'
}

@test "ai basecamp install runs the installer and complains when basecamp is still missing" {
  run_ai basecamp install < /dev/null
  [ "$status" -eq 1 ]
  assert_output_contains "Installing the Basecamp CLI..."
  assert_stub_called '^curl -fsSL https://basecamp.com/install-cli$'
  assert_output_contains "basecamp is still not on your PATH after installing."
}

@test "ai basecamp uninstall aborts without a yes" {
  stub basecamp
  run_ai basecamp uninstall <<< "n"
  [ "$status" -eq 1 ]
  assert_output_contains "the basecamp binary at $STUB_DIR/basecamp"
  assert_output_contains "Aborted."
  [ -x "$STUB_DIR/basecamp" ]
}

@test "ai basecamp uninstall logs out, removes the plugin, the binary and its dirs" {
  stub_claude
  stub basecamp
  touch "$PLUGINS/basecamp@37signals"
  mkdir -p "$HOME/.config/basecamp" "$HOME/.cache/basecamp"
  unset XDG_CONFIG_HOME XDG_CACHE_HOME

  run_ai basecamp uninstall <<< "y"
  [ "$status" -eq 0 ]
  assert_stub_called '^basecamp logout$'
  assert_output_contains "Logged out of Basecamp"
  assert_stub_called '^claude plugin uninstall basecamp@37signals -y$'
  assert_output_contains "Removed the Basecamp plugin for Claude Code"
  [ ! -e "$STUB_DIR/basecamp" ]
  [ ! -e "$HOME/.config/basecamp" ]
  [ ! -e "$HOME/.cache/basecamp" ]
  assert_output_contains "Done."
}

# --- ai update -------------------------------------------------------------

@test "ai update with nothing to fix says so" {
  make_everything_installed
  run_ai update < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Everything is up to date."
  refute_output_contains "Suggested fixes"
}

@test "ai update lists each suggested fix once and skips them without a terminal" {
  stub npm
  stub terminal-notifier 'echo "    authorization authorized"'
  run_ai update < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Suggested fixes: (nothing changes without your yes)"
  assert_output_contains "Run 'labelvier ai basecamp install'? [Y/n] (no terminal to ask on, skipped)"
  assert_output_contains "Run 'labelvier ai claude install'? [Y/n] (no terminal to ask on, skipped)"
  # Many checks point at the same command: it is asked once.
  [ "$(plain_output | grep -c "Run 'labelvier ai claude install'?")" -eq 1 ]
  assert_output_contains "Checking again..."
  assert_output_contains "✗ caveman plugin"
  [ ! -e "$CLAUDE_DIR/labelvier" ]
  refute_stub_called '^curl'
  refute_stub_called '^claude'
}

@test "ai update runs an accepted fix through the CLI and checks again" {
  stub_toolchain
  stub fa
  mkdir -p "$CLAUDE_DIR" "$HOME/Library/LaunchAgents"
  printf 'TIMESHEET_API_TOKEN="t"\n' > "$ENV_FILE"
  touch "$HOME/Library/LaunchAgents/nl.labelvier.cli-update.plist"

  run_ai_with '_confirm() { echo "$1 -> yes"; return 0; }' update < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Run 'labelvier ai claude install'? -> yes"
  # The fix is the real `labelvier ai claude install`, run as a child process.
  assert_output_contains "Installed $CLAUDE_DIR/labelvier/GLOBAL.md"
  assert_output_contains "Installed caveman plugin"
  assert_output_contains "Registered the hook in $SETTINGS"
  [ -f "$CLAUDE_DIR/labelvier/GLOBAL.md" ]
  [ -x "$HOOK" ]
  assert_stub_called '^claude plugin install caveman@caveman -y -s user$'
  assert_output_contains "Checking again..."
  assert_output_contains "All checks passed."
}

@test "ai update keeps its action list off stdin so the fix can still ask questions" {
  stub_toolchain
  unstub rtk
  mkdir -p "$HOME/Library/LaunchAgents"
  touch "$HOME/Library/LaunchAgents/nl.labelvier.cli-update.plist"
  # stdin answers the fix's own 'brew install rtk?' prompt; the action list
  # travels over fd 3. Were it on stdin, 'labelvier ai claude install' would be
  # read as the answer and the brew prompt would abort.
  run_ai_with '_confirm() { return 0; }' update <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "rtk is not installed."
  assert_stub_called '^brew install rtk$'
  refute_output_contains "Aborted."
  # The stub never puts rtk on PATH, so the fix stops there; the loop went on.
  assert_output_contains "rtk is still not on your PATH after installing."
  assert_output_contains "Checking again..."
}

@test "ai update skips a declined fix" {
  stub_toolchain
  mkdir -p "$HOME/Library/LaunchAgents"
  touch "$HOME/Library/LaunchAgents/nl.labelvier.cli-update.plist"
  run_ai_with '_confirm() { echo "$1 -> no"; return 1; }' update < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Run 'labelvier ai claude install'? -> no"
  assert_output_contains "  Skipped."
  assert_output_contains "Checking again..."
  [ ! -e "$CLAUDE_DIR/labelvier" ]
  refute_stub_called '^claude plugin install'
}

@test "ai update offers the daily auto-update when it is not enabled" {
  make_everything_installed
  rm -f "$HOME/Library/LaunchAgents/nl.labelvier.cli-update.plist"
  [ "$(uname)" = "Darwin" ] || skip "the auto-update offer is macOS only"
  run_ai_with '_confirm() { echo "$1 -> no"; return 1; }' update < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Want the CLI to update itself automatically once a day? -> no"
  assert_output_contains "turn it on later with: labelvier core update --enable-auto"
  refute_stub_called '^launchctl'
}
