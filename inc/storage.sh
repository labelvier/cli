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

  # @function convert-to-webp <host> [options]
  # @description Convert images to WebP format in the WordPress uploads folder.
  # @option --dry-run              Test run without actual conversion
  # @option --quality <0-100>      WebP quality (default: 85)
  # @option --with-backup          Create backup of original files (default: no backup)
  # @option --parallel-jobs <num>  Number of parallel conversions (default: 4)
  # @option --path <path>          Custom path relative to public_html (default: wp-content/uploads)
  # @option --yes                  Skip confirmation prompt (auto-proceed)
  # @option --background           Run in background mode (detaches and survives SSH disconnect)
  function convert-to-webp() {
    # Default options
    local DRY_RUN="false"
    local QUALITY="85"
    local CREATE_BACKUP="false"
    local PARALLEL_JOBS="4"
    local CUSTOM_PATH=""
    local AUTO_YES="false"
    local BACKGROUND_MODE="false"

    # Choose a host to convert images on
    if [[ $# -eq 0 ]]; then
      echo "Please provide a ssh host to convert images on."
      echo ""
      echo "Usage: ./wp-takeoff storage convert-to-webp <host> [options]"
      echo ""
      echo "Options:"
      echo "  --dry-run              Test run without actual conversion"
      echo "  --quality <0-100>      WebP quality (default: 85)"
      echo "  --with-backup          Create backup of original files (default: no backup)"
      echo "  --parallel-jobs <num>  Number of parallel conversions (default: 4)"
      echo "  --path <path>          Custom path relative to public_html (default: wp-content/uploads)"
      echo "  --yes                  Skip confirmation prompt (auto-proceed)"
      echo "  --background           Run in background mode (detaches and survives SSH disconnect)"
      echo ""
      echo "Examples:"
      echo "  ./wp-takeoff storage convert-to-webp my-host --dry-run"
      echo "  ./wp-takeoff storage convert-to-webp my-host --quality 90 --parallel-jobs 8"
      echo "  ./wp-takeoff storage convert-to-webp my-host --with-backup --yes"
      echo "  ./wp-takeoff storage convert-to-webp my-host --path wp-content/uploads/2024"
      echo "  ./wp-takeoff storage convert-to-webp my-host --background --yes"
      exit 1
    fi

    local SSH="$1"
    shift

    # Parse options
    while [[ $# -gt 0 ]]; do
      case $1 in
        --dry-run)
          DRY_RUN="true"
          shift
          ;;
        --quality)
          QUALITY="$2"
          shift 2
          ;;
        --with-backup)
          CREATE_BACKUP="true"
          shift
          ;;
        --parallel-jobs)
          PARALLEL_JOBS="$2"
          shift 2
          ;;
        --path)
          CUSTOM_PATH="$2"
          shift 2
          ;;
        --yes)
          AUTO_YES="true"
          shift
          ;;
        --background)
          BACKGROUND_MODE="true"
          shift
          ;;
        *)
          echo -e "${__red}Unknown option: $1${__reset}"
          exit 1
          ;;
      esac
    done

    # Find the WordPress installation path
    local WP_PATH
    WP_PATH=$(ssh "$SSH" "find /home/customer/www/*/public_html -maxdepth 0 | grep -E 'public_html$' | head -n 1")
    if [[ -z "$WP_PATH" ]]; then
      echo -e "${__red}No WordPress installation found on the server. Exiting.${__reset}"
      exit 1
    fi

    # Determine target path
    local TARGET_PATH
    if [[ -n "$CUSTOM_PATH" ]]; then
      TARGET_PATH="$WP_PATH/$CUSTOM_PATH"
    else
      TARGET_PATH="$WP_PATH/wp-content/uploads"
    fi

    echo -e "${__bold}WordPress path: $WP_PATH${__reset}"
    echo -e "${__bold}Target path: $TARGET_PATH${__reset}"
    echo -e ""
    echo -e "${__bold}Configuration:${__reset}"
    echo -e "  Quality:       $QUALITY"
    echo -e "  Dry run:       $DRY_RUN"
    echo -e "  Create backup: $CREATE_BACKUP"
    echo -e "  Parallel jobs: $PARALLEL_JOBS"
    echo -e "  Auto proceed:  $AUTO_YES"
    echo -e "  Background:    $BACKGROUND_MODE"
    echo -e ""

    # Upload the convert-to-webp.sh.tpl file to the server
    echo -e "Uploading WebP conversion script to server..."
    scp "$current_dir/../templates/convert-to-webp.sh.tpl" "$SSH:/home/customer/convert-to-webp.sh"

    # Make the script executable
    ssh "$SSH" "chmod +x /home/customer/convert-to-webp.sh"

    echo -e "${__green}The WebP conversion script has been uploaded to the server.${__reset}"
    echo -e ""

    # Build the command with environment variables
    local REMOTE_CMD="QUALITY=$QUALITY DRY_RUN=$DRY_RUN CREATE_BACKUP=$CREATE_BACKUP PARALLEL_JOBS=$PARALLEL_JOBS AUTO_YES=$AUTO_YES BACKGROUND_MODE=$BACKGROUND_MODE /bin/bash /home/customer/convert-to-webp.sh $TARGET_PATH"

    # Run the script on the server with the configured options
    echo -e "${__bold}Starting WebP conversion...${__reset}"
    echo -e ""

    if [[ "$BACKGROUND_MODE" == "true" ]]; then
      echo -e "${__yellow}Script will run in background mode on the server.${__reset}"
      echo -e "${__yellow}You can safely close this SSH connection.${__reset}"
      echo -e ""
      echo -e "To monitor progress on the server, connect via SSH and run:"
      echo -e "  tail -f ~/webp_conversion_background_*.log"
      echo -e ""
      echo -e "To check if the process is still running:"
      echo -e "  ps aux | grep convert-to-webp"
      echo -e ""
    fi

    ssh "$SSH" "$REMOTE_CMD"

    echo -e ""
    if [[ "$DRY_RUN" == "true" ]]; then
      echo -e "${__yellow}Dry run completed - no files were modified.${__reset}"
    else
      echo -e "${__green}WebP conversion completed.${__reset}"
    fi
    echo -e ""
    echo -e "To remove the script from the server, run:"
    echo -e "  ssh $SSH 'rm /home/customer/convert-to-webp.sh'"
  }

  main "$@"
)
