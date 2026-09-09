#!/bin/bash

global_command_name() (

  # Local filename to echo the documentation.
  local filename="global_command_name.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")

  # Runs the command.
  function main() {
    _dispatch "$filename" "$@"
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
