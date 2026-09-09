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
