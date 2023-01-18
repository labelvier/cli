#!/bin/bash

function _needs_active_wptakeoff_project() {
  # Check if we are in the right directory
  if [ ! -f "./wp-content/themes/labelvier/src/main.scss" ]; then
    echo "You are not in the right directory. Please run this command from the root of your theme."
    exit 1
  fi
}

function _echo_local_functions() {
  # first arguments is the name of the file
  local contents=$(cat $1)
  # get all lines starting with "function" and ending with "{" and save them in an array
  local functions=($(echo "$contents" | grep -oE 'function [^(]*'))
  # use sed to remove the function keyword and the space
  local functions=($(echo "${functions[@]}" | sed -e 's/function //g'))
  echo "Available functions:"
  for i in "${!functions[@]}"; do
    echo "$i) ${functions[$i]}"
  done
}
