#!/bin/bash

#######################################
# WordPress Image to WebP Converter
# Converteert naar WebP maar behoudt originele bestandsnaam
# example.jpg blijft example.jpg maar bevat WebP data
#######################################

# Configuratie
WP_CONTENT_DIR="${1:-/var/www/html/wp-content}"
QUALITY=${QUALITY:-85}    # WebP kwaliteit (0-100) - kan via env var worden gezet
DRY_RUN=${DRY_RUN:-false} # Set to true voor testrun - kan via env var worden gezet
BACKUP_DIR="${WP_CONTENT_DIR}/webp_backup_$(date +%Y%m%d_%H%M%S)"
CREATE_BACKUP=${CREATE_BACKUP:-true} # Maak backup van originelen - kan via env var worden gezet
LOG_FILE="webp_conversion_$(date +%Y%m%d_%H%M%S).log"
PARALLEL_JOBS=${PARALLEL_JOBS:-4} # Aantal parallelle conversies - kan via env var worden gezet
AUTO_YES=${AUTO_YES:-false} # Skip confirmation prompt - kan via env var worden gezet

# Kleuren voor output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#######################################
# Functies
#######################################

log() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
  echo "[ERROR] $1" >> "$LOG_FILE"
}

success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
  echo "[SUCCESS] $1" >> "$LOG_FILE"
}

warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
  echo "[WARNING] $1" >> "$LOG_FILE"
}

