#!/bin/bash
#
# Helper script to run all kind of scripts and commands for the Label Vier Starter Kit (WP Takeoff)
# Copyright 2022 labelvier

main_function="wp-pilot"

# load all functions from the includes directory
__dir="$(dirname "$0")"
for file in "$__dir"/inc/*.sh; do
  source "$file"
done

function main() {
  # check if the script has any arguments. Check if the first argument name matches an existing function. If not, show all possible commands
  if [ $# -eq 0 ] || ! declare -f "$1" > /dev/null; then
    echo "Usage: $main_function <command> [arguments]"
    echo
    echo "Possible commands:"
    declare -F | awk '{print $3}' | grep -v main
    exit 1
  else
    # run the function with the same name as the first argument
    "$@"
  fi
}

main "$@"
