#!/bin/bash
#
# Prints the CHANGELOG.md section for one version, without its heading.
#
#   scripts/changelog-section.sh 1.0.3
#
# Used by the release workflow to turn a tag into release notes, so the notes
# and the changelog can never drift apart.

set -e

version="${1:-}"

if [ -z "$version" ]; then
  echo "Usage: $(basename "$0") <version>" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

if [ ! -f CHANGELOG.md ]; then
  echo "No CHANGELOG.md found in $(pwd)." >&2
  exit 1
fi

# Everything between "## [<version>]" and the next "## [", heading excluded.
section=$(awk -v version="$version" '
  $0 ~ "^## \\[" version "\\]" { found = 1; next }
  found && /^## \[/ { exit }
  found { print }
' CHANGELOG.md)

# Strip the blank lines the section picks up at both ends.
section=$(printf '%s' "$section" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba')

if [ -z "$section" ]; then
  echo "No changelog section found for $version." >&2
  exit 1
fi

printf '%s\n' "$section"
