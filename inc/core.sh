#!/bin/bash

core() (

  # Local filename to echo the documentation.
  local filename="core.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")

  # Runs the command.
  function main() {
    _dispatch "$filename" "$@"
  }

  # @function update
  # @description Check for updates for the CLI
  function update() {
    _check_and_ask_for_update
  }

  function _run_update_checker() {
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
        touch "$last_git_check"
      fi
    fi
  }

  function _migrate_remote_if_needed() {
    # Migrate the remote from Bitbucket to GitHub if needed
    local current_remote
    current_remote=$(git remote get-url origin 2>/dev/null)
    if [[ "$current_remote" == *"bitbucket.org"* ]]; then
      echo "Migrating the CLI remote from Bitbucket to GitHub..."
      git remote set-url origin git@github.com:labelvier/WP-Takeoff-CLI.git
      git remote set-url origin git@github.com:labelvier/WP-Takeoff-CLI.git --push
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
          git pull
          echo "Update complete. Please restart the CLI."
          exit 0
        else
          # return to old PWD
          cd "$OLDPWD"
        fi
      fi
    fi
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
    sed -i '' "s/global_command_name/$command_name/g" "$current_dir/$command_name.sh"
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
    sed -i '' "s/first_command_name/$first_command_name/g" "$current_dir/$command_name.sh"
    echo "Generated $current_dir/$command_name.sh"
  }

  _get_package_version() {
    local package_version=$(cat "$current_dir/../package.json" | grep '"version":' | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
    echo "$package_version"
  }

  main "$@"
)
