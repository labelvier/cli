#!/bin/bash

siteground() (

  # The SiteGround automation lives in its own repo (labelvier/siteground).
  # Override the checkout location with SG_CLI_DIR.
  local sg_dir="${SG_CLI_DIR:-$HOME/Sites/siteground}"

  # Runs the command. Everything is forwarded to `npm run sg` in that repo, which has its own
  # subcommands and help (`labelvier sg` without arguments prints it).
  function main() {
    if [ ! -f "$sg_dir/package.json" ]; then
      echo -e "${__red}✗${__reset} SiteGround CLI not found in ${__bold}$sg_dir${__reset}. Clone labelvier/siteground there or set SG_CLI_DIR."
      exit 1
    fi
    _require_npm || exit 1
    npm --prefix "$sg_dir" run --silent sg -- "$@"
  }

  main "$@"
)