# Check of benodigde tools geïnstalleerd zijn
check_dependencies() {
  log "Controleren van afhankelijkheden..."

  local missing_deps=()

  if ! command -v cwebp &>/dev/null; then
    missing_deps+=("cwebp")
  fi

  if ! command -v gif2webp &>/dev/null; then
    missing_deps+=("gif2webp")
  fi

  if [ ${#missing_deps[@]} -gt 0 ]; then
    error "Missende afhankelijkheden: ${missing_deps[*]}"
    echo ""
    echo "Installeer met:"
    echo "  Ubuntu/Debian: sudo apt-get install webp"
    echo "  CentOS/RHEL:   sudo yum install libwebp-tools"
    echo "  macOS:         brew install webp"
    exit 1
  fi

  success "Alle benodigde tools zijn geïnstalleerd"
}

# Maak backup van origineel bestand
backup_file() {
  local file="$1"

  if [ "$CREATE_BACKUP" = false ]; then
    return 0
  fi

  # Bepaal relatief pad binnen wp-content
  local rel_path="${file#$WP_CONTENT_DIR/}"
  local backup_path="$BACKUP_DIR/$rel_path"
  local backup_subdir=$(dirname "$backup_path")

  # Maak backup directory structuur
  mkdir -p "$backup_subdir"

  # Kopieer bestand naar backup
  if cp -p "$file" "$backup_path"; then
    return 0
  else
    error "Backup maken mislukt: $file"
    return 1
  fi
}

# Converteer JPG/PNG naar WebP maar behoud originele bestandsnaam
convert_static_image() {
  local input_file="$1"
  local temp_webp="${input_file}.temp.webp"

  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] Zou converteren: $input_file (behoudt naam, WebP formaat)"
    return 0
  fi

  # Maak eerst backup
  if ! backup_file "$input_file"; then
    error "Kan geen backup maken, skip: $input_file"
    return 1
  fi

  # Converteer naar WebP (tijdelijk bestand) - suppress output maar show errors
  if ! cwebp -q $QUALITY "$input_file" -o "$temp_webp" 2>&1 | grep -E "^Error|^Warning" >&2; then
    local convert_status=${PIPESTATUS[0]}
    if [ $convert_status -ne 0 ]; then
      error "✗ Conversie mislukt: $(basename "$input_file")"
      rm -f "$temp_webp"
      return 1
    fi
  fi

  # Bereken besparing VOOR we het origineel overschrijven
  local original_size=$(stat -f%z "$input_file" 2>/dev/null || stat -c%s "$input_file" 2>/dev/null)
  local webp_size=$(stat -f%z "$temp_webp" 2>/dev/null || stat -c%s "$temp_webp" 2>/dev/null)
  local savings=$(((original_size - webp_size) * 100 / original_size))

  # Overschrijf origineel met WebP data (behoudt originele naam!)
  if ! mv "$temp_webp" "$input_file"; then
    error "✗ Overschrijven mislukt: $(basename "$input_file")"
    rm -f "$temp_webp"
    return 1
  fi

  success "✓ $(basename "$input_file") -> WebP formaat (${savings}% kleiner)"
  echo "$(basename "$input_file")|$original_size|$webp_size|$savings" >>"${LOG_FILE}.stats"

  return 0
}

# Converteer GIF naar WebP (behoudt animatie) maar behoud originele bestandsnaam
convert_gif_image() {
  local input_file="$1"
  local temp_webp="${input_file}.temp.webp"

  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] Zou converteren: $input_file (behoudt naam, WebP formaat, animated)"
    return 0
  fi

  # Maak eerst backup
  if ! backup_file "$input_file"; then
    error "Kan geen backup maken, skip: $input_file"
    return 1
  fi

  # Converteer GIF naar WebP (tijdelijk bestand) - suppress output maar show errors
  if ! gif2webp -q $QUALITY "$input_file" -o "$temp_webp" 2>&1 | grep -E "^Error|^Warning" >&2; then
    local convert_status=${PIPESTATUS[0]}
    if [ $convert_status -ne 0 ]; then
      error "✗ Conversie mislukt: $(basename "$input_file")"
      rm -f "$temp_webp"
      return 1
    fi
  fi

  # Bereken besparing VOOR we het origineel overschrijven
  local original_size=$(stat -f%z "$input_file" 2>/dev/null || stat -c%s "$input_file" 2>/dev/null)
  local webp_size=$(stat -f%z "$temp_webp" 2>/dev/null || stat -c%s "$temp_webp" 2>/dev/null)
  local savings=$(((original_size - webp_size) * 100 / original_size))

  # Overschrijf origineel met WebP data (behoudt originele naam!)
  if ! mv "$temp_webp" "$input_file"; then
    error "✗ Overschrijven mislukt: $(basename "$input_file")"
    rm -f "$temp_webp"
    return 1
  fi

  success "✓ $(basename "$input_file") -> WebP/Animated formaat (${savings}% kleiner)"
  echo "$(basename "$input_file")|$original_size|$webp_size|$savings" >>"${LOG_FILE}.stats"

  return 0
}

#######################################
# Main Script
#######################################

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  WordPress Image to WebP Converter"
echo "  (Behoudt originele bestandsnamen)"
echo "════════════════════════════════════════════════════════════"
echo ""

# Controleer of directory bestaat
if [ ! -d "$WP_CONTENT_DIR" ]; then
  error "Directory niet gevonden: $WP_CONTENT_DIR"
  exit 1
fi

log "Configuratie:"
log "  WP Content Dir: $WP_CONTENT_DIR"
log "  Kwaliteit:      $QUALITY"
log "  Dry Run:        $DRY_RUN"
log "  Backup maken:   $CREATE_BACKUP"
if [ "$CREATE_BACKUP" = true ]; then
  log "  Backup locatie: $BACKUP_DIR"
fi
log "  Log bestand:    $LOG_FILE"
log "  Parallelle jobs: $PARALLEL_JOBS"
echo ""

# Check dependencies
check_dependencies
echo ""

# Uitleg en waarschuwing
log "Deze conversie:"
log "  ✓ Behoudt de originele bestandsnaam (example.jpg blijft example.jpg)"
log "  ✓ Vervangt de inhoud met WebP formaat"
log "  ✓ WordPress hoeft NIET aangepast te worden"
log "  ✓ Moderne browsers herkennen WebP aan de file signature"
echo ""

