#!/bin/bash

core() (

  # Local filename to echo the documentation.
  local filename="core.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")
  # Official universal (arm64 + x86_64) terminal-notifier build from its GitHub
  # release, pinned by checksum. Used where Homebrew has no bottle.
  local notifier_version="3.1.0"
  local notifier_sha256="e969d4ae20287da1ba55495ae31dcedd8e9069deb8ce4eed24f6561a5fc3e4d5"

  # Runs the command.
  function main() {
    _dispatch "$filename" "$@"
  }

  # @function update
  # @description Check for updates for the CLI, or run it unattended with --auto (--enable-auto/--disable-auto set up the daily run)
  function update() {
    case "$1" in
      --auto) _auto_update ;;
      --enable-auto) _enable_auto_update ;;
      --disable-auto) _disable_auto_update ;;
      *)
        _check_and_ask_for_update
        local status=$?
        # 10 = the CLI updated itself; for the caller that is a success.
        [ "$status" -eq 10 ] && return 0
        return "$status"
        ;;
    esac
  }

  local auto_label="nl.labelvier.cli-update"
  local auto_plist="$HOME/Library/LaunchAgents/$auto_label.plist"
  local auto_dir="$HOME/.labelvier-auto-update"
  local auto_log="$auto_dir/update.log"

  function _auto_log() {
    mkdir -p "$auto_dir"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$auto_log"
  }

  # Shows a macOS notification. Silent no-op elsewhere. Optional $3 is a shell
  # command that runs in a new Terminal window when the notification is
  # clicked. That needs terminal-notifier (brew install terminal-notifier);
  # plain osascript notifications cannot have a click action.
  function _notify() {
    if [ -n "$3" ] && type -P terminal-notifier >/dev/null 2>&1; then
      # A .command file opened with `open` runs in Terminal; this avoids nested
      # shell/AppleScript quoting of the command.
      mkdir -p "$auto_dir"
      local launcher="$auto_dir/notification-action.command"
      printf '#!/bin/bash\n%s\n' "$3" > "$launcher"
      chmod 700 "$launcher"
      terminal-notifier -title "$1" -message "$2" -execute "open $(printf '%q' "$launcher")" >/dev/null 2>&1 && return 0
    fi
    if type -P osascript >/dev/null 2>&1; then
      osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1
    fi
  }

  # @function notifications
  # @description Install terminal-notifier and ask macOS for permission to show clickable update notifications.
  function notifications() {
    if [ "$(uname)" != "Darwin" ]; then
      echo "Notifications are only supported on macOS."
      return 0
    fi

    if ! type -P terminal-notifier >/dev/null 2>&1; then
      echo -e "${__red}terminal-notifier is not installed.${__reset} The automatic update needs it for notifications you can click."
      if ! _require_brew; then
        echo -e "Install it yourself: ${__blue}https://github.com/julienXX/terminal-notifier${__reset}"
        return 1
      fi
      # Homebrew only has a bottle for recent Apple Silicon macOS. Elsewhere
      # (Intel Macs, older macOS) it builds from source, which needs the full
      # Xcode.app. Take the official ready-made build from GitHub there instead.
      if _notifier_has_bottle; then
        _confirm "Install it now with 'brew install terminal-notifier'?"
      else
        _confirm "Install the official ready-made terminal-notifier $notifier_version from GitHub now?"
      fi
      case $? in
        0) if _notifier_has_bottle; then
             brew install terminal-notifier || return 1
           else
             _install_notifier_release || return 1
           fi ;;
        1) echo "  Skipped. Update notifications stay plain (no click action)."; return 1 ;;
        *) return 1 ;;
      esac
    fi

    local status
    status=$(_notification_status)
    case "$status" in
      authorized)
        echo -e "${__green}✓${__reset} terminal-notifier may show notifications"
        _tip_persistent_notifications
        return 0
        ;;
      denied)
        _explain_notifications_denied
        return 1
        ;;
    esac

    # Permission was never asked. Run directly from the Homebrew Cellar, macOS
    # refuses without a prompt ("Notifications are not allowed for this
    # application"). Launching the app bundle once through LaunchServices
    # (`open`) registers it, and then macOS does ask.
    local app
    app=$(terminal-notifier -diagnose 2>/dev/null | sed -n 's/^ *bundle path *//p')
    if [ -z "$app" ] || [ ! -d "$app" ]; then
      echo -e "${__red}Could not find the terminal-notifier app bundle.${__reset} Run: terminal-notifier -diagnose"
      return 1
    fi
    echo "macOS asks for permission to show notifications from terminal-notifier now. Click Allow."
    open -W -n "$app" --args -title "Label Vier CLI" -message "Notifications are on." >/dev/null 2>&1

    status=$(_notification_status)
    case "$status" in
      authorized)
        echo -e "${__green}✓${__reset} terminal-notifier may show notifications"
        _tip_persistent_notifications
        ;;
      denied)
        _explain_notifications_denied
        return 1
        ;;
      *)
        echo -e "${__red}✗${__reset} Permission is still not given (status: ${status:-unknown})."
        echo "  Check System Settings > Notifications > terminal-notifier, or run: terminal-notifier -diagnose"
        return 1
        ;;
    esac
  }

  # Succeeds when Homebrew has a ready-made terminal-notifier for this Mac.
  function _notifier_has_bottle() {
    brew ruby -e 'puts Formula["terminal-notifier"].bottle ? "bottle" : "source"' 2>/dev/null | grep -qx bottle
  }

  # Installs the GitHub release build into ~/Applications and puts a wrapper on
  # PATH next to brew's binaries. A wrapper, not a symlink: through a symlink
  # terminal-notifier cannot find its own app bundle (that is why Homebrew
  # uses one too).
  function _install_notifier_release() {
    local url="https://github.com/julienXX/terminal-notifier/releases/download/$notifier_version/terminal-notifier-$notifier_version.zip"
    local app="$HOME/Applications/terminal-notifier.app"
    local bin="$(brew --prefix)/bin/terminal-notifier"
    local tmp
    tmp=$(mktemp -d) || return 1

    echo "Downloading terminal-notifier $notifier_version..."
    if ! curl -fsSL "$url" -o "$tmp/terminal-notifier.zip"; then
      echo -e "${__red}Download failed:${__reset} $url"
      rm -rf "$tmp"
      return 1
    fi
    if [ "$(shasum -a 256 "$tmp/terminal-notifier.zip" | awk '{print $1}')" != "$notifier_sha256" ]; then
      echo -e "${__red}The download does not match the expected checksum, not installing it.${__reset}"
      rm -rf "$tmp"
      return 1
    fi

    ditto -x -k "$tmp/terminal-notifier.zip" "$tmp" \
      && mkdir -p "$HOME/Applications" \
      && rm -rf "$app" \
      && mv "$tmp/terminal-notifier.app" "$app" \
      && printf '#!/bin/bash\nexec %q "$@"\n' "$app/Contents/MacOS/terminal-notifier" > "$bin" \
      && chmod 755 "$bin"
    local status=$?
    rm -rf "$tmp"
    if [ "$status" -ne 0 ]; then
      echo -e "${__red}Installing terminal-notifier failed.${__reset}"
      return 1
    fi
    echo -e "${__green}✓${__reset} terminal-notifier $notifier_version installed in $app"
  }

  # Prints terminal-notifier's authorization status (authorized, denied,
  # not determined, ...) without showing a notification. Empty when it is
  # not installed.
  function _notification_status() {
    type -P terminal-notifier >/dev/null 2>&1 || return 0
    terminal-notifier -diagnose 2>/dev/null | sed -n 's/^ *authorization *//p'
  }

  # A temporary banner disappears after a few seconds, so the update
  # notification is easy to miss. Apps cannot change this style themselves.
  function _tip_persistent_notifications() {
    if terminal-notifier -diagnose 2>/dev/null | grep -q '^ *alert style *banners'; then
      echo "  Tip: set the banner style to Persistent in System Settings > Notifications > terminal-notifier,"
      echo "  so the update notification stays until you click it."
    fi
  }

  function _explain_notifications_denied() {
    echo -e "${__red}✗${__reset} Notifications from terminal-notifier are turned off."
    echo "  Turn them on in System Settings > Notifications > terminal-notifier."
    open "x-apple.systempreferences:com.apple.Notifications-Settings.extension" >/dev/null 2>&1
  }

  # Unattended update: fast-forward only, never force, never prompts. Runs
  # `ai check` afterwards and sends a notification when something needs
  # attention. It does NOT fix anything itself (new skills and config changes
  # always need a human yes via `labelvier ai update`).
  function _auto_update() {
    local cli_dir
    cli_dir=$(cd "$current_dir/.." && pwd)
    [ -d "$cli_dir/.git" ] || { _auto_log "skip: $cli_dir is not a git checkout"; return 0; }

    # Lock against double runs; a lock older than an hour is stale.
    mkdir -p "$auto_dir"
    local lock="$auto_dir/lock"
    if ! mkdir "$lock" 2>/dev/null; then
      if [ -n "$(find "$lock" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then
        rm -rf "$lock"; mkdir "$lock" || return 0
      else
        _auto_log "skip: another run is active"; return 0
      fi
    fi
    # Expand $lock now: the trap fires when the subshell exits, after this
    # function returned and its local variables are gone.
    trap "rm -rf '$lock'" EXIT

    cd "$cli_dir" || return 0
    _migrate_remote_if_needed
    if ! git fetch --tags --force --quiet 2>>"$auto_log"; then
      _auto_log "skip: git fetch failed (offline?)"; return 0
    fi

    local before after
    before=$(git rev-parse --short HEAD)
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
      _auto_log "skip update: working directory has local changes"
    elif git symbolic-ref -q HEAD > /dev/null; then
      if ! git merge --ff-only --quiet '@{u}' 2>>"$auto_log"; then
        _auto_log "skip update: cannot fast-forward (diverged or no upstream)"
      fi
    else
      local current newest
      current=$(git describe --tags --exact-match 2>/dev/null)
      newest=$(git tag --sort=-v:refname | head -1)
      if [ -n "$current" ] && [ -n "$newest" ] && [ "$current" != "$newest" ]; then
        git checkout --quiet "$newest" 2>>"$auto_log"
      fi
    fi
    after=$(git rev-parse --short HEAD)
    if [ "$before" != "$after" ]; then
      _auto_log "updated $before -> $after"
    else
      _auto_log "up-to-date at $after"
    fi

    # Run the checks of the (possibly just updated) CLI: the required tools of
    # `setup` and the AI setup. No terminal here, so `setup tools` only checks;
    # every install in it asks first.
    local result tools_ok=1
    "$cli_dir/labelvier" setup tools </dev/null >/dev/null 2>&1 || tools_ok=0
    result=$("$cli_dir/labelvier" ai check 2>&1)
    if [ "$tools_ok" -eq 0 ]; then
      # setup also walks through notifications and `ai update`, so it covers everything.
      _auto_log "setup tools found missing tools"
      _notify "Label Vier CLI" "Something needs attention. Open the terminal and type: labelvier setup" "$(printf '%q' "$cli_dir/labelvier") setup"
    elif echo "$result" | grep -q '✗'; then
      _auto_log "ai check found problems"
      _notify "Label Vier CLI" "Something needs attention. Open the terminal and type: labelvier ai update" "$(printf '%q' "$cli_dir/labelvier") ai update"
    elif [ "$before" != "$after" ]; then
      _notify "Label Vier CLI" "Updated to version $(git describe --tags --abbrev=0 2>/dev/null || echo "$after"), all checks passed."
    fi
  }

  function _enable_auto_update() {
    if [ "$(uname)" != "Darwin" ]; then
      echo "Automatic updates use launchd and are only supported on macOS."
      return 1
    fi
    local cli_dir
    cli_dir=$(cd "$current_dir/.." && pwd)
    # launchd starts with a bare PATH, without nvm (toon), ~/.local/bin
    # (claude, basecamp) and the like, so `ai check` would report those as
    # missing every day. Take the PATH of the shell that turns this on, with
    # the system defaults appended, escaped for the XML plist.
    local launchd_path
    launchd_path=$(printf '%s' "$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
    mkdir -p "$(dirname "$auto_plist")" "$auto_dir"
    cat > "$auto_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$auto_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$cli_dir/labelvier</string>
    <string>core</string>
    <string>update</string>
    <string>--auto</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$launchd_path</string>
    <key>LABELVIER_AUTO_UPDATE</key><string>1</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>86400</integer>
  <key>StandardErrorPath</key><string>$auto_log</string>
</dict>
</plist>
PLIST
    launchctl unload "$auto_plist" 2>/dev/null
    launchctl load "$auto_plist"
    echo "Automatic updates enabled: the CLI checks once a day (log: $auto_log)."
    echo "It uses the PATH of this shell. Installed a new Node version or tool elsewhere? Run this again."
    echo "Turn off with: labelvier core update --disable-auto"
    echo
    notifications
  }

  function _disable_auto_update() {
    # Turned off on purpose: do not offer it again from ai update.
    _choice_set auto_update no
    if [ -f "$auto_plist" ]; then
      launchctl unload "$auto_plist" 2>/dev/null
      rm -f "$auto_plist"
      echo "Automatic updates disabled."
    else
      echo "Automatic updates were not enabled."
    fi
  }

  function _run_update_checker() {
    # The unattended run (launchd) handles updating itself.
    [ -n "$LABELVIER_AUTO_UPDATE" ] && return
    # Check if there are updates available from git and ask if we should pull them
    if [ -d "$current_dir/../.git" ]; then
      # echo date minus 12 hours, don't use -d option because it's not available on mac
      last_git_check="$current_dir/../.last_git_check"
      if [ ! -f "$last_git_check" ]; then
        last_update=0;
      else
        # check the last time the .last_git_check was touched
        last_update=$(date -r "$last_git_check" +%s)
      fi
      now=$(date -u +%s)
      diff=$(($now - $last_update))

      # Don't check if we checked in the last 12 hours
      twelve_hours=43200;
      if [ $diff -gt $twelve_hours ]; then
        _check_and_ask_for_update
        local status=$?
        touch "$last_git_check"
        return $status
      fi
    fi
  }

  function _migrate_remote_if_needed() {
    # Migrate the remote from Bitbucket to GitHub if needed
    local current_remote
    current_remote=$(git remote get-url origin 2>/dev/null)
    if [[ "$current_remote" == *"bitbucket.org"* ]]; then
      echo "Migrating the CLI remote from Bitbucket to GitHub..."
      git remote set-url origin git@github.com:labelvier/cli.git
      git remote set-url origin git@github.com:labelvier/cli.git --push
      echo "Remote updated. Future updates will be fetched from GitHub."
    fi
  }

  # Update check for an install that is pinned to a release tag.
  #
  # Such an install has no upstream branch, so "is the remote ahead" has no
  # meaning here. The question is whether a newer release exists, and the answer
  # is another checkout rather than a pull.
  #
  # Assumes the caller is already in the CLI directory and has fetched.
  function _check_pinned_release() {
    local current newest

    current=$(git describe --tags --exact-match 2>/dev/null)
    newest=$(git tag --sort=-v:refname | head -1)

    if [ -z "$newest" ] || [ "$current" = "$newest" ]; then
      echo "Up-to-date"
      return
    fi

    if [ -z "$current" ]; then
      echo "This CLI is on a detached HEAD that is not a release tag, leaving it alone."
      return
    fi

    echo "You are on release $current, $newest is available. Do you want to update? (y/n)"
    read -r answer
    if [ "$answer" == "y" ]; then
      git -P log --pretty=oneline --abbrev-commit "$current".."$newest"
      git checkout --quiet "$newest"
      echo "Now on $newest. Please restart the CLI."
      exit 0
    fi
  }

  function _check_and_ask_for_update() {
    # Check if there are updates available from git and ask if we should pull them
    local OLDPWD=$(pwd);
    if [ -d "$current_dir/../.git" ]; then
      # Open the CLI dir
      cd "$current_dir/.."
      # Migrate remote from Bitbucket to GitHub if needed
      _migrate_remote_if_needed
      # Fetch the latest version
      git fetch --tags --force
      # An install pinned to a release sits on a detached HEAD, so there is no
      # upstream branch to compare against and every rev-parse below would
      # fail. Compare against the newest tag instead.
      if ! git symbolic-ref -q HEAD > /dev/null; then
        _check_pinned_release
        cd "$OLDPWD"
        return
      fi
      # Check if remote is ahead of local branch
      UPSTREAM=${1:-'@{u}'}
      LOCAL=$(git rev-parse @)
      REMOTE=$(git rev-parse "$UPSTREAM")
      BASE=$(git merge-base @ "$UPSTREAM")
      echo "Checking for updates..."
      if [ "$LOCAL" = "$REMOTE" ]; then
        echo "Up-to-date"
      elif [ "$LOCAL" = "$BASE" ]; then
        echo "Need to pull"
      elif [ "$REMOTE" = "$BASE" ]; then
        echo "Need to push"
      else
        echo "Diverged"
      fi

      # Check if there are updates available from git and ask if we should pull them
      if [ "$LOCAL" != "$REMOTE" ]; then
        echo "There is an update available for the CLI. Do you want to update? (y/n)"
        read -r answer
        if [ "$answer" == "y" ]; then
          # echo commits which are not in local branch but on remote
          git -P log --pretty=oneline --abbrev-commit "$LOCAL".."$REMOTE"
          if ! git pull; then
            cd "$OLDPWD"
            return 1
          fi
          echo -e "${__green}Update complete.${__reset}"
          touch "$current_dir/../.last_git_check"

          # An update can bring new tools, skills or config. This process still
          # runs the old functions, so setup runs in a fresh CLI process.
          cd "$OLDPWD"
          echo
          if _confirm_remembered setup_after_update "Run 'labelvier setup' now to install what this update needs?"; then
            "$current_dir/../labelvier" setup
          else
            echo "Run it later with: labelvier setup"
          fi
          # 10 = updated: the caller must stop, its loaded code is outdated.
          return 10
        else
          # return to old PWD
          cd "$OLDPWD"
        fi
      fi
    fi
  }

  # @function choices
  # @description Show the remembered answers to optional questions, or forget them with --reset [key]
  function choices() {
    local file
    file=$(_choices_file)

    if [ "$1" = "--reset" ]; then
      if [ -n "$2" ]; then
        _choice_reset "$2"
        echo "Forgot the answer for $2, the CLI asks again when it needs it."
      else
        _choice_reset
        echo "Forgot all remembered answers, the CLI asks again when it needs them."
      fi
      return 0
    fi

    if [ ! -s "$file" ]; then
      echo "No remembered answers."
      return 0
    fi
    echo "Remembered answers ($file):"
    sed 's/^/  /; s/=/: /' "$file"
    echo "Forget them with: labelvier core choices --reset [key]"
  }

  # @function install
  # @description Install the CLI on the system
  function install() {
    # Check if the CLI is already located in ~/.labelvier
    if [ -d "$HOME/.labelvier" ]; then
      echo "The CLI is already installed in $HOME/.labelvier"
    else
      # move the CLI to ~/.labelvier
      mv "$PWD" "$HOME/.labelvier"
      echo "The CLI is installed in $HOME/.labelvier"
    fi

    # Check if the CLI is already in the PATH
    if [[ ":$PATH:" == *"$HOME/.labelvier:"* ]]; then
      echo "labelvier is already present in the \$PATH variable"
    else
      local added_to_path=false
      # Ask if the user wants to add the CLI to the PATH. Let the user select the shell to add it to.
      options=("Bash" "Zsh" "Fish" "Cancel")
      echo "To which shell do you want to add the CLI to the \$PATH variable?"
      select opt in "${options[@]}"; do
        case $opt in
        "Bash")
          echo "export PATH=\$PATH:\$HOME/.labelvier" >>~/.bashrc
          added_to_path="bash"
          break
          ;;
        "Zsh")
          echo "export PATH=\$PATH:\$HOME/.labelvier" >>~/.zshrc
          added_to_path="zsh"
          break
          ;;
        "Fish")
          echo "set -gx PATH \$PATH \$HOME/.labelvier" >>~/.config/fish/config.fish
          added_to_path="fish"
          break
          ;;
        "Cancel")
          break
          ;;
        *) echo "invalid option $REPLY" ;;
        esac
      done

      if [ "$added_to_path" != false ]; then
        echo "The CLI is added to the \$PATH variable, now restart your $added_to_path shell to use the CLI."
      else
        echo "The CLI is not added to the \$PATH variable"
      fi
    fi

    # The checkout may just have been moved, so run setup from its new place.
    echo
    if _confirm "Run 'labelvier setup' now to install the required tools and the AI setup?"; then
      "$HOME/.labelvier/labelvier" setup
    else
      echo "Run it later with: labelvier setup"
    fi
  }

  # @function alias
  # @description Alias the CLI to a shorter name you can choose
  function alias() {
    # Ask what the user wants to use as an alias
    echo "What do you want to use as an alias for the CLI?"
    read -r alias
    # Ask which shell to add the alias to
    options=("Bash" "Zsh" "Cancel")
    echo "To which shell do you want to add the alias?"
    select opt in "${options[@]}"; do
      case $opt in
      "Bash")
        _add_alias_to_shell "$alias" ".bashrc"
        break
        ;;
      "Zsh")
        _add_alias_to_shell "$alias" ".zshrc"
        break
        ;;
      "Cancel")
        break
        ;;
      *) echo "invalid option $REPLY" ;;
      esac
    done
  }

  function _add_alias_to_shell() {
    # Get the correct file
    local alias=$1
    local shell_file=$2
    # Check if the alias is already in the .bashrc or .zshrc file
    if grep -q "alias $alias=" ~/$shell_file; then
      echo "The alias $alias is already in use"
    else
      # Add the alias to the .bashrc or .zshrc file with line breaks
      echo "" >>~/$shell_file
      echo "alias $alias='labelvier'" >>~/$shell_file
      echo "The alias $alias is added to the $shell_file file, now restart your $shell_file shell to use the CLI."
    fi
  }

  # @function generate <optional-command-name> <optional-first-command-name>
  # @description Generate a new command collection. Pass both names as args to skip the prompts.
  function generate () {
    local command_name="$1"
    local first_command_name="$2"

    # Ask for the command name if it wasn't passed as an argument
    if [[ -z "$command_name" ]]; then
      echo "What is the name of the command collection (i.e. core, release, deploy)?"
      read -r command_name
    fi
    # Check if there are any characters in the command name that are not allowed for a bash function name / file name
    if [[ "$command_name" =~ [^a-zA-Z0-9_-] ]]; then
      echo "The command name can only contain letters, numbers, underscores and dashes"
      exit 1
    fi
    # Copy example.sh.tpl to the command name
    cp "$current_dir/../templates/example.sh.tpl" "$current_dir/$command_name.sh"
    # Replace the command name in the file
    sed -i.bak "s/global_command_name/$command_name/g" "$current_dir/$command_name.sh" && rm -f "$current_dir/$command_name.sh.bak"
    # Ask for the first command name if it wasn't passed as an argument
    if [[ -z "$first_command_name" ]]; then
      echo "What is the name of the first command (i.e. list, install, deploy)?"
      read -r first_command_name
    fi
    # Check if there are any characters in the command name that are not allowed for a bash function name / file name
    if [[ "$first_command_name" =~ [^a-zA-Z0-9_-] ]]; then
      echo "The command name can only contain letters, numbers, underscores and dashes"
      exit 1
    fi
    # Replace the command name in the file
    sed -i.bak "s/first_command_name/$first_command_name/g" "$current_dir/$command_name.sh" && rm -f "$current_dir/$command_name.sh.bak"
    echo "Generated $current_dir/$command_name.sh"
  }

  _get_package_version() {
    local package_version=$(cat "$current_dir/../package.json" | grep '"version":' | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
    echo "$package_version"
  }

  main "$@"
)
