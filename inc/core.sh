#!/bin/bash

core() (

  # Local filename to echo the documentation.
  local filename="core.sh"

  # Runs the command.
  function main() {
    # try to run the subcommand passed as the second argument and that function exists
    if [[ -n "$1" ]] && type -t "$1" | grep -q 'function'; then
      "$1"
    else
      # if no subcommand is passed, run the documentation function
      _echo_documentation "inc/$filename"
    fi
  }

  # @function update
  # @description Check for updates for the CLI
  function update() {
    _check_and_ask_for_update
  }

  function _run_update_checker() {
    # Check if there are updates available from git and ask if we should pull them
    if [ -d ".git" ]; then
      # echo date minus 12 hours, don't use -d option because it's not available on mac
      last_update=$(date -u -r .git/FETCH_HEAD +%s)
      now=$(date -u +%s)
      diff=$(($now - $last_update))

      # Don't check if we checked in the last 12 hours
      if [ ! -f ".last_git_check" ] || [ $diff -gt 43200 ]; then
        _check_and_ask_for_update
        touch .last_git_check
      fi
    fi
  }

  function _check_and_ask_for_update() {
    # Check if there are updates available from git and ask if we should pull them
    if [ -d ".git" ]; then
      # Fetch the latest version
      git fetch
      # Check if remote is ahead of local branch
      UPSTREAM=${1:-'@{u}'}
      LOCAL=$(git rev-parse @)
      REMOTE=$(git rev-parse "$UPSTREAM")
      BASE=$(git merge-base @ "$UPSTREAM")
      if [ $LOCAL = $REMOTE ]; then
          echo "Up-to-date"
      elif [ $LOCAL = $BASE ]; then
          echo "Need to pull"
      elif [ $REMOTE = $BASE ]; then
          echo "Need to push"
      else
          echo "Diverged"
      fi

      # Check if there are updates available from git and ask if we should pull them
      if [ $LOCAL != $REMOTE ]; then
        echo "There is an update available for the CLI. Do you want to update? (y/n)"
        read -r answer
        if [ "$answer" == "y" ]; then
          git pull
          echo "Update complete. Please restart the CLI."
          exit 0
        fi
      fi
    fi
  }

  main "$@"
)
