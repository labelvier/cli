#!/bin/bash

ai() (

  # Local filename to echo the documentation.
  local filename="ai.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")

  # Everything the toon hook touches lives inside the Claude Code config dir.
  local claude_dir="$HOME/.claude"
  local hooks_dir="$claude_dir/hooks"
  local hook_path="$hooks_dir/basecamp-toon.sh"
  local settings_file="$claude_dir/settings.json"
  local hook_template="$current_dir/../templates/basecamp-toon.sh.tpl"

  # Runs the command.
  function main() {
    # try to run the subcommand passed as the second argument and that function exists
    if [[ -n "$1" ]] && type -t "$1" | grep -q 'function'; then
      # attach any remaining arguments to the function
      "$1" "${@:2}"
    else
      # if no subcommand is passed, run the documentation function
      _echo_documentation "$filename"
    fi
  }

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # jq is used to merge into settings.json without clobbering existing settings.
  # NOTE: `type -P` searches PATH only — `command -v` would also match the shell
  # functions defined in this file.
  function _require_jq() {
    if type -P jq >/dev/null 2>&1; then
      return 0
    fi

    echo -e "${__red}jq is not installed.${__reset} It is needed to edit $settings_file safely."
    if ! type -P brew >/dev/null 2>&1; then
      echo -e "Homebrew was not found either. Install jq yourself: ${__blue}https://jqlang.github.io/jq/download/${__reset}"
      exit 1
    fi

    local answer
    read -p "Install it now with 'brew install jq'? [y/N] " answer
    case "$answer" in
      [yY]*) brew install jq ;;
      *) echo "Aborted."; exit 1 ;;
    esac

    if ! type -P jq >/dev/null 2>&1; then
      echo -e "${__red}jq is still not on your PATH after installing.${__reset} Open a new shell and try again."
      exit 1
    fi
  }

  # The hook pipes basecamp output through the `toon` binary from @toon-format/cli.
  function _require_toon() {
    if type -P toon >/dev/null 2>&1; then
      return 0
    fi

    echo -e "${__red}The 'toon' command is not installed.${__reset} The hook needs it to convert JSON to TOON."
    if ! type -P npm >/dev/null 2>&1; then
      echo -e "npm was not found either. Install Node.js first, then run: ${__blue}npm i -g @toon-format/cli${__reset}"
      exit 1
    fi

    local answer
    read -p "Install it now with 'npm i -g @toon-format/cli'? [y/N] " answer
    case "$answer" in
      [yY]*) npm i -g @toon-format/cli ;;
      *) echo "Aborted."; exit 1 ;;
    esac

    if ! type -P toon >/dev/null 2>&1; then
      echo -e "${__red}'toon' is still not on your PATH after installing.${__reset} Open a new shell and try again."
      exit 1
    fi
  }

  # Make sure settings.json exists and holds valid JSON, then back it up.
  function _prepare_settings_file() {
    mkdir -p "$claude_dir"
    if [ ! -f "$settings_file" ]; then
      echo "{}" > "$settings_file"
      echo -e "Created ${__blue}$settings_file${__reset}"
    fi

    if ! jq empty "$settings_file" >/dev/null 2>&1; then
      echo -e "${__red}$settings_file is not valid JSON.${__reset} Fix it first — a broken settings file disables all your Claude Code settings."
      exit 1
    fi

    cp "$settings_file" "$settings_file.bak"
  }

  # Write the jq result over settings.json, but only when it parsed correctly.
  function _write_settings() {
    local tmp_file="$1"
    if [ ! -s "$tmp_file" ] || ! jq empty "$tmp_file" >/dev/null 2>&1; then
      echo -e "${__red}Failed to update $settings_file.${__reset} The original is untouched (backup: $settings_file.bak)."
      rm -f "$tmp_file"
      exit 1
    fi
    mv "$tmp_file" "$settings_file"
  }

  # ---------------------------------------------------------------------------
  # @function toon
  # @description Manage the Claude Code hook that pipes basecamp CLI output through the TOON formatter, which cuts the tokens Claude spends on reading it. Subcommands: add-hook, remove-hook.
  # ---------------------------------------------------------------------------
  function toon() {
    if [[ -n "$1" ]] && type -t "$1" | grep -q 'function'; then
      "$1" "${@:2}"
    else
      _toon_documentation
    fi
  }

  # Hand-written help for the second level: _echo_documentation only reads the
  # flat "# @function" list of this file, which belongs to `wp-takeoff ai`.
  function _toon_documentation() {
    echo -e "${__bold}wp-takeoff ai toon${__reset} — TOON output formatting for Claude Code."
    echo
    echo -e "Installs a ${__bold}PreToolUse${__reset} hook in ${__blue}$claude_dir${__reset} that rewrites a bash command"
    echo -e "like ${__blue}basecamp projects list${__reset} into ${__blue}basecamp projects list | toon${__reset} before Claude runs it."
    echo -e "TOON is a compact representation of JSON, so Claude reads the same data for a lot fewer tokens."
    echo
    echo -e "${__red}${__bold}Note:${__reset} only the ${__bold}basecamp${__reset} CLI is supported at the moment. Any other command is left alone."
    echo -e "Commands using ${__bold}-m/--md${__reset}, ${__bold}--jq${__reset}, ${__bold}--help${__reset} or ${__bold}--version${__reset} are skipped too (their output is not JSON),"
    echo -e "and so is anything with your own pipe, redirect or ${__bold};${__reset} / ${__bold}&&${__reset} chaining."
    echo
    echo -e "${__bold}Requirements:${__reset} ${__blue}jq${__reset} (via brew) and ${__blue}toon${__reset} (via npm i -g @toon-format/cli) — both are offered for install."
    echo
    echo -e "${__bold}Available functions:${__reset}"
    echo -e "  ${__bold}add-hook${__reset} - Install the hook script and register it in $settings_file"
    echo -e "  ${__bold}remove-hook${__reset} - Unregister the hook and delete the hook script"
    echo
    echo -e "${__bold}Usage: ${__blue}wp-takeoff ai toon add-hook${__reset}"
  }

  # Installs the hook script and registers it for the Bash tool.
  function add-hook() {
    _require_jq
    _require_toon

    if [ ! -f "$hook_template" ]; then
      echo -e "${__red}Hook template not found:${__reset} $hook_template"
      exit 1
    fi

    mkdir -p "$hooks_dir"
    cp "$hook_template" "$hook_path"
    chmod +x "$hook_path"
    echo -e "${__green}Installed${__reset} $hook_path"

    _prepare_settings_file

    # The "if" filter keeps the hook from spawning on every single bash command.
    local entry
    entry=$(jq -n --arg cmd "$hook_path" '{
      type: "command",
      command: $cmd,
      "if": "Bash(basecamp *)",
      statusMessage: "TOON-ifying basecamp output"
    }')

    local tmp_file="$settings_file.tmp"
    # Drop any earlier copy first so running add-hook twice stays idempotent,
    # then append to the existing Bash matcher group (or create one).
    jq --arg cmd "$hook_path" --argjson entry "$entry" '
      .hooks //= {}
      | .hooks.PreToolUse //= []
      | .hooks.PreToolUse |= map(.hooks |= map(select(.command != $cmd)))
      | if any(.hooks.PreToolUse[]; .matcher == "Bash")
        then .hooks.PreToolUse |= map(if .matcher == "Bash" then .hooks += [$entry] else . end)
        else .hooks.PreToolUse += [{matcher: "Bash", hooks: [$entry]}]
        end
    ' "$settings_file" > "$tmp_file"
    _write_settings "$tmp_file"

    echo -e "${__green}Registered${__reset} the hook in $settings_file (backup: $settings_file.bak)"
    echo
    echo -e "${__bold}Done.${__reset} From now on Claude Code pipes ${__blue}basecamp${__reset} output through TOON."
    echo -e "Only ${__bold}basecamp${__reset} is handled — other commands are untouched."
    echo -e "Already running a Claude Code session? Restart it or open ${__blue}/hooks${__reset} once to pick up the change."
  }

  # Removes the hook registration and the hook script itself.
  function remove-hook() {
    _require_jq

    if [ ! -f "$settings_file" ]; then
      echo "Nothing to remove: $settings_file does not exist."
    else
      _prepare_settings_file

      local tmp_file="$settings_file.tmp"
      # Remove our entry, then clean up any matcher group it left empty.
      jq --arg cmd "$hook_path" '
        if (.hooks.PreToolUse | type) == "array" then
          .hooks.PreToolUse |= (
            map(.hooks |= map(select(.command != $cmd)))
            | map(select((.hooks | length) > 0))
          )
          | if (.hooks.PreToolUse | length) == 0 then del(.hooks.PreToolUse) else . end
        else . end
      ' "$settings_file" > "$tmp_file"
      _write_settings "$tmp_file"

      echo -e "${__green}Unregistered${__reset} the hook from $settings_file (backup: $settings_file.bak)"
    fi

    if [ -f "$hook_path" ]; then
      rm -f "$hook_path"
      echo -e "${__green}Removed${__reset} $hook_path"
    else
      echo "No hook script found at $hook_path"
    fi

    echo
    echo -e "${__bold}Done.${__reset} Restart your Claude Code session to stop using the hook."
  }

  main "$@"
)
