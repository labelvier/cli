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
    echo "Added $INSTALL_DIR to \$PATH in $rc_file."
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
if [ "$path_updated" -eq 0 ] && [ -t 1 ] && [ -z "${CI:-}" ] && [ -z "${LABELVIER_NO_EXEC:-}" ]; then
  echo "Starting a new shell so it's ready to use..."
  exec "$SHELL" -l
fi
