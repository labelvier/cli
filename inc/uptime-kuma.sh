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
    _prepare_node_cli "Uptime Kuma" "$kuma_dir" KUMA_CLI_DIR || exit 1

    KUMA_STATE_DIR="$state_dir" node "$kuma_dir/src/cli.js" "$@"
  }

  main "$@"
)
