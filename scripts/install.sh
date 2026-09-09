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
    c=$'\033[0;34m'
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
  local text_line=7

  echo ""
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    for line in "${logo[@]}"; do
      echo "${c}${line}${r}"
      sleep 0.02
    done
    sleep 0.1
    local text="labelvier" i
    local lines_up=$(( ${#logo[@]} - text_line ))
    printf "\033[%dA\033[36G" "$lines_up"
    for (( i=0; i<${#text}; i++ )); do
      printf "%s%s%s" "${b}" "${text:$i:1}" "${r}"
      sleep 0.02
    done
    printf "\033[%dB\r" "$lines_up"
  else
    local i
    for i in "${!logo[@]}"; do
      if [ "$i" -eq "$text_line" ]; then
        echo "${logo[$i]}   labelvier"
      else
        echo "${logo[$i]}"
      fi
    done
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

if [[ ":$PATH:" == *":$INSTALL_DIR:"* ]]; then
  echo "labelvier is already on your \$PATH."
else
  shell_name=$(basename "${SHELL:-}")
  case "$shell_name" in
    zsh)
      rc_file="$HOME/.zshrc"
      echo "export PATH=\$PATH:$INSTALL_DIR" >> "$rc_file"
      ;;
    bash)
      rc_file="$HOME/.bashrc"
      echo "export PATH=\$PATH:$INSTALL_DIR" >> "$rc_file"
      ;;
    fish)
      rc_file="$HOME/.config/fish/config.fish"
      mkdir -p "$(dirname "$rc_file")"
      echo "set -gx PATH \$PATH $INSTALL_DIR" >> "$rc_file"
      ;;
    *)
      rc_file=""
      ;;
  esac

  if [ -n "$rc_file" ]; then
    echo "Added $INSTALL_DIR to \$PATH in $rc_file — restart your shell (or run 'source $rc_file') to use it."
  else
    echo "Could not detect your shell (\$SHELL=$SHELL) — add this to your shell config manually:"
    echo "  export PATH=\$PATH:$INSTALL_DIR"
  fi
fi

echo
echo "Installed! Run 'labelvier' or 'l4' to get started."
