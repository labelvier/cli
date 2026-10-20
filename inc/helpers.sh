#!/bin/bash

function _needs_active_wptakeoff_project() {
  # check if we have an .env file
  if [ -f .env ]; then
    # get the DEV_THEME_PATH from the .env file
      local dev_theme_path=$(grep DEV_THEME_PATH .env | cut -d '=' -f2)
      # exit if the DEV_THEME_PATH is not set
      if [ -z "$dev_theme_path" ]; then
        echo "DEV_THEME_PATH is not set in the .env file"
        exit 1
      fi
  fi
  # Check if we are in the right directory
  style_path="./$dev_theme_path/src/scss/style.scss"
  if [ ! -f $style_path ]; then
    echo "You are not in the right directory. Please run this command from the root of your theme."
    echo $style_path
    exit 1
  fi
}

function _echo_documentation() {
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")
  # first arguments is the name of the file
  local contents=$(cat "$current_dir/$1")
  # get all lines starting with any whitespace, then # @function and the next line
  local functions=$(echo "$contents" | grep -E "^\s*# @function" -A 1)
  echo -e "${__bold}Available functions:${__reset}"
  # loop through all functions
  while read -r line; do
    # get the name of the function
    local function_name=$(echo "$line" | cut -d' ' -f3-)
    # get the description of the function (the next line)
    read -r line
    local function_description=$(echo -e "$line" | cut -d' ' -f3-)
    # print the name and description
    echo -e "  ${__bold}$function_name${__reset} - $function_description"
    read -r line
  done <<<"$functions"
}

function _echo_function_description() {
  # first argument is the file to search, second is the subcommand name
  local current_dir=$(dirname "${BASH_SOURCE[0]}")
  local contents=$(cat "$current_dir/$1")
  local target="$2"
  local functions=$(echo "$contents" | grep -E "^\s*# @function" -A 1)
  local function_name function_description first_word
  while read -r line; do
    function_name=$(echo "$line" | cut -d' ' -f3-)
    read -r line
    function_description=$(echo -e "$line" | cut -d' ' -f3-)
    # the @function line may have usage args after the name (e.g. "start <version>")
    first_word=${function_name%% *}
    if [[ "$first_word" == "$target" ]]; then
      echo -e "${__bold}$function_name${__reset} - $function_description"
      return 0
    fi
    read -r line
  done <<<"$functions"

  # no documented description found, still print something rather than nothing
  echo -e "${__bold}$target${__reset}"
  return 1
}

# Shared main() dispatcher. Given the command file's own filename and "$@":
# runs the matching subcommand, but if --help is the argument right after the
# subcommand name, prints its one-line @description instead of running it.
# Falls back to the file's full documentation when no subcommand is given.
function _dispatch() {
  local filename="$1"
  shift
  local subcommand="$1"

  # No subcommand, or it looks like a flag (e.g. a bare `--help`) — show docs.
  # The `-*` check also matters because bash's `type -t` chokes on an arg
  # that looks like its own flag (errors instead of just failing).
  if [[ -z "$subcommand" ]] || [[ "$subcommand" == -* ]]; then
    _echo_documentation "$filename"
    return
  fi

  # A real subcommand name was typed but it doesn't exist — say so, don't
  # just silently dump the same docs a bare call would show.
  if ! type -t "$subcommand" | grep -q 'function'; then
    echo -e "${__red}✗${__reset} Unknown command: ${__bold}$subcommand${__reset}"
    echo
    _echo_documentation "$filename"
    return 1
  fi
  shift

  if [[ "$1" == "--help" ]]; then
    _echo_function_description "$filename" "$subcommand"
    return
  fi

  "$subcommand" "$@"
}

function _flag_is_present() {
  # first argument is the flag we are looking for
  flag_to_check="$1"
  shift
  args=("$@")

  # loop through all arguments
  for arg in "${args[@]}"; do
    # check if the argument is the flag we are looking for
    if [ "$arg" == "--$flag_to_check" ]; then
      # if it is, return 0 (true)
      return 0
    fi
  done
  # if we get here, the flag was not found
  return 1
}

