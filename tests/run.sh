#!/usr/bin/env bash
#
# Run the whole test suite: syntax check, bats (bash) and node:test (node/siteground).
#
# Usage: tests/run.sh [bats|node|syntax] [-- <extra bats args>]
# No argument runs everything. Needs bats-core (brew install bats-core) and node 20+.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
what="${1:-all}"
shift || true
[ "${1:-}" = "--" ] && shift
status=0

bold=$'\033[1m'; red=$'\033[0;31m'; green=$'\033[0;32m'; reset=$'\033[0m'
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then bold=""; red=""; green=""; reset=""; fi

section() { echo; echo "${bold}== $1${reset}"; }

run_syntax() {
  section "syntax (bash -n)"
  local file failed=0
  for file in "$ROOT/labelvier" "$ROOT"/inc/*.sh "$ROOT"/scripts/*.sh "$ROOT"/tests/run.sh; do
    if ! bash -n "$file"; then
      echo "${red}✗${reset} $file"
      failed=1
    fi
  done
  # Templates are bash too, once their placeholders are filled; a syntax check still catches typos.
  for file in "$ROOT"/templates/*.sh.tpl; do
    bash -n "$file" 2>/dev/null || echo "  (template $file does not parse as-is, placeholders?)"
  done
  [ "$failed" -eq 0 ] && echo "${green}✓${reset} all files parse"
  return "$failed"
}

run_bats() {
  section "bats"
  if ! command -v bats >/dev/null 2>&1; then
    echo "${red}✗${reset} bats not found. Install: brew install bats-core"
    return 1
  fi
  # With explicit arguments (files, bats flags) run just those; otherwise the whole directory.
  if [ $# -gt 0 ]; then
    bats "$@"
  else
    bats --recursive "$ROOT/tests/bats"
  fi
}

run_node() {
  section "node:test (node/siteground)"
  if ! command -v node >/dev/null 2>&1; then
    echo "${red}✗${reset} node not found"
    return 1
  fi
  (cd "$ROOT/node/siteground" && node --test "$@" "test/*.test.js")
}

case "$what" in
  syntax) run_syntax "$@" || status=1 ;;
  bats) run_bats "$@" || status=1 ;;
  node) run_node "$@" || status=1 ;;
  all)
    run_syntax || status=1
    run_bats || status=1
    run_node || status=1
    ;;
  *)
    echo "Usage: tests/run.sh [all|syntax|bats|node] [-- <args>]" >&2
    exit 2
    ;;
esac

echo
if [ "$status" -eq 0 ]; then
  echo "${green}✓ all green${reset}"
else
  echo "${red}✗ failures${reset}"
fi
exit "$status"
