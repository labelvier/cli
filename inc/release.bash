#!/bin/bash

release() (

  # Local filename to echo the documentation.
  local filename="release.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")

  # Runs the command.
  function main() {
    echo BASH_SOURCE[0];
    # try to run the subcommand passed as the second argument and that function exists
    if [[ -n "$1" ]] && type -t "$1" | grep -q 'function'; then
      "$1"
    else
      # if no subcommand is passed, run the documentation function
      _echo_documentation "$filename"
    fi
  }

  # @function example
  # @description description
  function example() {
    # do something
  }

  main "$@"
)
