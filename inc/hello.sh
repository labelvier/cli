#!/bin/bash

hello() (

  # Local filename to echo the documentation.
  local filename="hello.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")

  # Runs the command.
  function main() {
    _dispatch "$filename" "$@"
  }

  # @function world
  # @description Echo hello with possible arguments
  function world() {
    # Check if we have an second argument
    if [ $# -eq 0 ]; then
      echo "Hello world!"
    else
      echo "Hello $1!"
    fi
  }

  main "$@"
)