function _is_semantic_version() {
  # first argument is the version we are checking
  local version="$1"
  # get the first part till an optional space or dash
  local first_part=$(echo "$version" | cut -d' ' -f1 | cut -d'-' -f1)
  # check if the version is a semantic version
  if [[ $first_part =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # if it is, return 0 (true)
    return 0
  fi
  # if we get here, the version is not a semantic version
  return 1
}

# Offers to install Homebrew itself (via the official install script) when
# it's missing, so callers can fall through to `brew install <thing>`
# instead of just telling the user to go install <thing> by hand. Returns
# 1 (without exiting) when brew is still unavailable — declined, or the
# install failed — so callers can fall back to their own manual-install message.
# terminal-notifier only has a Homebrew bottle for recent Apple Silicon macOS.
# Elsewhere (Intel Macs, older macOS) brew builds it from source, which needs
# the full Xcode.app; the Command Line Tools are not enough. Succeeds when brew
# can install it here, or when that cannot be told (no brew yet).
function _can_install_terminal_notifier() {
  type -P brew >/dev/null 2>&1 || return 0
  brew ruby -e 'puts Formula["terminal-notifier"].bottle ? "bottle" : "source"' 2>/dev/null | grep -qx bottle && return 0
  [ -d /Applications/Xcode.app ]
}

# Said wherever terminal-notifier cannot be installed on this Mac.
function _echo_terminal_notifier_unavailable() {
  echo "Clickable notifications are not available on this Mac: Homebrew has no ready-made terminal-notifier"
  echo "for $(uname -m) macOS $(sw_vers -productVersion 2>/dev/null), and building it needs the full Xcode.app."
  echo "The automatic update still notifies you, only without the click action."
}

function _require_brew() {
  if type -P brew >/dev/null 2>&1; then
    return 0
  fi

  echo -e "${__red}Homebrew is not installed.${__reset} It's the easiest way to install missing dependencies."
  _confirm "Install Homebrew now?" || return 1

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # The installer doesn't update PATH in this already-running shell — pick
  # up brew from its known install locations ourselves.
  if ! type -P brew >/dev/null 2>&1; then
    local candidate
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
      if [ -x "$candidate" ]; then
        eval "$("$candidate" shellenv)"
        break
      fi
    done
  fi

  if ! type -P brew >/dev/null 2>&1; then
    echo -e "${__red}Homebrew installed but still not on your PATH in this shell.${__reset} Open a new shell and try again."
    return 1
  fi
}

# Asks a [Y/n] question on the terminal, also when stdin is a pipe or a
# here-string. Returns 0 on yes (or Enter), 1 on "n", and 2 when there is no
# terminal to ask on (launchd, cron, CI), so nothing is installed unasked.
# The /dev/tty check runs first, in a subshell: `read -p` writes its prompt
# to stderr, so `read ... < /dev/tty 2>/dev/null` would hide the question.
function _confirm() {
  if ! (: < /dev/tty) 2>/dev/null; then
    echo "$1 [Y/n] (no terminal to ask on, skipped)"
    return 2
  fi
  local answer
  read -p "$1 [Y/n] " answer < /dev/tty
  case "$answer" in
    [nN]*) return 1 ;;
  esac
}

# nvm is a shell function, not a binary, so look for its script and source it
# into this shell (that also puts nvm's default Node on PATH). Homebrew's nvm
# lives outside NVM_DIR and is only loaded by the source line in the shell
# profile, so a fresh install or a non-interactive shell has nvm on disk and
# still no npm. Returns 1 when nvm is not installed.
function _load_nvm() {
  type nvm >/dev/null 2>&1 && return 0
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

  local nvm_sh
  for nvm_sh in "$NVM_DIR/nvm.sh" /opt/homebrew/opt/nvm/nvm.sh /usr/local/opt/nvm/nvm.sh \
    "$(type -P brew >/dev/null 2>&1 && brew --prefix nvm 2>/dev/null)/nvm.sh"; do
    if [ -s "$nvm_sh" ]; then
      # nvm.sh can complain and return non-zero when no default Node is
      # installed yet, nvm itself is loaded either way.
      # shellcheck disable=SC1090
      . "$nvm_sh" >/dev/null 2>&1
      type nvm >/dev/null 2>&1 && return 0
    fi
  done
  return 1
}

# Checks for nvm and offers 'brew install nvm' when it is missing. nvm's own
# docs don't support the Homebrew install, but it is what we use on our Macs
# and it updates along with the rest of brew. Homebrew's nvm needs NVM_DIR and
# a source line in the shell profile, so those are added too.
function _require_nvm() {
  if _load_nvm; then
    echo -e "${__green}✓${__reset} nvm"
    return 0
  fi

  echo -e "${__red}✗${__reset} nvm is not installed (manages the Node.js version per project)."
  if ! type -P brew >/dev/null 2>&1; then
    echo "  Install Homebrew first, then run: brew install nvm"
    return 1
  fi
  if ! _confirm "  Install it now with 'brew install nvm'?"; then
    echo -e "  Skipped. Install it yourself: ${__blue}https://github.com/nvm-sh/nvm#installing-and-updating${__reset}"
    return 1
  fi
  brew install nvm || return 1

  # nvm refuses to install anything when NVM_DIR does not exist yet.
  mkdir -p "$NVM_DIR"

  if ! _load_nvm; then
    echo -e "${__red}✗${__reset} nvm is installed, but nvm.sh could not be found. Open a new shell and try again."
    return 1
  fi
  echo -e "${__green}✓${__reset} nvm installed"
  _persist_nvm_profile
}

# Appends NVM_DIR and the nvm.sh source line to the shell profile once, so
# nvm (and npm) still work in the next shell. Skips it when a profile already
# mentions NVM_DIR.
function _persist_nvm_profile() {
  local profile="$HOME/.zshrc" candidates="$HOME/.zshrc $HOME/.zprofile $HOME/.zshenv"
  if [ "${SHELL##*/}" = "bash" ]; then
    profile="$HOME/.bash_profile"
    candidates="$HOME/.bash_profile $HOME/.bashrc $HOME/.profile"
  fi

  local file
  for file in $candidates; do
    [ -f "$file" ] && grep -q 'NVM_DIR' "$file" && return 0
  done

  local nvm_sh
  nvm_sh="$(brew --prefix nvm 2>/dev/null)/nvm.sh"
  [ -s "$nvm_sh" ] || nvm_sh="$NVM_DIR/nvm.sh"

  {
    echo ''
    echo '# Added by labelvier: load nvm'
    echo 'export NVM_DIR="$HOME/.nvm"'
    echo "[ -s \"$nvm_sh\" ] && . \"$nvm_sh\""
  } >> "$profile"

  echo -e "${__green}✓${__reset} nvm added to $profile"
}

# Checks for Node.js and offers 'nvm install --lts' when it is missing.
# Needs nvm, see _require_nvm.
function _require_node() {
  if type -P node >/dev/null 2>&1 || { _load_nvm && type -P node >/dev/null 2>&1; }; then
    echo -e "${__green}✓${__reset} node ($(node --version 2>/dev/null))"
    return 0
  fi

  echo -e "${__red}✗${__reset} node is not installed (npm builds the themes and installs the toon tool)."
  if ! _load_nvm; then
    echo "  Install nvm first, then run: nvm install --lts"
    return 1
  fi
  if ! _confirm "  Install the latest LTS version with 'nvm install --lts'?"; then
    echo "  Skipped."
    return 1
  fi
  nvm install --lts && nvm alias default 'lts/*' >/dev/null

  if type -P node >/dev/null 2>&1; then
    echo -e "${__green}✓${__reset} node $(node --version) installed. Open a new shell to use it there too."
  else
    echo -e "${__red}✗${__reset} node is still not found. Open a new shell and try again."
    return 1
  fi
}

# npm comes with Node.js, Node.js comes from nvm: offers to install whatever
# is missing of those (Homebrew included). Silent when npm is already there.
function _require_npm() {
  if type -P npm >/dev/null 2>&1 || { _load_nvm && type -P npm >/dev/null 2>&1; }; then
    return 0
  fi
  _require_brew
  _require_nvm && _require_node && type -P npm >/dev/null 2>&1
}
