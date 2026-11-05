#!/bin/bash

changelog() (

  # Local filename to echo the documentation.
  local filename="changelog.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")
  local changelog_file="$current_dir/../CHANGELOG.md"

  # Runs the command.
  function main() {
    _dispatch "$filename" "$@"
  }

  # Fails with a message when the CHANGELOG.md is missing.
  function _require_changelog() {
    if [ ! -f "$changelog_file" ]; then
      echo -e "${__red}✗${__reset} No CHANGELOG.md found next to the CLI." >&2
      return 1
    fi
  }

  # Pipes stdin through a pager (like `man`) on a terminal; plain cat when
  # piped/redirected or when no pager exists. Honours $PAGER, default less.
  function _page() {
    if [ ! -t 1 ]; then
      cat
      return
    fi
    if [ -n "${PAGER:-}" ]; then
      $PAGER
    elif command -v less > /dev/null 2>&1; then
      less -FRX
    else
      cat
    fi
  }

  # @function latest
  # @description Reads the newest released version from the CHANGELOG.md in a pager
  function latest() {
    _require_changelog || return 1
    awk '
      /^## \[/ {
        if (found) exit
        if (tolower($0) !~ /^## \[unreleased\]/) found = 1
      }
      found { print }
    ' "$changelog_file" | _page
  }

  # @function show
  # @description Reads the changelog entry of one version in a pager, e.g. show 1.3.0
  function show() {
    _require_changelog || return 1
    if [ -z "${1:-}" ]; then
      echo -e "${__red}✗${__reset} Usage: $main_function changelog show <version>" >&2
      return 1
    fi
    local entry
    entry=$(awk -v want="$(echo "$1" | tr '[:upper:]' '[:lower:]')" '
      /^## \[/ {
        if (found) exit
        heading = tolower($0)
        sub(/^## \[/, "", heading)
        sub(/\].*/, "", heading)
        if (heading == want) found = 1
      }
      found { print }
    ' "$changelog_file")
    if [ -z "$entry" ]; then
      echo -e "${__red}✗${__reset} No changelog entry for version $1" >&2
      return 1
    fi
    echo "$entry" | _page
  }

  # @function all
  # @description Reads the whole CHANGELOG.md in a pager
  function all() {
    _require_changelog || return 1
    _page < "$changelog_file"
  }

  main "$@"
)
