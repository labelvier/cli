#!/bin/bash

storage() (

  # Local filename to echo the documentation.
  local filename="storage.sh"
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

  # @function summary <host> [max_depth]
  # @description Generate a storage summary for a given host.
  function summary() {
    # Choose a host to analyze
    if [[ $# -eq 0 ]]; then
      echo "Please provide a ssh host to analyze."
      exit 1
    else
      local SSH="$1"
      local MAX_DEPTH="${2:-0}"
      # Find the WordPress installation path
      local WP_PATH
      WP_PATH=$(ssh "$SSH" "find /home/customer/www/*/public_html -maxdepth 0 | grep -E 'public_html$' | head -n 1")
      if [[ -z "$WP_PATH" ]]; then
        echo -e "${__red}No WordPress installation found on the server. Exiting.${__reset}"
        exit 1
      fi
      # Upload the tree.sh.tpl file to the server
      scp "$current_dir/../templates/tree.sh.tpl" "$SSH:/home/customer/tree.sh"
      # Make the script executable
      ssh "$SSH" "chmod +x /home/customer/tree.sh"
      echo -e "The storage script has been uploaded to the server."
      echo -e ""
      # Run the script on the server with optional max_depth
      echo -e "${__bold}Analyzing 'wp-content' in WordPress path: $WP_PATH${__reset}"
      ssh "$SSH" "/bin/bash /home/customer/tree.sh $WP_PATH/wp-content $MAX_DEPTH"
    fi
  }

  main "$@"
)