if [ "$CREATE_BACKUP" = true ]; then
  success "✓ Backup wordt gemaakt in: $BACKUP_DIR"
else
  warning "✗ GEEN backup wordt gemaakt!"
fi
echo ""

# Skip interactive prompt als we niet interactief zijn (SSH/pipe), in dry-run mode, of AUTO_YES is gezet
if [ "$DRY_RUN" = false ] && [ "$AUTO_YES" = false ]; then
  # Check of we in een interactieve shell zitten
  if [ -t 0 ]; then
    read -p "Doorgaan met conversie? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
      log "Geannuleerd door gebruiker"
      exit 0
    fi
  else
    # Niet-interactief (SSH/pipe), ga automatisch door
    log "Niet-interactieve modus gedetecteerd - ga automatisch door met conversie"
    echo ""
  fi
elif [ "$AUTO_YES" = true ]; then
  log "Auto-proceed modus - conversie start direct"
  echo ""
fi

# Maak backup directory
if [ "$CREATE_BACKUP" = true ] && [ "$DRY_RUN" = false ]; then
  mkdir -p "$BACKUP_DIR"
  log "Backup directory aangemaakt: $BACKUP_DIR"
fi

# Maak stats file aan
if [ "$DRY_RUN" = false ]; then
  echo "# Filename|OriginalSize|WebPSize|SavingsPercent" >"${LOG_FILE}.stats"
fi

echo ""
log "Zoeken naar afbeeldingen..."
echo ""

# Tellers
total_jpg=0
total_png=0
total_gif=0
converted_count=0
error_count=0
total_original_size=0
total_webp_size=0

# Export functies voor parallel gebruik
export -f convert_static_image convert_gif_image backup_file log success error warning
export QUALITY DRY_RUN CREATE_BACKUP BACKUP_DIR LOG_FILE WP_CONTENT_DIR
export RED GREEN YELLOW BLUE NC

# Wrapper functie voor parallelle verwerking met counters
process_image() {
  local file="$1"
  local type="$2"

  if [ "$type" = "gif" ]; then
    convert_gif_image "$file"
  else
    convert_static_image "$file"
  fi

  return $?
}
export -f process_image

# Check of parallel beschikbaar is, anders gebruik xargs
USE_PARALLEL=false
if command -v parallel &>/dev/null; then
  USE_PARALLEL=true
  log "GNU Parallel gedetecteerd - gebruik maken van parallelle verwerking"
else
  log "GNU Parallel niet beschikbaar - gebruik maken van xargs voor parallelle verwerking"
fi

# Converteer JPG bestanden
log "═══ Converteren van JPG bestanden ═══"

# Tel JPG bestanden
total_jpg=$(find "$WP_CONTENT_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" \) | wc -l | tr -d ' ')

if [ "$total_jpg" -gt 0 ]; then
  log "Gevonden: $total_jpg JPG bestanden"
  echo ""

  if [ "$USE_PARALLEL" = true ]; then
    # Gebruik GNU parallel voor betere output
    find "$WP_CONTENT_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" \) -print0 | \
      parallel -0 -j "$PARALLEL_JOBS" --line-buffer process_image {} "static"
  else
    # Gebruik xargs met line-by-line processing
    find "$WP_CONTENT_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" \) -print0 | \
      xargs -0 -n 1 -P "$PARALLEL_JOBS" -I {} bash -c 'process_image "$@"' _ {}
  fi

  converted_count=$((converted_count + total_jpg))
else
  log "Geen JPG bestanden gevonden"
fi
echo ""

# Converteer PNG bestanden
log "═══ Converteren van PNG bestanden ═══"

# Tel PNG bestanden
total_png=$(find "$WP_CONTENT_DIR" -type f -iname "*.png" | wc -l | tr -d ' ')

