#!/bin/bash

zed() (

  # Local filename to echo the documentation.
  local filename="zed.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")
  local templates_dir="$current_dir/../templates/zed"

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

  # @function autocomplete
  # @description Enable PHP autocompletion for Zed editor
  function autocomplete() {
    local provider=""

    # Check for flags
    for arg in "$@"; do
      case "$arg" in
        --wordpress) provider="wordpress" ;;
      esac
    done

    # If no provider flag, ask the user
    if [[ -z "$provider" ]]; then
      echo -e "${__bold}Which autocompletion do you want to enable?${__reset}"
      options=("WordPress" "Cancel")
      select opt in "${options[@]}"; do
        case $opt in
          "WordPress") provider="wordpress"; break ;;
          "Cancel") exit 0 ;;
          *) echo "Invalid option" ;;
        esac
      done
    fi

    case "$provider" in
      wordpress) _setup_wordpress_autocomplete ;;
      *) echo "Unknown provider: $provider"; exit 1 ;;
    esac
  }

  function _setup_wordpress_autocomplete() {
    echo -e "${__bold}Setting up WordPress autocompletion for Zed...${__reset}"
    echo

    # Check if we are in the root of a starter kit project #TODO, is this neccesary?
    #_check_starterkit_root

    # Check if composer is available
    _check_composer

    # Setup .zed/settings.json
    _setup_zed_settings

    # Setup composer.json
    _setup_composer_json

    # Update .gitignore
    _update_gitignore

    # Run composer install
    echo "Running composer install..."
    composer install --no-interaction
    if [[ $? -ne 0 ]]; then
      echo -e "${__red}Composer install failed. Please check the errors above.${__reset}"
      exit 1
    fi

    # create the global .zed autocomplete directory and symlink the local autocomplete directory to it, this way the autocompletion files are stored in the user's home directory and can be shared across projects
    mkdir -p ~/.zed/autocomplete/
    # if autocomplete already exists and is a symlink, remove it
    if [[ -L autocomplete ]]; then
      rm autocomplete
    fi
    ln -s ~/.zed/autocomplete autocomplete
    echo -e "${__green}✓ Symlinked autocomplete directory to ~/.zed/autocomplete${__reset}"

    echo
    echo -e "${__green}✓ WordPress autocompletion for Zed has been set up successfully!${__reset}"
    echo -e "  Restart Zed to activate intelephense with WordPress stubs."
    echo

    # Ask if the user wants to commit the changes
    _ask_to_commit "wordpress"
  }

  function _check_starterkit_root() {
    if [[ ! -f ".env" ]] && [[ ! -f "example.env" ]] && [[ ! -f "docker-compose.yml" ]]; then
      echo -e "${__red}Error: You don't seem to be in the root of a WP Takeoff project.${__reset}"
      echo "Please run this command from the root of your starter kit project."
      exit 1
    fi
  }

  function _check_composer() {
    if ! command -v composer &> /dev/null; then
      echo -e "${__red}Error: Composer is not installed or not in your PATH.${__reset}"
      echo "Please install Composer first: https://getcomposer.org/download/"
      exit 1
    fi
  }

  function _setup_zed_settings() {
    local target_dir=".zed"
    local target_file="$target_dir/settings.json"

    mkdir -p "$target_dir"

    if [[ -f "$target_file" ]]; then
      echo -e "${__blue}Found existing .zed/settings.json${__reset}"
      options=("Merge" "Overwrite" "Skip")
      select opt in "${options[@]}"; do
        case $opt in
          "Merge")
            _merge_zed_settings "$target_file"
            return
            ;;
          "Overwrite")
            cp "$templates_dir/settings.json" "$target_file"
            echo -e "${__green}✓${__reset} Overwritten $target_file"
            return
            ;;
          "Skip")
            echo "Skipping .zed/settings.json (kept existing file)"
            return
            ;;
          *) echo "Invalid option" ;;
        esac
      done
    else
      cp "$templates_dir/settings.json" "$target_file"
      echo -e "${__green}✓${__reset} Created $target_file"
    fi
  }

  function _ensure_jq() {
    if command -v jq &> /dev/null; then
      return 0
    fi

    echo -e "${__blue}jq is required for merging JSON files but is not installed.${__reset}"
    echo "Do you want to install it via Homebrew? (y/n)"
    read -r answer
    if [[ "$answer" == "y" ]]; then
      if ! command -v brew &> /dev/null; then
        echo -e "${__red}Homebrew is not installed. Please install jq manually.${__reset}"
        return 1
      fi
      brew install jq
      if [[ $? -ne 0 ]]; then
        echo -e "${__red}Failed to install jq.${__reset}"
        return 1
      fi
      echo -e "${__green}✓${__reset} jq installed"
      return 0
    fi
    return 1
  }

  function _merge_zed_settings() {
    local target_file="$1"

    if ! _ensure_jq; then
      echo "Falling back to overwrite."
      cp "$templates_dir/settings.json" "$target_file"
      echo -e "${__green}✓${__reset} Overwritten $target_file"
      return
    fi

    # Deep merge: template values override existing on conflict
    local merged
    merged=$(jq -s '.[0] * .[1]' "$target_file" "$templates_dir/settings.json")
    echo "$merged" > "$target_file"
    echo -e "${__green}✓${__reset} Merged $target_file"
  }

  function _setup_composer_json() {
    local target_file="composer.json"

    if [[ -f "$target_file" ]]; then
      echo -e "${__blue}Found existing composer.json${__reset}"
      options=("Merge" "Overwrite" "Skip")
      select opt in "${options[@]}"; do
        case $opt in
          "Merge")
            _merge_composer_json
            return
            ;;
          "Overwrite")
            cp "$templates_dir/composer.json" "$target_file"
            echo -e "${__green}✓${__reset} Overwritten $target_file"
            return
            ;;
          "Skip")
            echo "Skipping composer.json (kept existing file)"
            return
            ;;
          *) echo "Invalid option" ;;
        esac
      done
    else
      cp "$templates_dir/composer.json" "$target_file"
      echo -e "${__green}✓${__reset} Created $target_file"
    fi
  }

  function _merge_composer_json() {
    # Use composer require to merge packages into existing composer.json
    echo "Merging packages into existing composer.json..."
    composer require --dev --no-install --no-interaction \
      "johnpbloch/wordpress-core-installer:^2.0" \
      "johnpbloch/wordpress:^6.9" \
      "php-stubs/wp-cli-stubs:^2.12"

    # Merge extra and scripts config using jq
    if _ensure_jq; then
      local tmp_file
      tmp_file=$(mktemp)
      jq '.config["allow-plugins"]["johnpbloch/wordpress-core-installer"] = true |
          .extra["wordpress-install-dir"] = "autocomplete/wordpress" |
          .scripts["post-install-cmd"] = ((.scripts["post-install-cmd"] // []) + ["rm -rf autocomplete/wordpress/wp-content", "rm -rf vendor/php-stubs/wordpress-stubs"] | unique)' \
          composer.json > "$tmp_file" && mv "$tmp_file" composer.json
    else
      echo -e "${__blue}Note: config/scripts sections could not be merged without jq.${__reset}"
    fi

    echo -e "${__green}✓${__reset} Merged composer.json"
  }

  function _update_gitignore() {
    local target_file=".gitignore"
    local additions_file="$templates_dir/gitignore-additions.txt"

    if [[ ! -f "$target_file" ]]; then
      cp "$additions_file" "$target_file"
      echo -e "${__green}✓${__reset} Created $target_file"
      return
    fi

    # Check if the additions are already present
    if grep -q "# Autocompletion files (managed by wp-takeoff zed)" "$target_file"; then
      echo -e "${__green}✓${__reset} .gitignore already contains autocomplete entries"
      return
    fi

    # Append additions to existing .gitignore
    echo "" >> "$target_file"
    cat "$additions_file" >> "$target_file"
    echo -e "${__green}✓${__reset} Updated $target_file with autocomplete entries"
  }

  function _ask_to_commit() {
    local provider="$1"

    echo "Do you want to commit these changes? (y/n)"
    read -r answer
    if [[ "$answer" != "y" ]]; then
      return
    fi

    git add .zed/settings.json composer.json composer.lock .gitignore
    git commit -m "build: add Zed autocompletion for $provider via wp-takeoff"
    echo -e "${__green}✓${__reset} Changes committed"
  }

  main "$@"
)
