#!/usr/bin/env bash
# Thin curl wrapper around the Label Vier Timesheet API (v1).
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

# <METHOD> <path-with-query> [json-body], path relative to /api/v1 (e.g. /users or users?x=1)
_request() {
	local method="$1" path="$2" body="${3:-}"
	case "$path" in /*) ;; *) path="/$path" ;; esac
	if [ "$TIMESHEET_TRANSPORT" = "browser" ]; then
		TIMESHEET_API_TOKEN="$TIMESHEET_API_TOKEN" TIMESHEET_BODY="$body" node "$BROWSER_GET" "$TIMESHEET_URL" "$path" "$method"
		return
	fi
	local args=(-sS -m 30 --fail-with-body -X "$method"
		-H "Authorization: Bearer ${TIMESHEET_API_TOKEN}"
		-H "Accept: application/json")
	[ -n "$body" ] && args+=(-H "Content-Type: application/json" --data "$body")
	curl "${args[@]}" "${TIMESHEET_URL}/api/v1${path}"
}

_get() { _request GET "$1"; }

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
  me                                         the token owner (id, name, email): who am I
  users                                      all users (id, name; email/roles if visible to token owner)
  projects [--active]                        all projects incl. phases (budget_hours, completed_at, order)
  phases [project_id]                        phases, optionally for one project
  entries --from D --to D [--user ID] [--project ID] [--phase ID] [--per-page N] [--page N] [--all]
                                             time entries (paginated; --all fetches every page, returns a flat array)
  summary --from D --to D [--user ID] [--project ID]
                                             hours per user x project x phase
  log --phase ID --date D --hours H [--description TEXT]
                                             book own hours (needs a token with ability write); replaces an existing booking for that phase/day
  delete <entry_id>                          delete one of your own bookings (needs ability write)
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
me)
	_get "/me"
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
log)
	phase="" date="" hours="" description="" has_desc=0
	while [ $# -gt 0 ]; do
		[ $# -ge 2 ] || { echo "Error: $1 needs a value" >&2; exit 1; }
		case "$1" in
		--phase) phase="${2:-}"; shift 2 ;;
		--date) date="${2:-}"; shift 2 ;;
		--hours) hours="${2:-}"; shift 2 ;;
		--description) description="${2:-}"; has_desc=1; shift 2 ;;
		*) echo "Unknown option: $1" >&2; _usage ;;
		esac
	done
	if [ -z "$phase" ] || [ -z "$date" ] || [ -z "$hours" ]; then
		echo "Error: --phase, --date (YYYY-MM-DD) and --hours (decimal, e.g. 1.5) are required" >&2
		exit 1
	fi
	[[ "$phase" =~ ^[0-9]+$ ]] || { echo "Error: --phase must be a numeric phase id" >&2; exit 1; }
	[[ "$hours" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "Error: --hours must be decimal with a dot (1.5 = 1:30)" >&2; exit 1; }
	_need_jq "log"
	body="$(jq -cn --arg phase "$phase" --arg date "$date" --arg hours "$hours" --arg desc "$description" --argjson has_desc "$has_desc" \
		'{phase_id: ($phase|tonumber), date: $date, hours: ($hours|tonumber)} + (if $has_desc == 1 then {description: $desc} else {} end)')"
	_request POST "/time-entries" "$body"
	echo
	;;
delete)
	[[ "${1:-}" =~ ^[0-9]+$ ]] || { echo "Error: delete needs a numeric entry id" >&2; exit 1; }
	_request DELETE "/time-entries/$1"
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
