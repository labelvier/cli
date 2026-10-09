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

  # Claude Code skill for the Timesheet API, shipped as a template dir and
  # copied to ~/.claude/skills/timesheet (the skill needs its browser/ deps).
  local skill_dir="$claude_dir/skills/timesheet"
  local skill_tpl_dir="$claude_tpl_dir/skills/timesheet"

  # Every template carries a "labelvier-ai-version: <n>" stamp. install/check
  # compare it with the installed copy, so outdated files get noticed and
  # refreshed. Bump the stamp in a template whenever its content changes.
  # The managed block in CLAUDE.md has its own version (bump it when the list
  # of @labelvier/... refs changes).
  local claude_md="$claude_dir/CLAUDE.md"
  local snippet_version="1"
  local snippet_start="<!-- labelvier-ai:start version=$snippet_version -->"
  local snippet_end="<!-- labelvier-ai:end -->"
  local snippet_refs="@labelvier/GLOBAL.md @labelvier/WORDPRESS.md @labelvier/ANGULAR.md"

  # Where the Basecamp CLI keeps its OAuth credentials and its cache.
  local basecamp_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/basecamp"
  local basecamp_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/basecamp"

  # Runs the command.
  function main() {
    _dispatch "$filename" "$@"
  }

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Offers to install Homebrew itself (via the official install script) when
  # it's missing, so callers can fall through to `brew install <thing>`
  # instead of just telling the user to go install <thing> by hand. Returns
  # 1 (without exiting) when brew is still unavailable — declined, or the
  # install failed — so callers can fall back to their own manual-install message.
  function _require_brew() {
    if type -P brew >/dev/null 2>&1; then
      return 0
    fi

    echo -e "${__red}Homebrew is not installed.${__reset} It's the easiest way to install missing dependencies."
    local answer
    read -p "Install Homebrew now? [y/N] " answer
    case "$answer" in
      [yY]*) ;;
      *) return 1 ;;
    esac

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # The installer doesn't update PATH in this already-running shell — pick
    # up brew from its known install locations ourselves.
    if ! type -P brew >/dev/null 2>&1; then
      local candidate
      for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
        if [ -x "$candidate" ]; then
          eval "$("$candidate" shellenv)"
          break
        fi
      done
    fi

    if ! type -P brew >/dev/null 2>&1; then
      echo -e "${__red}Homebrew installed but still not on your PATH in this shell.${__reset} Open a new shell and try again."
      return 1
    fi
  }

  # jq is used to merge into settings.json without clobbering existing settings.
  # NOTE: `type -P` searches PATH only — `command -v` would also match the shell
  # functions defined in this file.
  function _require_jq() {
    if type -P jq >/dev/null 2>&1; then
      return 0
    fi

    echo -e "${__red}jq is not installed.${__reset} It is needed to edit $settings_file safely."
    if ! _require_brew; then
      echo -e "Install jq yourself: ${__blue}https://jqlang.github.io/jq/download/${__reset}"
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
      if ! _require_brew; then
        echo -e "Install rtk yourself: ${__blue}https://www.rtk-ai.app/${__reset}"
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
    if ! _require_brew; then
      echo -e "Install Claude Code yourself: ${__blue}https://claude.com/product/claude-code${__reset}"
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

  # Version stamp of a file ("labelvier-ai-version: <n>"). Empty when the file
  # is missing or has no stamp (installed before versions existed).
  function _file_version() {
    [ -f "$1" ] || return 0
    sed -n 's/.*labelvier-ai-version: *\([0-9][0-9.]*\).*/\1/p' "$1" | head -n 1
  }

  # Version of the managed block in CLAUDE.md. Empty when there is none.
  function _snippet_version() {
    [ -f "$claude_md" ] || return 0
    sed -n 's/^<!-- labelvier-ai:start version=\([0-9][0-9.]*\) -->$/\1/p' "$claude_md" | head -n 1
  }

  # Prints "ok", "outdated" or "missing" for a target/template pair.
  function _file_status() {
    local target="$1" template="$2"
    [ -f "$target" ] || { echo missing; return; }
    [ "$(_file_version "$target")" = "$(_file_version "$template")" ] && echo ok || echo outdated
  }

  # List of "target file:template file" pairs the config-file part of
  # check/install works through. Plain array instead of an associative one —
  # this repo targets bash 3.2 (macOS default).
  function _claude_files() {
    echo "$labelvier_dir/GLOBAL.md:$claude_tpl_dir/labelvier/GLOBAL.md.tpl"
    echo "$labelvier_dir/WORDPRESS.md:$claude_tpl_dir/labelvier/WORDPRESS.md.tpl"
    echo "$labelvier_dir/ANGULAR.md:$claude_tpl_dir/labelvier/ANGULAR.md.tpl"
  }

  # "target file:template file" pairs of the timesheet skill. Kept separate
  # from _claude_files: these live in ~/.claude/skills, not ~/.claude/labelvier,
  # and are executable/need npm install afterwards.
  function _skill_files() {
    echo "$skill_dir/SKILL.md:$skill_tpl_dir/SKILL.md.tpl"
    echo "$skill_dir/scripts/timesheet.sh:$skill_tpl_dir/scripts/timesheet.sh.tpl"
    echo "$skill_dir/browser/browser-get.mjs:$skill_tpl_dir/browser/browser-get.mjs.tpl"
    echo "$skill_dir/browser/package.json:$skill_tpl_dir/browser/package.json.tpl"
    echo "$skill_dir/browser/package-lock.json:$skill_tpl_dir/browser/package-lock.json.tpl"
  }

  # True (0) if every skill file is present and the Playwright dependency is installed.
  function _skill_installed() {
    local pair
    while IFS= read -r pair; do
      [ -f "${pair%%:*}" ] || return 1
    done < <(_skill_files)
    [ -d "$skill_dir/browser/node_modules/playwright" ]
  }

  # True (0) if the installed skill carries the same version as the template.
  function _skill_current() {
    [ "$(_file_version "$skill_dir/SKILL.md")" = "$(_file_version "$skill_tpl_dir/SKILL.md.tpl")" ]
  }

  # Offers to store TIMESHEET_API_TOKEN in ~/.claude/.env. Only asks when the
  # token is missing and we have a terminal; otherwise just prints the hint.
  function _setup_skill_token() {
    local env_file="$claude_dir/.env"
    if [ -f "$env_file" ] && grep -q '^TIMESHEET_API_TOKEN=.' "$env_file"; then
      # Sanctum tokens contain '|': quote an unquoted value so the file stays
      # safe to source.
      if grep -q "^TIMESHEET_API_TOKEN=[^\"']" "$env_file"; then
        (umask 077; sed "s/^TIMESHEET_API_TOKEN=\(.*\)\$/TIMESHEET_API_TOKEN=\"\1\"/" "$env_file" > "$env_file.tmp")
        mv "$env_file.tmp" "$env_file"
        chmod 600 "$env_file"
        echo -e "${__green}✓${__reset} Quoted TIMESHEET_API_TOKEN in $env_file"
      fi
      echo -e "${__green}✓${__reset} TIMESHEET_API_TOKEN is set in $env_file"
      return 0
    fi

    echo -e "The timesheet skill needs a ${__bold}TIMESHEET_API_TOKEN${__reset}."
    echo -e "Create one in the Timesheet app under ${__blue}/profiel${__reset} → API-tokens (tick the write ability if the skill should book hours)."

    if [ ! -t 0 ]; then
      echo -e "Then add it to $env_file as ${__bold}TIMESHEET_API_TOKEN=<token>${__reset}."
      return 0
    fi

    local token
    read -r -s -p "Paste your token here (leave empty to skip): " token
    echo
    if [ -z "$token" ]; then
      echo -e "Skipped. Add ${__bold}TIMESHEET_API_TOKEN=<token>${__reset} to $env_file later."
      return 0
    fi

    mkdir -p "$claude_dir"
    # Replace an existing empty/old entry instead of appending a duplicate.
    if [ -f "$env_file" ] && grep -q '^TIMESHEET_API_TOKEN=' "$env_file"; then
      (umask 077; grep -v '^TIMESHEET_API_TOKEN=' "$env_file" > "$env_file.tmp")
      mv "$env_file.tmp" "$env_file"
    fi
    printf 'TIMESHEET_API_TOKEN="%s"\n' "$token" >> "$env_file"
    chmod 600 "$env_file"
    echo -e "${__green}Saved${__reset} the token in $env_file"
  }

  # Installs the timesheet skill and runs npm install for its Playwright
  # dependency. Existing files are only overwritten with --force.
  function _install_skill() {
    local force="$1" pair target template
    local refresh=1
    # Skill files belong together: when SKILL.md is outdated, refresh them all.
    if [ -f "$skill_dir/SKILL.md" ] && ! _skill_current; then
      refresh=0
      local installed_version
      installed_version=$(_file_version "$skill_dir/SKILL.md")
      echo -e "timesheet skill is outdated (installed: ${__bold}${installed_version:-unversioned}${__reset}, available: ${__bold}$(_file_version "$skill_tpl_dir/SKILL.md.tpl")${__reset}), updating."
    fi

    if ! type -P npm >/dev/null 2>&1; then
      echo -e "${__red}npm is not installed.${__reset} The timesheet skill needs it for Playwright. Install Node.js first, then re-run this command."
      return 1
    fi

    while IFS= read -r pair; do
      target="${pair%%:*}"
      template="${pair##*:}"

      if [ ! -f "$template" ]; then
        echo -e "${__red}Template not found:${__reset} $template"
        continue
      fi

      if [ -f "$target" ] && [ "$force" -ne 0 ] && [ "$refresh" -ne 0 ]; then
        echo -e "Up to date, skipped: $target ${__blue}(--force to overwrite)${__reset}"
        continue
      fi

      mkdir -p "$(dirname "$target")"
      cp "$template" "$target"
      echo -e "${__green}Installed${__reset} $target"
    done < <(_skill_files)

    chmod +x "$skill_dir/scripts/timesheet.sh" 2>/dev/null

    if [ -d "$skill_dir/browser/node_modules/playwright" ]; then
      echo -e "${__green}✓${__reset} timesheet skill dependencies already installed"
    else
      (cd "$skill_dir/browser" && npm install --no-audit --no-fund) \
        && echo -e "${__green}Installed${__reset} timesheet skill dependencies" \
        || echo -e "${__red}npm install failed.${__reset} Run it yourself: ${__blue}cd $skill_dir/browser && npm install${__reset}"
    fi

    echo
    _setup_skill_token
  }

  # Removes the timesheet skill directory (incl. node_modules). The token in
  # ~/.claude/.env is the user's own and is left alone.
  function _remove_skill() {
    if [ -d "$skill_dir" ]; then
      rm -rf "$skill_dir"
      echo -e "${__green}Removed${__reset} $skill_dir"
    fi
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
  # This creates it empty if it's missing and maintains one version-stamped
  # block in it that holds the @labelvier/... refs; everything outside that
  # block is left untouched. A block with another version is replaced, and
  # bare ref lines from before the block existed are folded into it.
  function _append_missing_refs() {
    if [ ! -f "$claude_md" ]; then
      mkdir -p "$claude_dir"
      : > "$claude_md"
      echo -e "${__green}Created${__reset} $claude_md (empty)"
    fi

    local installed
    installed=$(_snippet_version)
    if [ "$installed" = "$snippet_version" ]; then
      echo -e "${__green}✓${__reset} CLAUDE.md snippet is up to date (version $snippet_version)"
      return 0
    fi

    _strip_snippet
    {
      printf '\n%s\n' "$snippet_start"
      local ref
      for ref in $snippet_refs; do echo "$ref"; done
      echo "$snippet_end"
    } >> "$claude_md"

    if [ -n "$installed" ]; then
      echo -e "${__green}Updated${__reset} the labelvier snippet in $claude_md (version $installed → $snippet_version)"
    else
      echo -e "${__green}Added${__reset} the labelvier snippet (version $snippet_version) to $claude_md"
    fi
  }

  # Removes the managed block and any legacy bare ref lines from CLAUDE.md.
  # The block is only dropped when its end marker really follows; a start
  # marker without an end marker is left alone (never delete to end of file).
  # Writes through `cat >` so a symlinked CLAUDE.md stays a symlink, and keeps
  # a .bak of the original.
  function _strip_snippet() {
    [ -f "$claude_md" ] || return 0
    local tmp_file="$claude_md.tmp" ref
    cp "$claude_md" "$claude_md.bak"
    awk '
      /^<!-- labelvier-ai:start version=.* -->[[:space:]]*$/ { if (inblock) printf "%s", buf; inblock=1; buf=$0 ORS; next }
      inblock { buf=buf $0 ORS; if ($0 ~ /^<!-- labelvier-ai:end -->[[:space:]]*$/) { inblock=0; buf="" } ; next }
      { print }
      END { if (inblock) printf "%s", buf }
    ' "$claude_md" > "$tmp_file"
    for ref in $snippet_refs; do
      grep -vxF "$ref" "$tmp_file" > "$tmp_file.2"
      mv "$tmp_file.2" "$tmp_file"
    done
    cat "$tmp_file" > "$claude_md"
    rm -f "$tmp_file"
  }

  # Inverse of _append_missing_refs, for uninstall: removes only the snippet
  # (or legacy ref lines) added by this command, plus the @RTK.md line that
  # `rtk init -g` adds but — unlike its own --uninstall — never removes. Never
  # the file itself or anything else in it.
  function _remove_refs() {
    [ -f "$claude_md" ] || return 0

    if [ -n "$(_snippet_version)" ] || grep -qE '^@labelvier/(GLOBAL|WORDPRESS|ANGULAR)\.md$' "$claude_md"; then
      _strip_snippet
      echo -e "${__green}Removed${__reset} the labelvier snippet from $claude_md"
    fi

    if grep -qxF "@RTK.md" "$claude_md"; then
      grep -vxF "@RTK.md" "$claude_md" > "$claude_md.tmp"
      cat "$claude_md.tmp" > "$claude_md"
      rm -f "$claude_md.tmp"
      echo -e "${__green}Removed${__reset} @RTK.md from $claude_md"
    fi
  }

  # ---------------------------------------------------------------------------
  # @function claude
  # @description Installs the global GLOBAL.md/WORDPRESS.md/ANGULAR.md config (wired into your own CLAUDE.md), the timesheet skill, the toon hook, rtk and the caveman plugin. Subcommands: install, uninstall.
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
      install) echo -e "${__bold}install${__reset} - Installs config files, the timesheet skill, the toon hook, rtk and the caveman plugin. Flags: --force, --skip-hook" ;;
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

      local file_status
      file_status=$(_file_status "$target" "$template")
      if [ "$file_status" = "ok" ] && [ "$force" -ne 0 ]; then
        echo -e "Up to date, skipped: $target (version $(_file_version "$target")) ${__blue}(--force to overwrite)${__reset}"
        continue
      fi

      if [ "$file_status" = "outdated" ]; then
        cp "$target" "$target.bak"
        local old_version
        old_version=$(_file_version "$target")
        echo -e "Updating $target: ${__bold}${old_version:-unversioned}${__reset} → $(_file_version "$template") (old copy: $target.bak)"
      fi

      cp "$template" "$target"
      chmod 600 "$target"
      echo -e "${__green}Installed${__reset} $target"
    done < <(_claude_files)

    _append_missing_refs

    echo
    _install_skill "$force"

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
    echo -e "  - the timesheet skill ($skill_dir), if installed"

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
    _remove_skill

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
  # @description Installs the Basecamp CLI and its Claude Code plugin. Subcommands: install, uninstall.
  # ---------------------------------------------------------------------------
  function basecamp() {
    case "$1" in
      install|uninstall)
        if [[ "$2" == "--help" ]]; then
          _basecamp_subcommand_description "$1"
          return
        fi
        "_basecamp_$1" "${@:2}"
        ;;
      ""|-*)
        # No subcommand, or it looks like a flag (e.g. a bare `--help`).
        _basecamp_documentation
        ;;
      *)
        # A subcommand name was typed but it doesn't exist.
        echo -e "${__red}✗${__reset} Unknown command: ${__bold}$1${__reset}"
        echo
        _basecamp_documentation
        return 1
        ;;
    esac
  }

  # Second-level subcommand descriptions, hand-written for the same reason as
  # the claude ones: _echo_documentation only reads the flat "# @function"
  # list of this file, which belongs to `labelvier ai`.
  function _basecamp_subcommand_description() {
    case "$1" in
      install) echo -e "${__bold}install${__reset} - Installs the Basecamp CLI (and, through its own setup, the Claude Code plugin)" ;;
      uninstall) echo -e "${__bold}uninstall${__reset} - Removes the Basecamp CLI, your login and the Claude Code plugin (asks for confirmation)" ;;
      *) echo -e "${__bold}$1${__reset}" ;;
    esac
  }

  function _basecamp_documentation() {
    echo -e "${__bold}labelvier ai basecamp${__reset} — Basecamp CLI setup for Label Vier projects."
    echo
    echo -e "${__bold}Available functions:${__reset}"
    echo -e "  $(_basecamp_subcommand_description install)"
    echo -e "  $(_basecamp_subcommand_description uninstall)"
    echo
    echo -e "Run ${__blue}labelvier ai check${__reset} for status."
  }

  # True (0) if the Basecamp plugin for Claude Code is installed and enabled.
  # The Basecamp installer wires this up itself via `basecamp setup agents`.
  function _basecamp_plugin_installed() {
    type -P claude >/dev/null 2>&1 || return 1
    type -P jq >/dev/null 2>&1 || return 1
    command claude plugin list --json 2>/dev/null | jq -e '.[] | select(.id == "basecamp@37signals" and .enabled == true)' >/dev/null 2>&1
  }

  # Installs the Basecamp CLI. Safe to re-run: skips when already installed.
  function _basecamp_install() {
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

  # Inverse of _basecamp_install: drops the binary, the login and the Claude
  # Code plugin its setup installed.
  function _basecamp_uninstall() {
    # `type -P` searches PATH only — `command -v` would match the shell
    # function of the same name defined right above.
    local binary
    binary=$(type -P basecamp)

    echo -e "${__red}${__bold}Warning:${__reset} this removes everything ${__bold}labelvier ai basecamp install${__reset} sets up:"
    if [ -n "$binary" ]; then
      echo -e "  - the basecamp binary at $binary"
    else
      echo -e "  - the basecamp binary ${__blue}(not on your PATH, nothing to remove)${__reset}"
    fi
    echo -e "  - your Basecamp login: it is logged out and $basecamp_config_dir is deleted"
    echo -e "  - the cache in $basecamp_cache_dir"
    echo -e "  - the Basecamp plugin for Claude Code, if installed"

    echo
    local answer
    read -p "Continue? [y/N] " answer
    case "$answer" in
      [yY]*) ;;
      *) echo "Aborted."; exit 1 ;;
    esac

    # Log out first, while the binary is still there — that revokes the token
    # with Basecamp instead of only orphaning it on disk.
    if [ -n "$binary" ]; then
      command basecamp logout >/dev/null 2>&1 \
        && echo -e "${__green}Logged out${__reset} of Basecamp" \
        || echo "Skipping logout: no active Basecamp session."
    fi

    if _basecamp_plugin_installed; then
      command claude plugin uninstall basecamp@37signals -y
      echo -e "${__green}Removed${__reset} the Basecamp plugin for Claude Code"
    fi

    if [ -n "$binary" ]; then
      rm -f "$binary"
      echo -e "${__green}Removed${__reset} $binary"
    fi

    local dir
    for dir in "$basecamp_config_dir" "$basecamp_cache_dir"; do
      if [ -d "$dir" ]; then
        rm -rf "$dir"
        echo -e "${__green}Removed${__reset} $dir"
      fi
    done

    echo
    echo -e "${__bold}Done.${__reset} Restart your Claude Code session to pick up the changes."
  }

  # ---------------------------------------------------------------------------
  # @function check
  # @description Checks basecamp, toon, rtk, the caveman plugin, the timesheet skill and the Claude Code config.
  # ---------------------------------------------------------------------------
  function check() {
    if type -P basecamp >/dev/null 2>&1; then
      echo -e "${__green}✓${__reset} basecamp"
    else
      echo -e "${__red}✗${__reset} basecamp ${__red}(missing, run: labelvier ai basecamp install)${__reset}"
    fi

    if _basecamp_plugin_installed; then
      echo -e "${__green}✓${__reset} basecamp plugin for Claude Code"
    else
      echo -e "${__red}✗${__reset} basecamp plugin for Claude Code ${__red}(missing, run: labelvier ai basecamp install)${__reset}"
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

    local pair target template file_status old_version
    while IFS= read -r pair; do
      target="${pair%%:*}"
      template="${pair##*:}"
      file_status=$(_file_status "$target" "$template")
      old_version=$(_file_version "$target")
      case "$file_status" in
        ok) echo -e "${__green}✓${__reset} $target (version $(_file_version "$target"))" ;;
        outdated) echo -e "${__red}✗${__reset} $target ${__red}(outdated: installed ${old_version:-unversioned}, available $(_file_version "$template"); run: labelvier ai claude install)${__reset}" ;;
        *) echo -e "${__red}✗${__reset} $target ${__red}(missing, run: labelvier ai claude install)${__reset}" ;;
      esac
    done < <(_claude_files)

    if [ -f "$claude_md" ]; then
      echo -e "${__green}✓${__reset} $claude_md"
      local snippet_installed
      snippet_installed=$(_snippet_version)
      if [ -z "$snippet_installed" ]; then
        echo -e "${__red}✗${__reset} labelvier snippet in $claude_md ${__red}(missing or unversioned, run: labelvier ai claude install)${__reset}"
      elif [ "$snippet_installed" != "$snippet_version" ]; then
        echo -e "${__red}✗${__reset} labelvier snippet in $claude_md ${__red}(outdated: installed $snippet_installed, available $snippet_version; run: labelvier ai claude install)${__reset}"
      else
        echo -e "${__green}✓${__reset} labelvier snippet in $claude_md (version $snippet_installed)"
      fi
    else
      echo -e "${__red}✗${__reset} $claude_md ${__red}(missing, run: labelvier ai claude install)${__reset}"
    fi

    if ! _skill_installed; then
      echo -e "${__red}✗${__reset} $skill_dir (timesheet skill) ${__red}(missing or incomplete, run: labelvier ai claude install)${__reset}"
    elif ! _skill_current; then
      echo -e "${__red}✗${__reset} $skill_dir (timesheet skill) ${__red}(outdated: installed $(_file_version "$skill_dir/SKILL.md"), available $(_file_version "$skill_tpl_dir/SKILL.md.tpl"); run: labelvier ai claude install)${__reset}"
    else
      echo -e "${__green}✓${__reset} $skill_dir (timesheet skill, version $(_file_version "$skill_dir/SKILL.md"))"
    fi

    if [ -f "$claude_dir/.env" ] && grep -q '^TIMESHEET_API_TOKEN=.' "$claude_dir/.env"; then
      echo -e "${__green}✓${__reset} TIMESHEET_API_TOKEN set"
    else
      echo -e "${__red}✗${__reset} TIMESHEET_API_TOKEN ${__red}(not set in $claude_dir/.env, run: labelvier ai claude install)${__reset}"
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
