#!/bin/bash

function _needs_active_wptakeoff_project() {
  # Check if we are in the right directory
  if [ ! -f "./wp-content/themes/labelvier/src/main.scss" ]; then
    echo "You are not in the right directory. Please run this command from the root of your theme."
    exit 1
  fi
}

function _echo_documentation() {
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")
  # first arguments is the name of the file
  local contents=$(cat "$current_dir/$1")
  # get all lines starting with any whitespace, then # @function and the next line
  local functions=$(echo "$contents" | grep -E "^\s*# @function" -A 1)
  echo "Available functions:"
  # loop through all functions
  while read -r line; do
    # get the name of the function
    local function_name=$(echo "$line" | cut -d' ' -f3-)
    # get the description of the function (the next line)
    read -r line
    local function_description=$(echo "$line" | cut -d' ' -f3-)
    # print the name and description
    echo "  $function_name - $function_description"
    read -r line
  done <<< "$functions"
}
