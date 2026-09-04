#!/usr/bin/env bash
#
# Claude Code PreToolUse/Bash hook — installed by `wp-takeoff ai toon add-hook`.
#
# Rewrites a plain `basecamp ...` command so its JSON output is piped through the
# TOON formatter, which Claude reads with far fewer tokens than raw JSON.
#
# Only the `basecamp` CLI is supported right now. Every other command is passed
# through untouched.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -z "$cmd" ]]; then
  exit 0
fi

# Only rewrite a bare `basecamp ...` invocation: no pipes, redirects,
# chaining or backgrounding, and not already formatted.
if [[ ! "$cmd" =~ ^[[:space:]]*basecamp[[:space:]] ]]; then
  exit 0
fi
if [[ "$cmd" =~ [\|\>\<\;\&\`] ]]; then
  exit 0
fi
if [[ "$cmd" == *toon* ]]; then
  exit 0
fi
# Skip flags whose output is not JSON: markdown, jq-filtered values, help, version.
if [[ "$cmd" =~ (^|[[:space:]])(-m|--md|--jq|-h|--help|--version)([[:space:]]|$) ]]; then
  exit 0
fi

# Prefer the globally installed `toon` binary (~40ms) over npx (~1.1s).
formatter="npx @toon-format/cli"
if command -v toon >/dev/null 2>&1 || compgen -G "$HOME/.nvm/versions/node/*/bin/toon" >/dev/null 2>&1; then
  formatter="toon"
fi

printf '%s' "$input" | jq -c \
  --arg suffix " | $formatter" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse", updatedInput:(.tool_input | .command += $suffix)}}'
