#!/bin/bash

# Opens the CHANGELOG.md in a pager, like `man`. No subcommands: a bare
# `changelog` shows it straight away, so it deliberately skips `_dispatch`.
changelog() (

  local current_dir=$(dirname "${BASH_SOURCE[0]}")
  local changelog_file="$current_dir/../CHANGELOG.md"

  if [ "${1:-}" = "--help" ]; then
    echo "changelog - Reads the CHANGELOG.md in a pager (q quits, \$PAGER is honoured)"
    return 0
  fi

  if [ ! -f "$changelog_file" ]; then
    echo -e "${__red}✗${__reset} No CHANGELOG.md found next to the CLI." >&2
    return 1
  fi

  # Not on a terminal (piped/redirected): plain text.
  if [ ! -t 1 ]; then
    cat "$changelog_file"
  elif [ -n "${PAGER:-}" ]; then
    $PAGER < "$changelog_file"
  elif command -v less > /dev/null 2>&1; then
    less -FRX < "$changelog_file"
  else
    cat "$changelog_file"
  fi
)
