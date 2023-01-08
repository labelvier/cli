#!/bin/bash
#
# This script is used to echo hello world

# Echo hello with possible arguments
function hello() {
  # Check if we have an second argument
  if [ $# -eq 0 ]; then
    echo "Hello world!"
  else
    echo "Hello $1!"
  fi
}