if [ "$total_png" -gt 0 ]; then
  log "Gevonden: $total_png PNG bestanden"
  echo ""

  if [ "$USE_PARALLEL" = true ]; then
    find "$WP_CONTENT_DIR" -type f -iname "*.png" -print0 | \
      parallel -0 -j "$PARALLEL_JOBS" --line-buffer process_image {} "static"
  else
    find "$WP_CONTENT_DIR" -type f -iname "*.png" -print0 | \
      xargs -0 -n 1 -P "$PARALLEL_JOBS" -I {} bash -c 'process_image "$@"' _ {}
  fi

  converted_count=$((converted_count + total_png))
else
  log "Geen PNG bestanden gevonden"
fi
echo ""

# Converteer GIF bestanden
log "═══ Converteren van GIF bestanden ═══"

# Tel GIF bestanden
total_gif=$(find "$WP_CONTENT_DIR" -type f -iname "*.gif" | wc -l | tr -d ' ')

if [ "$total_gif" -gt 0 ]; then
  log "Gevonden: $total_gif GIF bestanden"
  echo ""

  if [ "$USE_PARALLEL" = true ]; then
    find "$WP_CONTENT_DIR" -type f -iname "*.gif" -print0 | \
      parallel -0 -j "$PARALLEL_JOBS" --line-buffer process_image {} "gif"
  else
    find "$WP_CONTENT_DIR" -type f -iname "*.gif" -print0 | \
      xargs -0 -n 1 -P "$PARALLEL_JOBS" -I {} bash -c 'process_image "$@"' _ {}
  fi

  converted_count=$((converted_count + total_gif))
else
  log "Geen GIF bestanden gevonden"
fi
echo ""

# Bereken totale besparing
if [ -f "${LOG_FILE}.stats" ] && [ "$DRY_RUN" = false ]; then
  while IFS='|' read -r filename original_size webp_size savings; do
    if [[ "$filename" != "#"* ]]; then
      total_original_size=$((total_original_size + original_size))
      total_webp_size=$((total_webp_size + webp_size))
    fi
  done <"${LOG_FILE}.stats"

  if [ $total_original_size -gt 0 ]; then
    total_savings=$(((total_original_size - total_webp_size) * 100 / total_original_size))
    total_saved_mb=$(echo "scale=2; ($total_original_size - $total_webp_size) / 1024 / 1024" | bc)
  fi
fi

# Samenvatting
echo ""
echo "════════════════════════════════════════════════════════════"
log "Conversie voltooid!"
echo "════════════════════════════════════════════════════════════"
log "Totaal gevonden:"
log "  JPG:  $total_jpg"
log "  PNG:  $total_png"
log "  GIF:  $total_gif"
log "  Totaal: $((total_jpg + total_png + total_gif))"
echo ""
log "Resultaten:"
log "  Succesvol: $converted_count"
log "  Fouten:    $error_count"
echo ""

if [ -n "$total_saved_mb" ] && [ "$DRY_RUN" = false ]; then
  log "Totale besparing:"
  log "  Percentage: ${total_savings}%"
  log "  Ruimte:     ${total_saved_mb} MB"
  echo ""
fi

if [ "$CREATE_BACKUP" = true ] && [ "$DRY_RUN" = false ]; then
  success "✓ Backup van originelen: $BACKUP_DIR"
fi

log "✓ Conversie log: $LOG_FILE"
if [ "$DRY_RUN" = false ]; then
  log "✓ Statistieken: ${LOG_FILE}.stats"
fi
echo ""

if [ "$DRY_RUN" = false ]; then
  echo ""
  warning "═══ BELANGRIJK ═══"
  echo ""
  log "1. Test je website grondig!"
  log "2. Check of afbeeldingen correct worden weergegeven"
  log "3. Clear browser cache en WordPress cache"
  log "4. Test op verschillende browsers"
  echo ""
  log "5. Als alles werkt, kun je de backup verwijderen:"
  log "   rm -rf $BACKUP_DIR"
  echo ""
  success "Geen database wijzigingen nodig - WordPress blijft gewoon werken!"
  echo ""
fi

exit 0
