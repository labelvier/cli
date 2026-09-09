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
    if ! type -P rtk >/dev/null 2>&1; then
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
    fi

    # The binary alone does nothing — `rtk init -g` is what actually wires it
    # up: writes ~/.claude/RTK.md, patches the Claude Code hook into
    # settings.json, and appends the @RTK.md import to CLAUDE.md. Idempotent,
    # so safe to re-run every time install runs.
    if rtk init -g --auto-patch; then
      echo -e "${__green}✓${__reset} rtk wired into Claude Code (RTK.md, hook, CLAUDE.md import)"
    else
      echo -e "${__red}rtk init -g failed.${__reset} Run it yourself: ${__blue}rtk init -g${__reset}"
    fi
  }

  # claude itself (the Claude Code CLI) is needed to manage plugins like caveman.
  function _require_claude_cli() {
    if type -P claude >/dev/null 2>&1; then
      return 0
    fi

    echo -e "${__red}The 'claude' command is not installed.${__reset} It is needed to install the caveman plugin."
    if ! type -P brew >/dev/null 2>&1; then
      echo -e "Homebrew was not found either. Install Claude Code yourself: ${__blue}https://claude.com/product/claude-code${__reset}"
      exit 1
    fi

    local answer
    read -p "Install it now with 'brew install --cask claude-code'? [y/N] " answer
    case "$answer" in
      [yY]*) brew install --cask claude-code ;;
      *) echo "Aborted."; exit 1 ;;
    esac

    if ! type -P claude >/dev/null 2>&1; then
      echo -e "${__red}'claude' is still not on your PATH after installing.${__reset} Open a new shell and try again."
      exit 1
    fi
  }

  # True (0) if the caveman plugin is installed and enabled.
  function _caveman_installed() {
    type -P claude >/dev/null 2>&1 || return 1
    type -P jq >/dev/null 2>&1 || return 1
    command claude plugin list --json 2>/dev/null | jq -e '.[] | select(.id == "caveman@caveman" and .enabled == true)' >/dev/null 2>&1
  }

  # Installs the caveman Claude Code plugin (github.com/JuliusBrussee/caveman) —
  # ultra-compressed communication mode. Safe to re-run: skips when already installed.
  function _install_caveman() {
    _require_claude_cli
    _require_jq

    if _caveman_installed; then
      echo -e "${__green}✓${__reset} caveman plugin already installed"
      return 0
    fi

    command claude plugin marketplace add JuliusBrussee/caveman
    command claude plugin install caveman@caveman -y -s user

    if _caveman_installed; then
      echo -e "${__green}Installed${__reset} caveman plugin"
    else
      echo -e "${__red}Failed to install the caveman plugin.${__reset} Run it yourself: ${__blue}claude plugin marketplace add JuliusBrussee/caveman && claude plugin install caveman@caveman${__reset}"
    fi
  }

  # Removes the caveman plugin and its marketplace registration.
  function _remove_caveman() {
    if ! type -P claude >/dev/null 2>&1; then
      echo "Skipping caveman plugin removal: 'claude' is not installed."
      return 0
    fi

    if _caveman_installed; then
      command claude plugin uninstall caveman@caveman -y
      echo -e "${__green}Removed${__reset} caveman plugin"
    fi

    command claude plugin marketplace remove caveman >/dev/null 2>&1 \
      && echo -e "${__green}Removed${__reset} the caveman marketplace"
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
    echo "$labelvier_dir/GLOBAL.md:$claude_tpl_dir/labelvier/GLOBAL.md.tpl"
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

  # CLAUDE.md is the user's own file — we never overwrite or template it.
  # This only creates it empty if it's missing (so the refs below have
  # somewhere to live) and appends whatever @labelvier/... lines are missing,
  # leaving all of the user's own content untouched.
  function _append_missing_refs() {
    local claude_md="$claude_dir/CLAUDE.md"
    if [ ! -f "$claude_md" ]; then
      mkdir -p "$claude_dir"
      : > "$claude_md"
      echo -e "${__green}Created${__reset} $claude_md (empty)"
    fi

    local ref
    for ref in "@labelvier/GLOBAL.md" "@labelvier/WORDPRESS.md" "@labelvier/ANGULAR.md"; do
      if ! grep -qxF "$ref" "$claude_md"; then
        printf '\n%s\n' "$ref" >> "$claude_md"
        echo -e "${__green}Added${__reset} $ref to $claude_md"
      fi
    done
  }

  # Inverse of _append_missing_refs, for uninstall: removes only the
  # reference lines added by this command (or by `rtk init -g`, which adds
  # @RTK.md but — unlike its own --uninstall — never removes it), never the
  # file itself or anything else in it.
  function _remove_refs() {
    local claude_md="$claude_dir/CLAUDE.md"
    [ -f "$claude_md" ] || return 0

    local ref tmp_file="$claude_md.tmp"
    for ref in "@labelvier/GLOBAL.md" "@labelvier/WORDPRESS.md" "@labelvier/ANGULAR.md" "@RTK.md"; do
      if grep -qxF "$ref" "$claude_md"; then
        grep -vxF "$ref" "$claude_md" > "$tmp_file" && mv "$tmp_file" "$claude_md"
        echo -e "${__green}Removed${__reset} $ref from $claude_md"
      fi
    done
  }

  # ---------------------------------------------------------------------------
  # @function claude
  # @description Installs the global GLOBAL.md/WORDPRESS.md/ANGULAR.md config (wired into your own CLAUDE.md), the toon hook, rtk and the caveman plugin. Subcommands: install, uninstall.
  # ---------------------------------------------------------------------------
  function claude() {
    case "$1" in
      install|uninstall)
        if [[ "$2" == "--help" ]]; then
          _claude_subcommand_description "$1"
          return
        fi
        "_claude_$1" "${@:2}"
        ;;
      ""|-*)
        # No subcommand, or it looks like a flag (e.g. a bare `--help`).
        _claude_documentation
        ;;
      *)
        # A subcommand name was typed but it doesn't exist.
        echo -e "${__red}✗${__reset} Unknown command: ${__bold}$1${__reset}"
        echo
        _claude_documentation
        return 1
        ;;
    esac
  }

  # Second-level subcommand descriptions, hand-written because
  # _echo_documentation only reads the flat "# @function" list of this file,
  # which belongs to `labelvier ai` (install/uninstall must stay out of it).
  # Shared between the full doc below and `claude <sub> --help`.
  function _claude_subcommand_description() {
    case "$1" in
      install) echo -e "${__bold}install${__reset} - Installs config files, the toon hook, rtk and the caveman plugin. Flags: --force, --skip-hook" ;;
      uninstall) echo -e "${__bold}uninstall${__reset} - Removes the toon hook and config files (asks for confirmation)" ;;
      *) echo -e "${__bold}$1${__reset}" ;;
    esac
  }

  function _claude_documentation() {
    echo -e "${__bold}labelvier ai claude${__reset} — Claude Code setup for Label Vier projects."
    echo
    echo -e "${__bold}Available functions:${__reset}"
    echo -e "  $(_claude_subcommand_description install)"
    echo -e "  $(_claude_subcommand_description uninstall)"
    echo
    echo -e "Run ${__blue}labelvier ai check${__reset} for status."
  }

  # Creates missing config files from their tpl template and installs the
  # toon hook. Never overwrites an existing config file unless --force is
  # passed. CLAUDE.md itself is never templated/overwritten — it only gets
  # the missing @labelvier/... lines appended (see _append_missing_refs), so
  # personal content in it is never touched. --skip-hook skips the toon hook
  # step.
  function _claude_install() {
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

    echo
    _install_caveman

    if _flag_is_present skip-hook "$@"; then
      echo "Skipped the toon hook (--skip-hook)."
    else
      echo
      _install_hook
    fi
  }

  # Removes the toon hook and the @labelvier/... refs it added to CLAUDE.md —
  # never the file itself, which holds personal/project edits.
  function _claude_uninstall() {
    echo -e "${__red}${__bold}Warning:${__reset} this removes everything ${__bold}labelvier ai claude install${__reset} sets up:"
    echo -e "  - the toon hook script and its registration in $settings_file"
    echo -e "  - the @labelvier/... and @RTK.md reference lines in CLAUDE.md (not the file itself)"
    echo -e "  - rtk's own artifacts (RTK.md, its Claude Code hook) via ${__bold}rtk init -g --uninstall${__reset}, if rtk is installed"
    echo -e "  - the caveman plugin and its marketplace registration, if installed"

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
    _remove_caveman

    # Delegate to rtk's own uninstall rather than reimplementing it — it
    # removes RTK.md, its settings.json hook entry, and usually the @RTK.md
    # line too; _remove_refs below is just a safety net in case it doesn't.
    if type -P rtk >/dev/null 2>&1; then
      rtk init -g --uninstall --auto-patch || echo -e "${__red}rtk init -g --uninstall failed.${__reset} Run it yourself: ${__blue}rtk init -g --uninstall${__reset}"
    fi
    _remove_refs

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
  # @description Checks basecamp, toon, rtk, the caveman plugin and the Claude Code config.
  # ---------------------------------------------------------------------------
  function check() {
    if type -P basecamp >/dev/null 2>&1; then
      echo -e "${__green}✓${__reset} basecamp"
    else
      echo -e "${__red}✗${__reset} basecamp ${__red}(missing, run: labelvier ai basecamp)${__reset}"
    fi

    if type -P toon >/dev/null 2>&1; then
      echo -e "${__green}✓${__reset} toon"
    else
      echo -e "${__red}✗${__reset} toon ${__red}(missing, run: labelvier ai claude install)${__reset}"
    fi

    if type -P rtk >/dev/null 2>&1; then
      echo -e "${__green}✓${__reset} rtk"
    else
      echo -e "${__red}✗${__reset} rtk ${__red}(missing, run: labelvier ai claude install)${__reset}"
    fi

    # Ask rtk itself whether it's fully wired into Claude Code (RTK.md, hook,
    # @RTK.md import) instead of re-implementing its own checks here.
    if type -P rtk >/dev/null 2>&1; then
      local rtk_status
      rtk_status=$(rtk init -g --dry-run 2>&1)
      if echo "$rtk_status" | grep -q '^\[dry-run\] would'; then
        echo -e "${__red}✗${__reset} rtk not fully wired into Claude Code ${__red}(run: labelvier ai claude install)${__reset}"
        echo "$rtk_status" | grep '^\[dry-run\] would' | sed 's/^/    /'
      else
        echo -e "${__green}✓${__reset} rtk wired into Claude Code"
      fi
    fi

    if _caveman_installed; then
      echo -e "${__green}✓${__reset} caveman plugin"
    else
      echo -e "${__red}✗${__reset} caveman plugin ${__red}(missing, run: labelvier ai claude install)${__reset}"
    fi

    local pair target
    while IFS= read -r pair; do
      target="${pair%%:*}"
      if [ -f "$target" ]; then
        echo -e "${__green}✓${__reset} $target"
      else
        echo -e "${__red}✗${__reset} $target ${__red}(missing, run: labelvier ai claude install)${__reset}"
      fi
    done < <(_claude_files)

    if [ -f "$claude_dir/CLAUDE.md" ]; then
      echo -e "${__green}✓${__reset} $claude_dir/CLAUDE.md"
      local ref
      for ref in "@labelvier/GLOBAL.md" "@labelvier/WORDPRESS.md" "@labelvier/ANGULAR.md"; do
        if ! grep -qxF "$ref" "$claude_dir/CLAUDE.md"; then
          echo -e "${__red}✗${__reset} $claude_dir/CLAUDE.md does not reference $ref ${__red}(run: labelvier ai claude install)${__reset}"
        fi
      done
    else
      echo -e "${__red}✗${__reset} $claude_dir/CLAUDE.md ${__red}(missing, run: labelvier ai claude install)${__reset}"
    fi

    if _hook_registered; then
      echo -e "${__green}✓${__reset} $hook_path (toon hook, registered)"
    elif [ -f "$hook_path" ]; then
      echo -e "${__red}✗${__reset} $hook_path exists but is not registered in $settings_file ${__red}(run: labelvier ai claude install)${__reset}"
    else
      echo -e "${__red}✗${__reset} $hook_path (toon hook) ${__red}(missing, run: labelvier ai claude install)${__reset}"
    fi
  }

  main "$@"
)
