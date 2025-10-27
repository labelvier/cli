#!/bin/bash

RED='\033[0;31m'    # For directories with Gigabytes (G)
YELLOW='\033[1;33m' # For directories with Megabytes (M)
NC='\033[0m'       # No Color (reset)

function _get_color_code() {
  local size_str="$1"

  # Rough color estimation based on size suffix:
  if [[ "$size_str" == *G* ]]; then
    echo -n "$RED"
    return
  fi

  if [[ "$size_str" == *M* ]]; then
    echo -n "$YELLOW"
    return
  fi

  echo -n "$NC"
}

function _list_dirs_recursively() {
  local dir="$1"
  local depth="$2"
  local max_depth="$3"

  # Check the depth: stop if we have reached max_depth
  if [ -n "$max_depth" ] && [ "$depth" -gt "$max_depth" ]; then
    return
  fi

  # Make the indentation
  local i=0
  local padding=""
  for ((i; i < depth; i++)); do
    padding+=$'\t'
  done

  # Loop through all items in the current directory
  local item
  for item in "$dir"/*; do
    if [ -d "$item" ]; then

      # Calculate the size (ignore errors)
      local size
      size=$(du -sh "$item" 2>/dev/null | awk '{print $1}')

      # Determine the color
      local color
      color=$(_get_color_code "$size")

      # Format the path for display
      local display_path
      display_path=$(echo "$item" | sed 's/^\.\///')

      # Print the colored output: the color is set at the beginning of the line
      # and reset at the end with ${NC}.
      echo -e "${color}${size}\t$padding$display_path${NC}"

      # Recursive call for the subdirectory
      _list_dirs_recursively "$item" $((depth + 1)) "$max_depth"
    fi
  done
}

# Determine start directory, default to current directory
START_DIR="${1:-.}"

# Determine max depth if provided, default to only the first level
MAX_DEPTH="${2:-0}"

echo -e "Legend: ${RED}Red = Gigabytes+${NC}, ${YELLOW}Yellow = Megabytes+${NC}"
echo -e "Directory tree with sizes (starting from \"$START_DIR\"):"

# Start the recursive listing
_list_dirs_recursively "$START_DIR" 0 "$MAX_DEPTH"
