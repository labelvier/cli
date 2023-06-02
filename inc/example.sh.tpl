#!/bin/bash

global_command_name() (

  # Local filename to echo the documentation.
  local filename="global_command_name.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")

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

  # @function first_command_name
  # @description Description
  function first_command_name() {
    # Check if we have a second argument
    if [ $# -eq 0 ]; then
      echo "Hello world!"
    else
      echo "Hello $1!"
    fi
  }

  main "$@"
)
