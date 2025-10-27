#!/bin/bash

# ANSI Kleurcodes
RED='\033[0;31m'    # Voor mappen met Gigabytes (G)
YELLOW='\033[1;33m' # Voor mappen met Megabytes (M)
NC='\033[0m'       # Geen Kleur (reset)

# Functie om de kleurcode te bepalen op basis van de grootte-string
function get_color_code() {
  local size_str="$1"

  # Ruwe schatting voor kleurcodering:
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

# Functie om de directory recursief te verwerken
# Argumenten: $1 = pad, $2 = huidige diepte, $3 = max. diepte
function list_dirs_recursively() {
  local dir="$1"
  local depth="$2"
  local max_depth="$3"

  # Controleer de diepte: stop als we de max_depth bereikt hebben
  if [ -n "$max_depth" ] && [ "$depth" -gt "$max_depth" ]; then
    return
  fi

  # Maak de inspringing
  local padding=""
  for ((i = 0; i < depth; i++)); do
    padding+=$'\t'
  done

  # Loop door alle items in de huidige map
  for item in "$dir"/*; do
    if [ -d "$item" ]; then

      # Bereken de grootte (fouten negeren)
      local size=$(du -sh "$item" 2>/dev/null | awk '{print $1}')

      # Bepaal de kleur
      local color=$(get_color_code "$size")

      # Pad opmaken voor weergave
      local display_path=$(echo "$item" | sed 's/^\.\///')

      # Print de gekleurde output: de kleur wordt aan het begin van de regel gezet
      # en gereset aan het einde met ${NC}.
      echo -e "${color}${size}\t$padding$display_path${NC}"

      # Recursieve aanroep voor de submap
      list_dirs_recursively "$item" $((depth + 1)) "$max_depth"
    fi
  done
}

# ----------------------------------------------------------------------
# HOOFDLOGICA: Verwerk de input (pad en optionele diepte)
# ----------------------------------------------------------------------

# Bepaal de START_DIR (standaard is '.')
START_DIR="${1:-.}"

# Bepaal de MAX_DEPTH
MAX_DEPTH="$2"

echo -e "Directory boom met groottes (vanaf $START_DIR):"
echo -e "Legenda: ${RED}Rood = Gigabytes+${NC}, ${YELLOW}Geel = Megabytes+${NC}"

# Start de recursie
list_dirs_recursively "$START_DIR" 0 "$MAX_DEPTH"