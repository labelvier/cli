#!/bin/bash

siteground() (

  # The SiteGround automation is a Node CLI in node/siteground (Playwright only for the login).
  # Override the code location with SG_CLI_DIR, e.g. a checkout you are working on.
  local sg_dir="${SG_CLI_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../node/siteground" && pwd)}"

  # Session and generated credentials, outside the code so `core update` never touches them.
  local state_dir="${SG_STATE_DIR:-$HOME/.config/labelvier/siteground}"

  # Runs the command. Everything is forwarded to the Node CLI, which has its own subcommands
  # and help (`labelvier siteground` without arguments prints it).
  function main() {
    if [ ! -f "$sg_dir/package.json" ]; then
      echo -e "${__red}✗${__reset} SiteGround CLI not found in ${__bold}$sg_dir${__reset}. Check SG_CLI_DIR."
      exit 1
    fi
    _require_npm || exit 1
    if ! node -e 'process.exit(+process.versions.node.split(".")[0] < 20 ? 1 : 0)'; then
      echo -e "${__red}✗${__reset} SiteGround CLI needs node 20 or newer, found $(node --version). Run: nvm install --lts"
      exit 1
    fi

    _install_dependencies || exit 1
    _migrate_state
    if [ "$1" == "login" ]; then
      _install_chromium || exit 1
    fi

    SG_STATE_DIR="$state_dir" node "$sg_dir/src/cli.js" "$@"
  }

  # Installs node_modules on first use and again when package-lock.json changed (after `core update`).
  function _install_dependencies() {
    if [ -f "$sg_dir/node_modules/.package-lock.json" ] && [ ! "$sg_dir/package-lock.json" -nt "$sg_dir/node_modules/.package-lock.json" ]; then
      return 0
    fi
    echo "Installing SiteGround CLI dependencies…"
    npm --prefix "$sg_dir" ci --silent --no-audit --no-fund >/dev/null || {
      echo -e "${__red}✗${__reset} npm ci failed in ${__bold}$sg_dir${__reset}."
      return 1
    }
  }

  # Playwright's Chromium is only needed for the browser login; the install is a no-op once present.
  function _install_chromium() {
    if [ ! -d "$sg_dir/node_modules/playwright" ]; then
      echo -e "${__red}✗${__reset} Playwright is not installed in ${__bold}$sg_dir${__reset}, the login needs it."
      return 1
    fi
    (cd "$sg_dir" && npx --no-install playwright install chromium) || {
      echo -e "${__red}✗${__reset} Installing Chromium for Playwright failed."
      return 1
    }
  }

  # One-time copy of the session and credentials from the old standalone checkout (~/Sites/siteground).
  function _migrate_state() {
    local old_dir="$HOME/Sites/siteground"
    [ -d "$state_dir" ] && return 0
    [ -f "$old_dir/.session.json" ] || [ -d "$old_dir/.credentials" ] || return 0

    mkdir -p "$state_dir" && chmod 700 "$state_dir"
    [ -f "$old_dir/.session.json" ] && cp -p "$old_dir/.session.json" "$state_dir/"
    [ -d "$old_dir/.credentials" ] && cp -Rp "$old_dir/.credentials" "$state_dir/"
    echo -e "${__green}✓${__reset} Copied session and credentials from ${__bold}$old_dir${__reset} to ${__bold}$state_dir${__reset}."
  }

  main "$@"
)
