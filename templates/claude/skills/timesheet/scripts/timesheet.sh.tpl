#!/usr/bin/env bash
# Thin curl wrapper around the Label Vier Timesheet read-only API (v1).
# Config: TIMESHEET_URL (default below) + TIMESHEET_API_TOKEN (from ~/.claude/.env or env).
set -euo pipefail

# Read only our own keys from ~/.claude/.env without sourcing it: Sanctum tokens
# contain '|', which an unquoted value would turn into a shell pipe.
_env_value() {
	sed -n "s/^$1=//p" "$HOME/.claude/.env" | tail -n 1 | sed -e "s/^'\(.*\)'\$/\1/" -e 's/^"\(.*\)"$/\1/'
}
if [ -f "$HOME/.claude/.env" ]; then
	[ -z "${TIMESHEET_API_TOKEN:-}" ] && TIMESHEET_API_TOKEN="$(_env_value TIMESHEET_API_TOKEN)"
	[ -z "${TIMESHEET_URL:-}" ] && TIMESHEET_URL="$(_env_value TIMESHEET_URL)"
	[ -z "${TIMESHEET_TRANSPORT:-}" ] && TIMESHEET_TRANSPORT="$(_env_value TIMESHEET_TRANSPORT)"
fi

TIMESHEET_URL="${TIMESHEET_URL:-https://timesheet.labelvier.nl}"
TIMESHEET_URL="${TIMESHEET_URL%/}"

if [ -z "${TIMESHEET_API_TOKEN:-}" ]; then
	echo "Error: TIMESHEET_API_TOKEN not set (check ~/.claude/.env)" >&2
	exit 1
fi

# browser (default): fetch inside a browser session; a SiteGround challenge is
# shown to the person running the command (see ../browser/browser-get.mjs).
# curl: direct HTTP, only works where no bot challenge is in front of the API.
TIMESHEET_TRANSPORT="${TIMESHEET_TRANSPORT:-browser}"
BROWSER_GET="$(cd "$(dirname "$0")/../browser" && pwd)/browser-get.mjs"

# GET <path-with-query>, path relative to /api/v1 (e.g. /users or users?x=1)
_get() {
	local path="$1"
	case "$path" in /*) ;; *) path="/$path" ;; esac
	if [ "$TIMESHEET_TRANSPORT" = "browser" ]; then
		TIMESHEET_API_TOKEN="$TIMESHEET_API_TOKEN" node "$BROWSER_GET" "$TIMESHEET_URL" "$path"
		return
	fi
	curl -sS -m 30 --fail-with-body \
		-H "Authorization: Bearer ${TIMESHEET_API_TOKEN}" \
		-H "Accept: application/json" \
		"${TIMESHEET_URL}/api/v1${path}"
}

_need_jq() {
	command -v jq >/dev/null || {
		echo "Error: jq is required for $1" >&2
		exit 1
	}
}

_usage() {
	cat >&2 <<'USAGE'
Usage: timesheet.sh <command> [args]

  get <path>                                 raw GET under /api/v1 (e.g. get '/time-entries?per_page=5')
  users                                      all users (id, name; email/roles if visible to token owner)
  projects [--active]                        all projects incl. phases (budget_hours, completed_at, order)
  phases [project_id]                        phases, optionally for one project
  entries --from D --to D [--user ID] [--project ID] [--phase ID] [--per-page N] [--page N] [--all]
                                             time entries (paginated; --all fetches every page, returns a flat array)
  summary --from D --to D [--user ID] [--project ID]
                                             hours per user x project x phase
Dates are YYYY-MM-DD.
USAGE
	exit 1
}

cmd="${1:-}"
shift || true

case "$cmd" in
get)
	[ -n "${1:-}" ] || _usage
	_get "$1"
	echo
	;;
users)
	_get "/users"
	echo
	;;
projects)
	if [ "${1:-}" = "--active" ]; then
		_get "/projects?is_active=1"
	else
		_get "/projects"
	fi
	echo
	;;
phases)
	if [ -n "${1:-}" ]; then
		_get "/phases?project_id=$1"
	else
		_get "/phases"
	fi
	echo
	;;
entries | summary)
	from="" to="" user="" project="" phase="" per_page="" page="" all=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--from) from="$2"; shift 2 ;;
		--to) to="$2"; shift 2 ;;
		--user) user="$2"; shift 2 ;;
		--project) project="$2"; shift 2 ;;
		--phase) phase="$2"; shift 2 ;;
		--per-page) per_page="$2"; shift 2 ;;
		--page) page="$2"; shift 2 ;;
		--all) all=1; shift ;;
		*) echo "Unknown option: $1" >&2; _usage ;;
		esac
	done
	if [ -z "$from" ] || [ -z "$to" ]; then
		echo "Error: --from and --to are required (YYYY-MM-DD)" >&2
		exit 1
	fi
	qs="from=${from}&to=${to}"
	[ -n "$user" ] && qs="${qs}&user_id=${user}"
	[ -n "$project" ] && qs="${qs}&project_id=${project}"

	if [ "$cmd" = "summary" ]; then
		_get "/summary?${qs}"
		echo
		exit 0
	fi

	[ -n "$phase" ] && qs="${qs}&phase_id=${phase}"
	if [ "$all" -eq 1 ]; then
		_need_jq "--all"
		qs="${qs}&per_page=${per_page:-1000}"
		p=1
		tmp="$(mktemp)"
		trap 'rm -f "$tmp"' EXIT
		echo '[]' >"$tmp"
		while :; do
			resp="$(_get "/time-entries?${qs}&page=${p}")"
			jq -s '.[0] + .[1].data' "$tmp" <(printf '%s' "$resp") >"${tmp}.n" && mv "${tmp}.n" "$tmp"
			last="$(printf '%s' "$resp" | jq -r '.meta.last_page')"
			[ "$p" -ge "$last" ] && break
			p=$((p + 1))
		done
		cat "$tmp"
	else
		[ -n "$per_page" ] && qs="${qs}&per_page=${per_page}"
		[ -n "$page" ] && qs="${qs}&page=${page}"
		_get "/time-entries?${qs}"
		echo
	fi
	;;
*)
	_usage
	;;
esac
