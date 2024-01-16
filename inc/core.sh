#!/bin/bash

core() (

  # Local filename to echo the documentation.
  local filename="core.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")

  # Runs the command.
  function main() {
    # try to run the subcommand passed as the second argument and that function exists
    if [[ -n "$1" ]] && type -t "$1" | grep -q 'function'; then
      "$1"
    else
      # if no subcommand is passed, run the documentation function
      _echo_documentation "$filename"
    fi
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

  function _check_and_ask_for_update() {
    # Check if there are updates available from git and ask if we should pull them
    local OLDPWD=$(pwd);
    if [ -d "$current_dir/../.git" ]; then
      # Open wp-takeoff dir
      cd "$current_dir/.."
      # Fetch the latest version
      git fetch
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
    # Check if the CLI is already located in ~/.wp-takeoff
    if [ -d "$HOME/.wp-takeoff" ]; then
      echo "The CLI is already installed in $HOME/.wp-takeoff"
    else
      # move the CLI to ~/.wp-takeoff
      mv "$PWD" "$HOME/.wp-takeoff"
      echo "The CLI is installed in $HOME/.wp-takeoff"
    fi

    # Check if the CLI is already in the PATH
    if [[ ":$PATH:" == *"$HOME/.wp-takeoff:"* ]]; then
      echo "wp-takeoff is already present in the \$PATH variable"
    else
      local added_to_path=false
      # Ask if the user wants to add the CLI to the PATH. Let the user select the shell to add it to.
      options=("Bash" "Zsh" "Fish" "Cancel")
      echo "To which shell do you want to add the CLI to the \$PATH variable?"
      select opt in "${options[@]}"; do
        case $opt in
        "Bash")
          echo "export PATH=\$PATH:\$HOME/.wp-takeoff" >>~/.bashrc
          added_to_path="bash"
          break
          ;;
        "Zsh")
          echo "export PATH=\$PATH:\$HOME/.wp-takeoff" >>~/.zshrc
          added_to_path="zsh"
          break
          ;;
        "Fish")
          echo "set -gx PATH \$PATH \$HOME/.wp-takeoff" >>~/.config/fish/config.fish
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
      echo "alias $alias='wp-takeoff'" >>~/$shell_file
      echo "The alias $alias is added to the $shell_file file, now restart your $shell_file shell to use the CLI."
    fi
  }

  # @function generate
  # @description Generate a new command collection
  function generate () {
    # Ask for the command name
    echo "What is the name of the command collection (i.e. core, release, deploy)?"
    read -r command_name
    # Check if there are any characters in the command name that are not allowed for a bash function name / file name
    if [[ "$command_name" =~ [^a-zA-Z0-9_-] ]]; then
      echo "The command name can only contain letters, numbers, underscores and dashes"
      exit 1
    fi
    # Copy example.sh.tpl to the command name
    cp "$current_dir/example.sh.tpl" "$current_dir/$command_name.sh"
    # Replace the command name in the file
    sed -i '' "s/global_command_name/$command_name/g" "$current_dir/$command_name.sh"
    # Ask for the first command name
    echo "What is the name of the first command (i.e. list, install, deploy)?"
    read -r first_command_name
    # Check if there are any characters in the command name that are not allowed for a bash function name / file name
    if [[ "$first_command_name" =~ [^a-zA-Z0-9_-] ]]; then
      echo "The command name can only contain letters, numbers, underscores and dashes"
      exit 1
    fi
    # Replace the command name in the file
    sed -i '' "s/first_command_name/$first_command_name/g" "$current_dir/$command_name.sh"
  }

  _get_package_version() {
    local package_version=$(cat "$current_dir/../package.json" | grep '"version":' | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
    echo "$package_version"
  }

  main "$@"
)
