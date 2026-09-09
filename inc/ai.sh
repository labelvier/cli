#!/bin/bash

ai() (

  # Local filename to echo the documentation.
  local filename="ai.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")

  # Everything Claude Code setup touches lives inside its config dir.
  local claude_dir="$HOME/.claude"
  local hooks_dir="$claude_dir/hooks"
  local hook_path="$hooks_dir/basecamp-toon.sh"
  local settings_file="$claude_dir/settings.json"
  local hook_template="$current_dir/../templates/basecamp-toon.sh.tpl"

  # Global Claude Code config files rolled out to every Label Vier dev.
  local labelvier_dir="$claude_dir/labelvier"
  local claude_tpl_dir="$current_dir/../templates/claude"

  # Runs the command.
  function main() {
    _dispatch "$filename" "$@"
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

  # rtk is a general Claude Code token-saving proxy, not tied to the hook —
  # every Label Vier dev should have it regardless of --skip-hook.
  function _require_rtk() {
    if type -P rtk >/dev/null 2>&1; then
      return 0
    fi

    echo -e "${__red}rtk is not installed.${__reset} It proxies commands (ls, git, ...) to cut Claude Code token usage."
    if ! type -P brew >/dev/null 2>&1; then
      echo -e "Homebrew was not found either. Install rtk yourself: ${__blue}https://www.rtk-ai.app/${__reset}"
      exit 1
    fi

    local answer
    read -p "Install it now with 'brew install rtk'? [y/N] " answer
    case "$answer" in
      [yY]*) brew install rtk ;;
      *) echo "Aborted."; exit 1 ;;
    esac

    if ! type -P rtk >/dev/null 2>&1; then
      echo -e "${__red}rtk is still not on your PATH after installing.${__reset} Open a new shell and try again."
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

  # List of "target file:template file" pairs the config-file part of
  # check/install works through. Plain array instead of an associative one —
  # this repo targets bash 3.2 (macOS default).
  function _claude_files() {
    echo "$claude_dir/CLAUDE.md:$claude_tpl_dir/CLAUDE.md.tpl"
    echo "$labelvier_dir/WORDPRESS.md:$claude_tpl_dir/labelvier/WORDPRESS.md.tpl"
    echo "$labelvier_dir/ANGULAR.md:$claude_tpl_dir/labelvier/ANGULAR.md.tpl"
  }

  # True (0) if the toon hook script is both present and registered in
  # settings.json. Falls back to a plain file check when jq isn't installed.
  function _hook_registered() {
    [ -f "$hook_path" ] || return 1

    if ! type -P jq >/dev/null 2>&1 || [ ! -f "$settings_file" ]; then
      return 1
    fi

    jq -e --arg cmd "$hook_path" \
      '(.hooks.PreToolUse // []) | any(.[].hooks[]?; .command == $cmd)' \
      "$settings_file" >/dev/null 2>&1
  }

  # Installs the hook script and registers it for the Bash tool. Safe to
  # re-run: it replaces its own entry rather than duplicating it.
  function _install_hook() {
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
    # Drop any earlier copy first so running this twice stays idempotent,
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
    echo -e "From now on Claude Code pipes ${__blue}basecamp${__reset} output through TOON. Restart a running session (or open ${__blue}/hooks${__reset} once) to pick it up."
  }

  # Removes the hook registration and the hook script itself.
  function _remove_hook() {
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
  }

  # Appends any missing @labelvier/... reference line to an existing
  # CLAUDE.md. Only adds what's missing, never rewrites the rest of the file.
  function _append_missing_refs() {
    local claude_md="$claude_dir/CLAUDE.md"
    [ -f "$claude_md" ] || return 0

    local ref
    for ref in "@labelvier/WORDPRESS.md" "@labelvier/ANGULAR.md"; do
      if ! grep -q "$ref" "$claude_md"; then
        printf '\n%s\n' "$ref" >> "$claude_md"
        echo -e "${__green}Added${__reset} $ref to $claude_md"
      fi
    done
  }

  # ---------------------------------------------------------------------------
  # @function claude
  # @description Installs the global CLAUDE.md/WORDPRESS.md/ANGULAR.md config, the toon hook and rtk. Subcommands: install, uninstall.
  # ---------------------------------------------------------------------------
  function claude() {
    if [[ -n "$1" ]] && [[ "$1" != -* ]] && type -t "$1" | grep -q 'function'; then
      if [[ "$2" == "--help" ]]; then
        _claude_subcommand_description "$1"
        return
      fi
      "$1" "${@:2}"
    else
      _claude_documentation
    fi
  }

  # Second-level subcommand descriptions, hand-written because
  # _echo_documentation only reads the flat "# @function" list of this file,
  # which belongs to `wp-takeoff ai` (install/uninstall must stay out of it).
  # Shared between the full doc below and `claude <sub> --help`.
  function _claude_subcommand_description() {
    case "$1" in
      install) echo -e "${__bold}install${__reset} - Installs config files, the toon hook and rtk. Flags: --force, --skip-hook" ;;
      uninstall) echo -e "${__bold}uninstall${__reset} - Removes the toon hook and config files (asks for confirmation)" ;;
      *) echo -e "${__bold}$1${__reset}" ;;
    esac
  }

  function _claude_documentation() {
    echo -e "${__bold}wp-takeoff ai claude${__reset} — Claude Code setup for Label Vier projects."
    echo
    echo -e "${__bold}Available functions:${__reset}"
    echo -e "  $(_claude_subcommand_description install)"
    echo -e "  $(_claude_subcommand_description uninstall)"
    echo
    echo -e "Run ${__blue}wp-takeoff ai check${__reset} for status."
  }

  # Creates missing config files from their tpl template and installs the
  # toon hook. Never overwrites an existing config file unless --force is
  # passed; an existing CLAUDE.md only gets the missing @labelvier/... lines
  # appended, so custom content in it is never touched. --skip-hook skips
  # the toon hook step.
  function install() {
    local force=1
    _flag_is_present force "$@" && force=0

    mkdir -p "$labelvier_dir"

    local pair target template
    while IFS= read -r pair; do
      target="${pair%%:*}"
      template="${pair##*:}"

      if [ ! -f "$template" ]; then
        echo -e "${__red}Template not found:${__reset} $template"
        continue
      fi

      if [ -f "$target" ] && [ "$force" -ne 0 ]; then
        echo -e "Already present, skipped: $target ${__blue}(--force to overwrite)${__reset}"
        continue
      fi

      cp "$template" "$target"
      chmod 600 "$target"
      echo -e "${__green}Installed${__reset} $target"
    done < <(_claude_files)

    _append_missing_refs

    echo
    _require_rtk

    if _flag_is_present skip-hook "$@"; then
      echo "Skipped the toon hook (--skip-hook)."
    else
      echo
      _install_hook
    fi
  }

  # Removes the toon hook only — config files hold personal/project edits
  # and are never deleted by this command.
  function uninstall() {
    echo -e "${__red}${__bold}Warning:${__reset} this removes everything ${__bold}wp-takeoff ai claude install${__reset} sets up:"
    echo -e "  - the toon hook script and its registration in $settings_file"

    local pair target
    while IFS= read -r pair; do
      target="${pair%%:*}"
      [ -f "$target" ] && echo -e "  - $target"
    done < <(_claude_files)

    echo
    local answer
    read -p "Continue? [y/N] " answer
    case "$answer" in
      [yY]*) ;;
      *) echo "Aborted."; exit 1 ;;
    esac

    _remove_hook

    while IFS= read -r pair; do
      target="${pair%%:*}"
      if [ -f "$target" ]; then
        rm -f "$target"
        echo -e "${__green}Removed${__reset} $target"
      fi
    done < <(_claude_files)

    # Only removes the directory when empty, so unrelated files someone put there survive.
    rmdir "$labelvier_dir" 2>/dev/null || true

    echo
    echo -e "${__bold}Done.${__reset} Restart your Claude Code session to pick up the changes."
  }

  # ---------------------------------------------------------------------------
  # @function basecamp
  # @description Installs the Basecamp CLI.
  # ---------------------------------------------------------------------------
  function basecamp() {
    if type -P basecamp >/dev/null 2>&1; then
      echo -e "${__green}✓${__reset} basecamp is already installed."
      return 0
    fi

    echo "Installing the Basecamp CLI..."
    curl -fsSL https://basecamp.com/install-cli | bash

    if type -P basecamp >/dev/null 2>&1; then
      echo -e "${__green}Installed${__reset} basecamp"
    else
      echo -e "${__red}basecamp is still not on your PATH after installing.${__reset} Open a new shell and try again."
      exit 1
    fi
  }

  # ---------------------------------------------------------------------------
  # @function check
  # @description Checks basecamp, toon, rtk and the Claude Code config.
  # ---------------------------------------------------------------------------
  function check() {
    if type -P basecamp >/dev/null 2>&1; then
      echo -e "${__green}✓${__reset} basecamp"
    else
      echo -e "${__red}✗${__reset} basecamp ${__red}(missing, run: wp-takeoff ai basecamp)${__reset}"
    fi

    if type -P toon >/dev/null 2>&1; then
      echo -e "${__green}✓${__reset} toon"
    else
      echo -e "${__red}✗${__reset} toon ${__red}(missing, run: npm i -g @toon-format/cli)${__reset}"
    fi

    if type -P rtk >/dev/null 2>&1; then
      echo -e "${__green}✓${__reset} rtk"
    else
      echo -e "${__red}✗${__reset} rtk ${__red}(missing, run: brew install rtk)${__reset}"
    fi

    local pair target
    while IFS= read -r pair; do
      target="${pair%%:*}"
      if [ -f "$target" ]; then
        echo -e "${__green}✓${__reset} $target"
      else
        echo -e "${__red}✗${__reset} $target ${__red}(missing)${__reset}"
      fi
    done < <(_claude_files)

    if [ -f "$claude_dir/CLAUDE.md" ]; then
      if ! grep -q '@labelvier/WORDPRESS.md' "$claude_dir/CLAUDE.md"; then
        echo -e "${__red}✗${__reset} $claude_dir/CLAUDE.md does not reference @labelvier/WORDPRESS.md"
      fi
      if ! grep -q '@labelvier/ANGULAR.md' "$claude_dir/CLAUDE.md"; then
        echo -e "${__red}✗${__reset} $claude_dir/CLAUDE.md does not reference @labelvier/ANGULAR.md"
      fi
    fi

    if _hook_registered; then
      echo -e "${__green}✓${__reset} $hook_path (toon hook, registered)"
    elif [ -f "$hook_path" ]; then
      echo -e "${__red}✗${__reset} $hook_path exists but is not registered in $settings_file"
    else
      echo -e "${__red}✗${__reset} $hook_path (toon hook, missing)"
    fi
  }

  main "$@"
)
