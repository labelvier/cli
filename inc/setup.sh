#!/bin/bash

setup() (

  # Local filename to echo the documentation.
  local filename="setup.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")

  # Runs the command. Unlike the other commands, a bare `labelvier setup`
  # runs the whole walkthrough instead of printing the docs, because that is
  # what a new colleague types. Subcommands and --help still go through
  # _dispatch.
  function main() {
    if [ $# -eq 0 ]; then
      all
    else
      _dispatch "$filename" "$@"
    fi
  }

  # @function all
  # @description Walk through the whole setup: required tools, notifications, then the AI check and install. Runs when no subcommand is given.
  function all() {
    echo -e "${__bold}Label Vier CLI setup${__reset}"
    echo "Checks the tools the CLI needs and offers to install what is missing. Nothing is installed without your yes."
    echo

    echo -e "${__bold}Tools${__reset}"
    tools

    echo
    echo -e "${__bold}Notifications${__reset}"
    core notifications

    echo
    echo -e "${__bold}AI${__reset}"
    if _confirm_remembered setup_ai "Check and install the AI setup (Claude Code config, skills, Basecamp, rtk) now?"; then
      ai update
    else
      echo "  Ok, run it later with: labelvier ai update"
    fi
  }

  # @function tools
  # @description Check the required tools (Homebrew, git, jq, nvm, Node, Docker, Composer) and offer to install missing ones.
  function tools() {
    local missing=""

    if _require_brew; then
      echo -e "${__green}✓${__reset} brew"
    else
      missing="$missing brew"
    fi

    _require_git || missing="$missing git"
    _brew_tool jq "edits Claude Code settings and Zed config" jq || missing="$missing jq"
    _require_nvm || missing="$missing nvm"
    _require_node || missing="$missing node"
    _require_docker || missing="$missing docker"
    _brew_tool composer "needed by the zed commands" composer || missing="$missing composer"

    echo
    if [ -z "$missing" ]; then
      echo -e "${__green}All required tools are installed.${__reset}"
    else
      echo -e "${__red}Still missing:${__reset}$missing. Run 'labelvier setup tools' again after fixing them."
      return 1
    fi
  }

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Checks for a command and offers `brew install <args>` when it is missing.
  # $1 = command, $2 = what the CLI uses it for, rest = brew install args.
  function _brew_tool() {
    local cmd="$1" purpose="$2"
    shift 2

    if type -P "$cmd" >/dev/null 2>&1; then
      echo -e "${__green}✓${__reset} $cmd"
      return 0
    fi

    echo -e "${__red}✗${__reset} $cmd is not installed ($purpose)."
    if ! type -P brew >/dev/null 2>&1; then
      echo "  Install Homebrew first, then run: brew install $*"
      return 1
    fi
    if ! _confirm "  Install it now with 'brew install $*'?"; then
      echo "  Skipped."
      return 1
    fi
    brew install "$@"

    if type -P "$cmd" >/dev/null 2>&1; then
      echo -e "${__green}✓${__reset} $cmd installed"
    else
      echo -e "${__red}✗${__reset} $cmd is still not on your PATH. Open a new shell and run 'labelvier setup tools' again."
      return 1
    fi
  }

  # On macOS /usr/bin/git is only a stub until the Xcode Command Line Tools
  # are installed, so `type -P git` alone says nothing there.
  function _require_git() {
    if [ "$(uname)" = "Darwin" ] && ! xcode-select -p >/dev/null 2>&1; then
      echo -e "${__red}✗${__reset} git needs the Xcode Command Line Tools, which are not installed."
      if _confirm "  Open the installer for the Command Line Tools now?"; then
        xcode-select --install
        echo "  Finish the installer, then run 'labelvier setup tools' again."
      fi
      return 1
    fi
    _brew_tool git "used for releases, deploys and updating this CLI" git
  }

  # Any docker CLI is fine (Docker Desktop, OrbStack, ...). Docker Desktop
  # only links its CLI after the app has been opened once.
  function _require_docker() {
    if type -P docker >/dev/null 2>&1; then
      echo -e "${__green}✓${__reset} docker"
      return 0
    fi
    if [ -d "/Applications/Docker.app" ]; then
      echo -e "${__red}✗${__reset} Docker Desktop is installed, but the docker command is not on your PATH yet."
      echo "  Open Docker Desktop once (open -a Docker), then run 'labelvier setup tools' again."
      return 1
    fi
    if [ "$(uname)" != "Darwin" ]; then
      echo -e "${__red}✗${__reset} docker is not installed. Install it yourself: ${__blue}https://docs.docker.com/engine/install/${__reset}"
      return 1
    fi
    if ! _brew_tool docker "the WordPress projects run in Docker" --cask docker-desktop; then
      [ -d "/Applications/Docker.app" ] && echo "  Open Docker Desktop once (open -a Docker), so it links the docker command."
      return 1
    fi
  }

  main "$@"
)
