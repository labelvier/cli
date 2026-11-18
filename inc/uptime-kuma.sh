#!/bin/bash

uptime-kuma() (

  # The Uptime Kuma tooling is a Node CLI in node/uptime-kuma (Socket.IO API of status.labelvier.nl).
  # Override the code location with KUMA_CLI_DIR, e.g. a checkout you are working on.
  local kuma_dir="${KUMA_CLI_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../node/uptime-kuma" && pwd)}"

  # Login token, outside the code so `core update` never touches it.
  local state_dir="${KUMA_STATE_DIR:-$HOME/.config/labelvier/uptime-kuma}"

  # Runs the command. Everything is forwarded to the Node CLI, which has its own subcommands
  # and help (`labelvier uptime-kuma` without arguments prints it).
  function main() {
    if [ ! -f "$kuma_dir/package.json" ]; then
      echo -e "${__red}✗${__reset} Uptime Kuma CLI not found in ${__bold}$kuma_dir${__reset}. Check KUMA_CLI_DIR."
      exit 1
    fi
    _require_npm || exit 1
    if ! node -e 'process.exit(+process.versions.node.split(".")[0] < 20 ? 1 : 0)'; then
      echo -e "${__red}✗${__reset} Uptime Kuma CLI needs node 20 or newer, found $(node --version). Run: nvm install --lts"
      exit 1
    fi

    _install_dependencies || exit 1

    KUMA_STATE_DIR="$state_dir" node "$kuma_dir/src/cli.js" "$@"
  }

  # Installs node_modules on first use and again when package-lock.json changed (after `core update`).
  function _install_dependencies() {
    if [ -f "$kuma_dir/node_modules/.package-lock.json" ] && [ ! "$kuma_dir/package-lock.json" -nt "$kuma_dir/node_modules/.package-lock.json" ]; then
      return 0
    fi
    echo "Installing Uptime Kuma CLI dependencies…"
    npm --prefix "$kuma_dir" ci --silent --no-audit --no-fund >/dev/null || {
      echo -e "${__red}✗${__reset} npm ci failed in ${__bold}$kuma_dir${__reset}."
      return 1
    }
  }

  main "$@"
)
