#!/bin/bash

ssh() (

  # Local filename to echo the documentation.
  local filename="ssh.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")

  # Path to the SSH config file.
  local ssh_config="${HOME}/.ssh/config"

  # Runs the command.
  function main() {
    # If $1 is a known subcommand function, dispatch to it; if $1 looks like an
    # ssh flag or host (anything not a declared function), forward to the real
    # binary so that callers like migrate.sh can still use `ssh -G`, `ssh -p`, etc.
    if [[ -n "$1" ]] && declare -f -- "$1" > /dev/null 2>&1; then
      if [[ "$2" == "--help" ]]; then
        _echo_function_description "$filename" "$1"
        return
      fi
      "$1" "${@:2}"
    elif [[ -n "$1" ]]; then
      command ssh "$@"
    else
      _echo_documentation "$filename"
    fi
  }

  # Prompt for a value, showing an optional default. Echoes the result.
  function _ask() {
    local prompt="$1"
    local default="$2"
    local answer

    if [ -n "$default" ]; then
      read -r -p "$prompt [$default]: " answer
      echo "${answer:-$default}"
    else
      read -r -p "$prompt: " answer
      echo "$answer"
    fi
  }

  # Make sure ~/.ssh and the config file exist with the correct permissions.
  function _ensure_config() {
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    touch "$ssh_config"
    chmod 600 "$ssh_config"
  }

  # @function alias
  # @description Add an SSH host alias to ~/.ssh/config (prompts when arguments are missing)
  function alias() {
    local name="$1"
    local host_part="$2"
    local user_part="$3"
    local port="$4"
    local identity="$5"

    # Prompt for anything that was not passed as an argument.
    [ -z "$name" ]      && name=$(_ask "Alias name")
    [ -z "$host_part" ] && host_part=$(_ask "HostName (host or IP)")
    [ -z "$user_part" ] && user_part=$(_ask "User (leave empty for none)")
    [ -z "$port" ]      && port=$(_ask "Port" "18765")
    [ -z "$identity" ]  && identity=$(_ask "IdentityFile (leave empty for none)")

    # Required values.
    if [ -z "$name" ] || [ -z "$host_part" ]; then
      echo -e "${__red}Alias name and HostName are required.${__reset}"
      return 1
    fi

    _ensure_config

    # Refuse to add a duplicate alias.
    if grep -qiE "^[[:space:]]*Host[[:space:]]+${name}([[:space:]]|$)" "$ssh_config"; then
      echo -e "${__red}Alias '${name}' already exists in ${ssh_config}.${__reset}"
      return 1
    fi

    # Append the Host block.
    {
      echo ""
      echo "Host ${name}"
      echo "    HostName ${host_part}"
      [ -n "$user_part" ] && echo "    User ${user_part}"
      [ -n "$port" ] && [ "$port" != "22" ] && echo "    Port ${port}"
      [ -n "$identity" ] && echo "    IdentityFile ${identity}"
    } >> "$ssh_config"

    echo -e "${__green}Added alias '${name}' -> ${user_part:+${user_part}@}${host_part}.${__reset}"
    echo -e "Connect with: ${__blue}ssh ${name}${__reset}"
  }

  # @function list
  # @description List all SSH host aliases from ~/.ssh/config
  function list() {
    _ensure_config
    echo -e "${__bold}SSH aliases in ${ssh_config}:${__reset}"
    grep -iE "^[[:space:]]*Host[[:space:]]+" "$ssh_config" | awk '{$1=""; print "  " $0}' | grep -v '\*'
  }

  # @function search
  # @description Search aliases by pattern and print the matching Host block(s) (prompts when no pattern is given)
  function search() {
    local pattern="$1"
    [ -z "$pattern" ] && pattern=$(_ask "Search pattern")

    if [ -z "$pattern" ]; then
      echo -e "${__red}Search pattern is required.${__reset}"
      return 1
    fi

    _ensure_config

    # Print each matching Host block: from the matching line until the next blank line.
    local result
    result=$(awk "/$pattern/,/^\$/" "$ssh_config")

    if [ -z "$result" ]; then
      echo -e "${__red}No match for '${pattern}'.${__reset}"
      return 1
    fi
    echo "$result"
  }

  # @function remove
  # @description Remove an SSH host alias from ~/.ssh/config (prompts when no name is given)
  function remove() {
    local name="$1"
    [ -z "$name" ] && name=$(_ask "Alias name to remove")

    if [ -z "$name" ]; then
      echo -e "${__red}Alias name is required.${__reset}"
      return 1
    fi

    _ensure_config

    if ! grep -qiE "^[[:space:]]*Host[[:space:]]+${name}([[:space:]]|$)" "$ssh_config"; then
      echo -e "${__red}Alias '${name}' not found in ${ssh_config}.${__reset}"
      return 1
    fi

    # Delete the Host block: from the matching Host line until the next Host line or EOF.
    awk -v alias="$name" '
      BEGIN { skip = 0 }
      /^[[:space:]]*Host[[:space:]]+/ {
        if ($2 == alias) { skip = 1; next } else { skip = 0 }
      }
      skip == 0 { print }
    ' "$ssh_config" > "${ssh_config}.tmp" && mv "${ssh_config}.tmp" "$ssh_config"
    chmod 600 "$ssh_config"

    echo -e "${__green}Removed alias '${name}'.${__reset}"
  }

  main "$@"
)
