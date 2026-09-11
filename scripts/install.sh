#!/bin/bash
#
# Installs the Label Vier CLI (labelvier / l4).
#
#   curl -fsSL https://raw.githubusercontent.com/labelvier/cli/master/scripts/install.sh | bash
#
# Pin a release instead of tracking master:
#
#   curl -fsSL https://raw.githubusercontent.com/labelvier/cli/1.0.3/scripts/install.sh | bash -s -- 1.0.3
#
# The ref in the URL only picks which installer you download — the version
# argument is what decides which version ends up in $INSTALL_DIR. Passing both
# keeps the two in step, which is why the release notes hand out that one line.
# LABELVIER_CLI_REF does the same as the argument, for callers that find an
# environment variable easier to thread through.
#
# Non-interactive by design: this script's stdin is the curl stream, not a
# terminal, so it never `read`s. Everything is detected/decided automatically.

set -e

REPO="labelvier/cli"
INSTALL_DIR="${LABELVIER_CLI_DIR:-$HOME/.labelvier}"
REF="${1:-${LABELVIER_CLI_REF:-}}"

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
  # --force so a moved tag still lands; tags are the only thing a pinned
  # install has to go on.
  git -C "$INSTALL_DIR" fetch --tags --force --quiet
  if [ -n "$REF" ]; then
    git -C "$INSTALL_DIR" checkout --quiet "$REF"
  elif git -C "$INSTALL_DIR" symbolic-ref -q HEAD > /dev/null; then
    git -C "$INSTALL_DIR" pull --ff-only
  else
    # Pinned install, no version asked for: put it back on the branch that
    # tracks releases, otherwise the update checker has no upstream to compare
    # against and every run would ask about an update it cannot do.
    echo "Was pinned to a release — moving back to master."
    git -C "$INSTALL_DIR" checkout --quiet master
    git -C "$INSTALL_DIR" pull --ff-only
  fi
else
  echo "Cloning $REPO to $INSTALL_DIR..."
  git clone "https://github.com/$REPO.git" "$INSTALL_DIR"
  if [ -n "$REF" ]; then
    git -C "$INSTALL_DIR" checkout --quiet "$REF"
  fi
fi

if [ -n "$REF" ]; then
  echo "Pinned to $REF."
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
