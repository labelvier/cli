#!/bin/bash

check() (

  # Local filename to echo the documentation.
  local filename="check.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")

  # PHP_CodeSniffer with the WordPress standards lives in php/phpcs (vendor/ is gitignored).
  # Override the location with PHPCS_DIR, e.g. a checkout you are working on.
  local phpcs_dir="${PHPCS_DIR:-$(cd "$current_dir/../php/phpcs" && pwd)}"

  # Runs the command.
  function main() {
    _dispatch "$filename" "$@"
  }

  # @function php
  # @description Check changed theme PHP for security issues and bugs (no code style); --all, --base=<branch>, --committed.
  # Note: this function shadows the php binary inside this subshell. Use `type -P php`
  # or `command php`, never a bare `php`, in the helpers below.
  function php() {
    local all=false base="" committed=false
    local arg
    for arg in "$@"; do
      case "$arg" in
        --all) all=true ;;
        --base=*) base="${arg#--base=}" ;;
        # Only files changed in commits, not uncommitted or new files: what a push sends.
        --committed) committed=true ;;
        *)
          echo -e "${__red}✗${__reset} Unknown option: ${__bold}$arg${__reset}"
          echo "  Usage: labelvier check php [--all] [--base=<branch>] [--committed]"
          exit 1
          ;;
      esac
    done

    local theme_path
    theme_path=$(_check_php_theme_path) || exit 1
    _check_php_require || exit 1
    _check_php_install || exit 1

    local standard
    standard=$(_check_php_standard)

    if [ "$all" = true ]; then
      echo -e "Checking ${__bold}$theme_path${__reset} with ${__bold}$(_check_php_standard_label "$standard")${__reset}"
      _check_php_run "$standard" "$theme_path"
      exit $?
    fi

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo -e "${__red}✗${__reset} Not a git repository, so there are no changed files. Use ${__bold}--all${__reset} to check the whole theme."
      exit 1
    fi

    base=$(_check_php_base "$base") || exit 1

    local files
    files=$(_check_php_changed_files "$base" "$theme_path" "$committed")
    if [ -z "$files" ]; then
      echo -e "${__green}✓${__reset} No changed PHP files in ${__bold}$theme_path${__reset} compared to ${__bold}$base${__reset}."
      exit 0
    fi

    echo -e "Checking $(echo "$files" | wc -l | tr -d ' ') changed file(s) compared to ${__bold}$base${__reset} with ${__bold}$(_check_php_standard_label "$standard")${__reset}"
    # One file per line; split on newlines only and don't glob, so odd filenames survive.
    local IFS=$'\n'
    set -f
    # shellcheck disable=SC2086
    _check_php_run "$standard" $files
    exit $?
  }

  # @function install-hook
  # @description Add a git pre-push hook to this project that runs `check php --committed` before every push.
  function install-hook() {
    _check_php_theme_path >/dev/null || exit 1
    local hook
    hook=$(_check_hook_path) || exit 1

    if [ -f "$hook" ] && ! grep -qF "$(_check_hook_marker)" "$hook"; then
      echo -e "${__red}✗${__reset} There is already a pre-push hook in ${__bold}$hook${__reset} that labelvier did not write."
      echo "  Add this line to it yourself:"
      echo "  $(_check_hook_command)"
      exit 1
    fi

    mkdir -p "$(dirname "$hook")"
    _check_hook_script > "$hook"
    chmod +x "$hook"
    echo -e "${__green}✓${__reset} Pre-push hook installed in ${__bold}$hook${__reset}."
    echo "  Every git push now runs: labelvier check php --committed"
    echo "  Skip it once with: git push --no-verify"
  }

  # @function uninstall-hook
  # @description Remove the pre-push hook that install-hook added to this project.
  function uninstall-hook() {
    local hook
    hook=$(_check_hook_path) || exit 1

    if [ ! -f "$hook" ]; then
      echo "No pre-push hook in $hook, nothing to remove."
      exit 0
    fi
    if ! grep -qF "$(_check_hook_marker)" "$hook"; then
      echo -e "${__red}✗${__reset} The pre-push hook in ${__bold}$hook${__reset} was not written by labelvier, left it alone."
      exit 1
    fi
    rm "$hook"
    echo -e "${__green}✓${__reset} Pre-push hook removed from ${__bold}$hook${__reset}."
  }

  # The line that marks a hook as ours, so install can update it and uninstall can remove it.
  function _check_hook_marker() {
    echo "# labelvier check php pre-push hook"
  }

  # The command the hook runs. Git runs hooks without shell aliases, so it calls this CLI
  # by its full path. stdin is closed: git passes the pushed refs there, not for the CLI.
  function _check_hook_command() {
    local cli
    cli="$(cd "$current_dir/.." && pwd)/labelvier"
    echo "LABELVIER_AUTO_UPDATE=1 \"$cli\" check php --committed < /dev/null"
  }

  # Path of this repository's pre-push hook. Refuses when core.hooksPath is set, because
  # that folder belongs to another tool (husky, lefthook, ...) or is shared by all repos.
  function _check_hook_path() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo -e "${__red}✗${__reset} Not a git repository." >&2
      return 1
    fi
    local hooks_path
    hooks_path=$(git config --get core.hooksPath)
    if [ -n "$hooks_path" ]; then
      echo -e "${__red}✗${__reset} git uses its own hooks folder here (core.hooksPath = ${__bold}$hooks_path${__reset})." >&2
      echo "  Add this line to its pre-push hook yourself:" >&2
      echo "  $(_check_hook_command)" >&2
      return 1
    fi
    echo "$(git rev-parse --absolute-git-dir)/hooks/pre-push"
  }

  # The hook file.
  function _check_hook_script() {
    cat <<EOF
#!/bin/sh
$(_check_hook_marker)
# Written by \`labelvier check install-hook\`, removed by \`labelvier check uninstall-hook\`.
# Checks the theme PHP changed in the commits being pushed; errors stop the push.
# Skip it once with: git push --no-verify

# git does not hand the hook a terminal, so colours and the screen width are lost.
# When the push was started from a terminal, ask that terminal for them.
if (: < /dev/tty) 2>/dev/null; then
  export FORCE_COLOR=1
  LABELVIER_REPORT_WIDTH=\$(stty size < /dev/tty 2>/dev/null | cut -d ' ' -f 2)
  export LABELVIER_REPORT_WIDTH
fi

$(_check_hook_command)
EOF
  }

  # Prints the theme path from DEV_THEME_PATH in .env, relative to the project root.
  function _check_php_theme_path() {
    if [ ! -f .env ]; then
      echo -e "${__red}✗${__reset} No .env found. Run this from the root of a Label Vier project." >&2
      return 1
    fi
    local theme_path
    theme_path=$(grep -E '^DEV_THEME_PATH=' .env | tail -n 1 | cut -d '=' -f2- | tr -d "\"' \r")
    # .env has it as /wp-content/themes/<theme>; make it relative to the project root.
    theme_path="${theme_path#/}"
    theme_path="${theme_path%/}"
    if [ -z "$theme_path" ]; then
      echo -e "${__red}✗${__reset} DEV_THEME_PATH is not set in the .env file." >&2
      return 1
    fi
    if [ ! -d "$theme_path" ]; then
      echo -e "${__red}✗${__reset} Theme folder ${__bold}$theme_path${__reset} (DEV_THEME_PATH in .env) does not exist." >&2
      return 1
    fi
    echo "$theme_path"
  }

  # PHP and Composer run phpcs on the host. Offers 'brew install' when one is missing.
  function _check_php_require() {
    local missing=""
    type -P php >/dev/null 2>&1 || missing="php"
    type -P composer >/dev/null 2>&1 || missing="$missing composer"
    missing="${missing# }"
    [ -z "$missing" ] && return 0

    echo -e "${__red}✗${__reset} Missing: ${__bold}$missing${__reset} (needed to run PHP_CodeSniffer)."
    if ! type -P brew >/dev/null 2>&1 || ! _confirm "  Install it now with 'brew install $missing'?"; then
      echo "  Install it yourself: brew install $missing"
      return 1
    fi
    # shellcheck disable=SC2086
    brew install $missing || return 1
  }

  # Installs vendor/ on first use and again when composer.lock changed (after `core update`).
  function _check_php_install() {
    if [ ! -f "$phpcs_dir/composer.json" ]; then
      echo -e "${__red}✗${__reset} PHP_CodeSniffer setup not found in ${__bold}$phpcs_dir${__reset}. Check PHPCS_DIR."
      return 1
    fi
    local installed="$phpcs_dir/vendor/composer/installed.json"
    if [ -f "$installed" ] && [ -x "$phpcs_dir/vendor/bin/phpcs" ] && [ ! "$phpcs_dir/composer.lock" -nt "$installed" ]; then
      return 0
    fi
    echo "Installing PHP_CodeSniffer…"
    composer install --working-dir="$phpcs_dir" --no-interaction --no-progress --quiet || {
      echo -e "${__red}✗${__reset} composer install failed in ${__bold}$phpcs_dir${__reset}."
      return 1
    }
    # composer leaves installed.json alone when nothing changed; touch it so the lock check passes.
    touch "$installed"
  }

  # Short name of standard $1 for the output: the project file, or "Label Vier ruleset".
  function _check_php_standard_label() {
    if [ "$1" = "$phpcs_dir/ruleset.xml" ]; then
      echo "the Label Vier ruleset"
    else
      echo "${1#"$PWD"/}"
    fi
  }

  # A project's own phpcs config wins; otherwise the Label Vier ruleset from the CLI.
  function _check_php_standard() {
    local file
    for file in .phpcs.xml phpcs.xml .phpcs.xml.dist phpcs.xml.dist; do
      if [ -f "$file" ]; then
        echo "$PWD/$file"
        return
      fi
    done
    echo "$phpcs_dir/ruleset.xml"
  }

  # Prints the branch to compare with: the given one, else develop, main or master.
  # origin/ first: a local develop that was never pulled lags behind, and comparing with it
  # would pull in files changed by other people's commits. Falls back to the local branch.
  function _check_php_base() {
    local candidates="$1"
    [ -z "$candidates" ] && candidates="develop main master"
    local name ref
    for name in $candidates; do
      for ref in "origin/$name" "$name"; do
        if git rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then
          echo "$ref"
          return 0
        fi
      done
    done
    echo -e "${__red}✗${__reset} Branch ${__bold}${1:-develop, main or master}${__reset} not found. Use --base=<branch> or --all." >&2
    return 1
  }

  # Theme PHP files changed since the branch point with $1, plus uncommitted and new
  # files unless $3 is true (--committed).
  function _check_php_changed_files() {
    local base="$1" pathspec="$2/*.php" committed="${3:-false}"
    {
      git diff --name-only --diff-filter=d "$base...HEAD" -- "$pathspec"
      if [ "$committed" != true ]; then
        git diff --name-only --diff-filter=d HEAD -- "$pathspec"
        git ls-files --others --exclude-standard -- "$pathspec"
      fi
    } | sort -u
  }

  # Runs phpcs with standard $1 on the remaining arguments and reports the result.
  function _check_php_run() {
    local standard="$1"
    shift
    local status=0
    local options=()
    # Colours whenever the CLI uses them (a terminal, or FORCE_COLOR from the hook).
    [ -n "$__reset" ] && options+=(--colors)
    # The ruleset's report-width "auto" only works on a terminal; the hook passes the width.
    [ -n "${LABELVIER_REPORT_WIDTH:-}" ] && options+=(--report-width="$LABELVIER_REPORT_WIDTH")
    # ${options[@]+...}: bash 3.2 with set -u treats an empty array as unbound.
    "$phpcs_dir/vendor/bin/phpcs" --standard="$standard" --basepath="$PWD" -q ${options[@]+"${options[@]}"} "$@" || status=$?
    if [ "$status" -eq 0 ]; then
      echo -e "${__green}✓${__reset} No security issues or bugs found."
    else
      echo -e "${__red}✗${__reset} PHP_CodeSniffer found errors (see above)."
    fi
    return "$status"
  }

  main "$@"
)
