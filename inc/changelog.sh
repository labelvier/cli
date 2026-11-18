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

  # Colours/bold only on a terminal: `labelvier` empties the colour vars when
  # piped or NO_COLOR is set, and then the file is shown as it is.
  function _render() {
    if [ -z "$__bold" ]; then
      cat "$changelog_file"
      return
    fi
    local b r bl g c d
    b=$(printf '%b' "$__bold") r=$(printf '%b' "$__reset")
    bl=$(printf '%b' "$__blue") g=$(printf '%b' "$__green")
    c=$'\033[0;36m' d=$'\033[2m'
    awk -v b="$b" -v r="$r" -v bl="$bl" -v g="$g" -v c="$c" -v d="$d" '
      # `code` -> cyan, **bold** -> bold
      function inline(t,   out, p, q) {
        out = ""
        while ((p = index(t, "`")) > 0) {
          q = index(substr(t, p + 1), "`")
          if (q == 0) break
          out = out bold(substr(t, 1, p - 1)) c substr(t, p + 1, q - 1) r
          t = substr(t, p + q + 1)
        }
        return out bold(t)
      }
      function bold(t,   out, p, q) {
        out = ""
        while ((p = index(t, "**")) > 0) {
          q = index(substr(t, p + 2), "**")
          if (q == 0) break
          out = out substr(t, 1, p - 1) b substr(t, p + 2, q - 1) r
          t = substr(t, p + q + 3)
        }
        return out t
      }
      /^# /       { print b bl $0 r; next }
      /^## /      { print b g $0 r; next }
      /^### /     { print b c $0 r; next }
      /^\[[^]]+\]: / { print d $0 r; next }
      /^[-*] /    { print bl "•" r " " inline(substr($0, 3)); next }
      /^  +[-*] / { match($0, /[-*] /); print substr($0, 1, RSTART - 1) bl "◦" r " " inline(substr($0, RSTART + 2)); next }
      { print inline($0) }
    ' "$changelog_file"
  }

  # Not on a terminal (piped/redirected): no pager.
  if [ ! -t 1 ]; then
    _render
  elif [ -n "${PAGER:-}" ]; then
    _render | $PAGER
  elif command -v less > /dev/null 2>&1; then
    _render | less -FRX
  else
    _render
  fi
)
