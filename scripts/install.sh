#!/bin/bash
#
# Installs the Label Vier CLI (labelvier / l4).
#
#   curl -fsSL https://raw.githubusercontent.com/labelvier/cli/master/scripts/install.sh | bash
#
# Non-interactive by design: this script's stdin is the curl stream, not a
# terminal, so it never `read`s. Everything is detected/decided automatically.

set -e

REPO="labelvier/cli"
INSTALL_DIR="${LABELVIER_CLI_DIR:-$HOME/.labelvier}"

show_banner() {
  # Skip the braille mark if the terminal is too narrow (logo 32 + gap 3 + text 9 = 44)
  local cols
  cols=$(tput cols 2>/dev/null || echo 80)
  if [ "$cols" -lt 44 ]; then
    echo ""
    echo "Label Vier CLI"
    echo ""
    return
  fi

  local b="" c="" r=""
  if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
    b=$'\033[1m'
    c=$'\033[38;2;226;101;94m'
    r=$'\033[0m'
  fi

  local logo=(
    "⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡠⢤⣐⠲⠶⠤⠤⠶⠶⣂⡤⢄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⣀⢔⡪⠓⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠚⠵⡢⣄⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⡠⣪⠔⠁⠀⠀⠀⠀⠀⢀⠀⠀⢀⠀⠀⠀⠀⠀⠀⠀⠈⠲⢕⢄⠀⠀⠀⠀"
    "⠀⠀⢀⢜⠔⠁⠀⠀⠀⠀⠀⠀⢠⢋⠭⡫⢸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠣⡱⡀⠀⠀"
    "⠀⢀⢮⠊⠀⠀⠀⠀⠀⠀⠀⢠⢃⠎⠀⡇⢸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⡕⡀⠀"
    "⠀⣎⠇⠀⠀⠀⠀⠀⠀⠀⡰⢡⠋⠀⠀⡇⢸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣱⠀"
    "⢰⡘⠀⠀⠀⠀⠀⠀⠀⡰⢡⠃⠀⠀⠀⡇⢸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢣⡇"
    "⠘⡇⠀⠀⠀⠀⠀⠀⢸⠤⢇⣀⣀⣀⣀⣧⣼⣀⣀⣀⣀⣀⣀⣀⠀⠀⠀⠀⠀⠀⢸⢰"
    "⢠⡇⠀⠀⠀⠀⠀⠀⠈⠉⠉⠉⠉⠉⠑⡟⢻⠊⠉⠉⠉⢑⠖⡜⠀⠀⠀⠀⠀⠀⢸⠸"
    "⠸⢣⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⢸⠀⠀⠀⢠⢎⡜⠀⠀⠀⠀⠀⠀⠀⡘⡇"
    "⠀⢏⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⢸⠀⠀⢠⢃⠎⠀⠀⠀⠀⠀⠀⠀⢠⡻⠀"
    "⠀⠈⢞⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⢸⠀⣠⢃⠎⠀⠀⠀⠀⠀⠀⠀⢠⢣⠃⠀"
    "⠀⠀⠈⢮⢢⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⠮⠒⢡⠃⠀⠀⠀⠀⠀⠀⠀⡴⡱⠁⠀⠀"
    "⠀⠀⠀⠀⠑⢕⠤⡀⠀⠀⠀⠀⠀⠀⠀⠉⠉⠉⠁⠀⠀⠀⠀⠀⢀⡤⡪⠊⠀⠀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⠑⠪⢖⠤⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⠤⣒⠕⠊⠀⠀⠀⠀⠀⠀"
    "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠑⠚⠭⠶⢒⣒⣒⡒⠶⠬⠛⠊⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀"
  )
  local text="Label Vier CLI"
  local pad=$(( (32 - ${#text}) / 2 ))

  echo ""
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    for line in "${logo[@]}"; do
      echo "${c}${line}${r}"
      sleep 0.02
    done
    sleep 0.1
    echo ""
    local i
    printf "%${pad}s" ""
    for (( i=0; i<${#text}; i++ )); do
      printf "%s%s%s" "${b}" "${text:$i:1}" "${r}"
      sleep 0.02
    done
    printf "\n"
  else
    local i
    for i in "${!logo[@]}"; do
      echo "${logo[$i]}"
    done
    echo ""
    printf "%${pad}s%s\n" "" "$text"
  fi
  echo ""
}

show_banner

if [ -d "$INSTALL_DIR/.git" ]; then
  echo "Already installed at $INSTALL_DIR — updating..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  echo "Cloning $REPO to $INSTALL_DIR..."
  git clone "https://github.com/$REPO.git" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/labelvier"

path_updated=1
if [[ ":$PATH:" == *":$INSTALL_DIR:"* ]]; then
  echo "labelvier is already on your \$PATH."
else
  shell_name=$(basename "${SHELL:-}")
  case "$shell_name" in
    zsh)
      rc_file="$HOME/.zshrc"
      path_line="export PATH=\$PATH:$INSTALL_DIR"
      ;;
    bash)
      # A login shell (what we exec below, and what Terminal.app starts on
      # macOS) reads ~/.bash_profile — NOT ~/.bashrc. Writing to .bashrc is
      # why the PATH change did not take effect without a manual restart.
      if [ -f "$HOME/.bash_profile" ] || [ ! -f "$HOME/.profile" ]; then
        rc_file="$HOME/.bash_profile"
      else
        rc_file="$HOME/.profile"
      fi
      path_line="export PATH=\$PATH:$INSTALL_DIR"
      ;;
    fish)
      rc_file="$HOME/.config/fish/config.fish"
      mkdir -p "$(dirname "$rc_file")"
      path_line="set -gx PATH \$PATH $INSTALL_DIR"
      ;;
    *)
      rc_file=""
      ;;
  esac

  if [ -n "$rc_file" ]; then
    # Re-running the installer must not stack duplicate PATH entries.
    if [ -f "$rc_file" ] && grep -qF "$INSTALL_DIR" "$rc_file"; then
      echo "$rc_file already points at $INSTALL_DIR."
    else
      echo "$path_line" >> "$rc_file"
      echo "Added $INSTALL_DIR to \$PATH in $rc_file."
    fi
    # Either way this shell does not have it yet, so it still needs reloading.
    path_updated=0
  else
    echo "Could not detect your shell (\$SHELL=$SHELL) — add this to your shell config manually:"
    echo "  export PATH=\$PATH:$INSTALL_DIR"
  fi
fi

echo
echo "Installed! Run 'labelvier' or 'l4' to get started."

# Drop straight into a fresh login shell so labelvier/l4 works right away,
# without the user having to restart their terminal or run 'source ~/.zshrc'
# themselves. Only when this is a real interactive terminal (not CI, not
# LABELVIER_NO_EXEC) — never for piped/scripted installs.
#
# The documented install is `curl ... | bash`, so this script's stdin is the
# curl pipe, not the terminal. Handing that stdin to the new shell makes it
# start non-interactively, read EOF and exit immediately — the terminal falls
# back to the original shell with the original PATH, and `labelvier` is still
# not found until the user restarts the terminal by hand. Reconnect stdin to
# the controlling terminal so the new shell is actually interactive.
if [ "$path_updated" -eq 0 ] && [ -z "${CI:-}" ] && [ -z "${LABELVIER_NO_EXEC:-}" ] \
  && [ -t 1 ] && [ -r /dev/tty ]; then
  echo "Starting a new shell so it's ready to use..."
  exec "$SHELL" -l < /dev/tty
fi

# No new shell was started (piped output, CI, or no controlling terminal), so
# tell the user how to pick up the change without restarting the terminal.
if [ "$path_updated" -eq 0 ]; then
  echo
  echo "Run this to use labelvier in this terminal:"
  echo "  source $rc_file"
fi
