#!/bin/bash

function _needs_active_wptakeoff_project() {
  # check if we have an .env file
  if [ -f .env ]; then
    # get the DEV_THEME_PATH from the .env file
      local dev_theme_path=$(grep DEV_THEME_PATH .env | cut -d '=' -f2)
      # exit if the DEV_THEME_PATH is not set
      if [ -z "$dev_theme_path" ]; then
        echo "DEV_THEME_PATH is not set in the .env file"
        exit 1
      fi
  fi
  # Check if we are in the right directory
  style_path="./$dev_theme_path/src/scss/style.scss"
  if [ ! -f $style_path ]; then
    echo "You are not in the right directory. Please run this command from the root of your theme."
    echo $style_path
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
  echo -e "${__bold}Available functions:${__reset}"
  # loop through all functions
  while read -r line; do
    # get the name of the function
    local function_name=$(echo "$line" | cut -d' ' -f3-)
    # get the description of the function (the next line)
    read -r line
    local function_description=$(echo -e "$line" | cut -d' ' -f3-)
    # print the name and description
    echo -e "  ${__bold}$function_name${__reset} - $function_description"
    read -r line
  done <<<"$functions"
}

function _echo_function_description() {
  # first argument is the file to search, second is the subcommand name
  local current_dir=$(dirname "${BASH_SOURCE[0]}")
  local contents=$(cat "$current_dir/$1")
  local target="$2"
  local functions=$(echo "$contents" | grep -E "^\s*# @function" -A 1)
  local function_name function_description first_word
  while read -r line; do
    function_name=$(echo "$line" | cut -d' ' -f3-)
    read -r line
    function_description=$(echo -e "$line" | cut -d' ' -f3-)
    # the @function line may have usage args after the name (e.g. "start <version>")
    first_word=${function_name%% *}
    if [[ "$first_word" == "$target" ]]; then
      echo -e "${__bold}$function_name${__reset} - $function_description"
      return 0
    fi
    read -r line
  done <<<"$functions"

  # no documented description found, still print something rather than nothing
  echo -e "${__bold}$target${__reset}"
  return 1
}

# Shared main() dispatcher. Given the command file's own filename and "$@":
# runs the matching subcommand, but if --help is the argument right after the
# subcommand name, prints its one-line @description instead of running it.
# Falls back to the file's full documentation when no subcommand is given.
function _dispatch() {
  local filename="$1"
  shift
  local subcommand="$1"

  # the `-*` guard matters: bash's `type -t` chokes on an arg that looks like
  # its own flag (e.g. "type -t --help" errors instead of just failing), so a
  # bare `<cmd> --help` must be caught before it ever reaches `type`.
  if [[ -z "$subcommand" ]] || [[ "$subcommand" == -* ]] || ! type -t "$subcommand" | grep -q 'function'; then
    _echo_documentation "$filename"
    return
  fi
  shift

  if [[ "$1" == "--help" ]]; then
    _echo_function_description "$filename" "$subcommand"
    return
  fi

  "$subcommand" "$@"
}

function _flag_is_present() {
  # first argument is the flag we are looking for
  flag_to_check="$1"
  shift
  args=("$@")

  # loop through all arguments
  for arg in "${args[@]}"; do
    # check if the argument is the flag we are looking for
    if [ "$arg" == "--$flag_to_check" ]; then
      # if it is, return 0 (true)
      return 0
    fi
  done
  # if we get here, the flag was not found
  return 1
}

function _is_semantic_version() {
  # first argument is the version we are checking
  local version="$1"
  # get the first part till an optional space or dash
  local first_part=$(echo "$version" | cut -d' ' -f1 | cut -d'-' -f1)
  # check if the version is a semantic version
  if [[ $first_part =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # if it is, return 0 (true)
    return 0
  fi
  # if we get here, the version is not a semantic version
  return 1
}