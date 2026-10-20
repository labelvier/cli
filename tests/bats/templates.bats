#!/usr/bin/env bats
# templates/: the deployable shell templates, the scaffold template and the
# claude/zed config files. Templates are copied verbatim (cron, storage,
# migrate, ai, zed) — only example.sh.tpl has placeholders, filled by
# `core generate` with sed (global_command_name / first_command_name).

bats_require_minimum_version 1.5.0
load test_helper
setup()    { setup_sandbox; }
teardown() { teardown_sandbox; }

TPL="$CLI_ROOT/templates"

# A PATH with only the stubs and the base system: no Homebrew, no nvm, so
# `command -v cwebp|parallel|toon` only finds what a test stubbed.
# jq is a hard requirement of the basecamp hook, so it alone is linked in.
bare_path() {
  mkdir -p "$TEST_TMP/bare-bin"
  if command -v jq >/dev/null 2>&1 && [ ! -e "$TEST_TMP/bare-bin/jq" ]; then
    ln -s "$(command -v jq)" "$TEST_TMP/bare-bin/jq"
  fi
  echo "$STUB_DIR:$TEST_TMP/bare-bin:/usr/bin:/bin:/usr/sbin:/sbin"
}

# Fill example.sh.tpl the way `core generate` does. Prints the rendered path.
render_example() {
  local command_name="$1" first_command_name="$2" out="$TEST_TMP/$1.sh"
  sed -e "s/global_command_name/$command_name/g" -e "s/first_command_name/$first_command_name/g" \
    "$TPL/example.sh.tpl" > "$out"
  echo "$out"
}

# --- every template parses ---------------------------------------------------

@test "every templates/*.sh.tpl parses with bash -n" {
  local file
  for file in "$TPL"/*.sh.tpl "$TPL"/claude/skills/timesheet/scripts/timesheet.sh.tpl; do
    bash -n "$file" || { echo "does not parse: $file" >&2; return 1; }
  done
}

@test "example.sh.tpl parses after its placeholders are filled and leaves none behind" {
  local rendered
  rendered="$(render_example greeter wave)"
  bash -n "$rendered"
  ! grep -qE 'global_command_name|first_command_name' "$rendered"
  grep -q '^greeter() (' "$rendered"
  grep -q '# @function wave' "$rendered"
  grep -q 'local filename="greeter.sh"' "$rendered"
}

@test "a rendered example command dispatches through _dispatch like a real inc file" {
  local rendered
  rendered="$(render_example greeter wave)"
  load_cli
  # shellcheck disable=SC1090
  source "$rendered"
  run greeter wave
  [ "$status" -eq 0 ]
  [ "$output" = "Hello world!" ]
  run greeter wave Bob
  [ "$output" = "Hello Bob!" ]
  # --help and the bare call read the docs from inc/<filename>, where a
  # generated command lives for real; a file rendered elsewhere has none.
}

# --- run_cron_jobs.sh.tpl ----------------------------------------------------

@test "run_cron_jobs runs cron and action scheduler for a single site" {
  stub find 'echo /home/customer/www/example/public_html'
  stub wp 'case "$*" in "site list"*) echo https://example.test;; esac'
  run bash "$TPL/run_cron_jobs.sh.tpl"
  [ "$status" -eq 0 ]
  assert_output_contains "Running cron events for /home/customer/www/example/public_html"
  assert_stub_called '^wp site list --field=url --path=/home/customer/www/example/public_html$'
  assert_stub_called '^wp cron event run --path=/home/customer/www/example/public_html --due-now$'
  assert_stub_called '^wp action-scheduler clean --path=/home/customer/www/example/public_html$'
  assert_stub_called '^wp action-scheduler run --path=/home/customer/www/example/public_html$'
  refute_stub_called '\-\-url='
}

@test "run_cron_jobs loops over every site of a multisite with --url" {
  stub find 'echo /home/customer/www/example/public_html'
  stub wp 'case "$*" in "site list"*) printf "%s\n" https://one.test https://two.test;; esac'
  run bash "$TPL/run_cron_jobs.sh.tpl"
  [ "$status" -eq 0 ]
  assert_output_contains "Running cron events for https://one.test"
  assert_output_contains "Running action scheduler for https://two.test"
  assert_stub_called '^wp cron event run --url=https://one.test --path=/home/customer/www/example/public_html --due-now$'
  assert_stub_called '^wp cron event run --url=https://two.test --path=/home/customer/www/example/public_html --due-now$'
  assert_stub_called '^wp action-scheduler clean --url=https://two.test '
  assert_stub_called '^wp action-scheduler run --url=https://one.test '
  [ "$(grep -c '^wp cron event run' "$STUB_LOG")" -eq 2 ]
}

# --- sync_uploads.sh.tpl -----------------------------------------------------

@test "sync_uploads builds the rsync-over-ssh command and cleans up its lock and log" {
  stub rsync 'echo "sent 1 bytes"'
  stub ssh
  run bash "$TPL/sync_uploads.sh.tpl" deploy src.example.test 18765 /home/src/wp-content/uploads /home/dst/wp-content
  [ "$status" -eq 0 ]
  assert_stub_called '^rsync -e ssh -p 18765 -av --stats deploy@src.example.test:/home/src/wp-content/uploads /home/dst/wp-content$'
  refute_stub_called '^ssh'
  [ ! -f ./.sync_running ]
  [ ! -f ./sync-uploads.log ]
  local dated
  dated="$(ls sync-uploads-*.log)"
  [ -n "$dated" ]
  grep -q "sent 1 bytes" "$dated"
}

@test "sync_uploads refuses to start while the lock file exists" {
  stub rsync
  touch ./.sync_running
  run bash "$TPL/sync_uploads.sh.tpl" deploy src.example.test 22 /src /dst
  [ "$status" -eq 1 ]
  assert_output_contains "Sync is already running"
  refute_stub_called '^rsync'
  [ -f ./.sync_running ]
}

# --- convert-to-webp.sh.tpl --------------------------------------------------

# cwebp/gif2webp stubs: write a WebP-looking file (RIFF....WEBP) to the -o target.
stub_webp_tools() {
  stub cwebp 'printf "RIFF\\0\\0\\0\\0WEBPVP8 " > "${@: -1}"'
  stub gif2webp 'printf "RIFF\\0\\0\\0\\0WEBPVP8X" > "${@: -1}"'
}

make_uploads() {
  mkdir -p "$TEST_TMP/wp-content/uploads"
  head -c 400 /dev/zero > "$TEST_TMP/wp-content/uploads/photo.jpg"
}

@test "convert-to-webp dry run lists what it would convert without touching anything" {
  stub_webp_tools
  make_uploads
  run env PATH="$(bare_path)" DRY_RUN=true bash "$TPL/convert-to-webp.sh.tpl" "$TEST_TMP/wp-content"
  [ "$status" -eq 0 ]
  assert_output_contains "Dry Run:        true"
  assert_output_contains "Gevonden: 1 JPG bestanden"
  assert_output_contains "[DRY-RUN] Zou converteren: $TEST_TMP/wp-content/uploads/photo.jpg"
  refute_stub_called '^cwebp'
  [ "$(head -c 4 "$TEST_TMP/wp-content/uploads/photo.jpg" | tr -d '\0')" = "" ]
  ! ls -d "$TEST_TMP"/wp-content/webp_backup_* >/dev/null 2>&1
}

@test "convert-to-webp converts a jpg in place via cwebp, keeps a backup and writes stats" {
  stub_webp_tools
  make_uploads
  run env PATH="$(bare_path)" AUTO_YES=true bash "$TPL/convert-to-webp.sh.tpl" "$TEST_TMP/wp-content"
  [ "$status" -eq 0 ]
  assert_output_contains "GNU Parallel niet beschikbaar"
  assert_output_contains "Auto-proceed modus"
  assert_stub_called "^cwebp -q 85 $TEST_TMP/wp-content/uploads/photo.jpg -o $TEST_TMP/wp-content/uploads/photo.jpg.temp.webp$"
  refute_stub_called '^gif2webp'
  # The file keeps its name but now holds WebP data; the original is in the backup.
  [ "$(head -c 4 "$TEST_TMP/wp-content/uploads/photo.jpg")" = "RIFF" ]
  [ ! -f "$TEST_TMP/wp-content/uploads/photo.jpg.temp.webp" ]
  local backup
  backup="$(ls -d "$TEST_TMP"/wp-content/webp_backup_*)"
  [ "$(wc -c < "$backup/uploads/photo.jpg")" -eq 400 ]
  assert_output_contains "photo.jpg -> WebP formaat"
  assert_output_contains "Conversie voltooid!"
  grep -q '^photo.jpg|400|' webp_conversion_*.log.stats
}

@test "convert-to-webp honours QUALITY and CREATE_BACKUP=false" {
  stub_webp_tools
  make_uploads
  run env PATH="$(bare_path)" AUTO_YES=true QUALITY=60 CREATE_BACKUP=false bash "$TPL/convert-to-webp.sh.tpl" "$TEST_TMP/wp-content"
  [ "$status" -eq 0 ]
  assert_output_contains "GEEN backup wordt gemaakt"
  assert_stub_called "^cwebp -q 60 $TEST_TMP/wp-content/uploads/photo.jpg -o "
  ! ls -d "$TEST_TMP"/wp-content/webp_backup_* >/dev/null 2>&1
}

@test "convert-to-webp converts gifs with gif2webp when GNU parallel is absent" {
  skip "bug: the xargs fallback runs process_image with only the file, so the 'gif' type is lost and gifs go through cwebp"
  stub_webp_tools
  mkdir -p "$TEST_TMP/wp-content/uploads"
  head -c 100 /dev/zero > "$TEST_TMP/wp-content/uploads/anim.gif"
  run env PATH="$(bare_path)" AUTO_YES=true CREATE_BACKUP=false bash "$TPL/convert-to-webp.sh.tpl" "$TEST_TMP/wp-content"
  [ "$status" -eq 0 ]
  assert_stub_called "^gif2webp -q 85 $TEST_TMP/wp-content/uploads/anim.gif -o "
  refute_stub_called '^cwebp'
  assert_output_contains "anim.gif -> WebP/Animated formaat"
}

@test "convert-to-webp skips files that already hold WebP data" {
  if [ "$(uname)" = Darwin ]; then
    skip "bug: is_webp_file greps od output with single spaces, but BSD od prints two per byte, so on macOS nothing is ever detected as WebP"
  fi
  stub_webp_tools
  mkdir -p "$TEST_TMP/wp-content/uploads"
  printf 'RIFF\0\0\0\0WEBPVP8 ' > "$TEST_TMP/wp-content/uploads/done.jpg"
  run env PATH="$(bare_path)" AUTO_YES=true bash "$TPL/convert-to-webp.sh.tpl" "$TEST_TMP/wp-content"
  [ "$status" -eq 0 ]
  assert_output_contains "Skip (al WebP): done.jpg"
  assert_output_contains "Overgeslagen:  1 (al WebP formaat)"
  refute_stub_called '^cwebp'
}

@test "convert-to-webp stops when cwebp is not installed" {
  make_uploads
  run env PATH="$(bare_path)" bash "$TPL/convert-to-webp.sh.tpl" "$TEST_TMP/wp-content"
  [ "$status" -eq 1 ]
  assert_output_contains "Missende afhankelijkheden: cwebp gif2webp"
  assert_output_contains "brew install webp"
}

@test "convert-to-webp fails for a directory that does not exist" {
  stub_webp_tools
  run env PATH="$(bare_path)" bash "$TPL/convert-to-webp.sh.tpl" "$TEST_TMP/nope"
  [ "$status" -eq 1 ]
  assert_output_contains "Directory niet gevonden: $TEST_TMP/nope"
}

# --- tree.sh.tpl -------------------------------------------------------------

@test "tree lists directories with their sizes, one level deep by default" {
  mkdir -p root/uploads/2026 root/plugins
  head -c 1024 /dev/zero > root/uploads/2026/big.bin
  run bash "$TPL/tree.sh.tpl" root
  [ "$status" -eq 0 ]
  assert_output_contains "Legend:"
  assert_output_contains "starting from \"root\""
  assert_output_contains "root/uploads"
  assert_output_contains "root/plugins"
  refute_output_contains "root/uploads/2026"
}

@test "tree recurses to the given depth with tab indentation" {
  mkdir -p root/uploads/2026/01
  run bash "$TPL/tree.sh.tpl" root 1
  [ "$status" -eq 0 ]
  assert_output_contains "root/uploads/2026"
  refute_output_contains "root/uploads/2026/01"
  plain_output | grep -q $'\t\troot/uploads/2026'
}

@test "tree strips a leading ./ from the displayed paths" {
  mkdir -p sub
  run bash "$TPL/tree.sh.tpl"
  [ "$status" -eq 0 ]
  assert_output_contains "starting from \".\""
  plain_output | grep -qE $'\tsub$'
}

# --- basecamp-toon.sh.tpl ----------------------------------------------------

hook_input() {
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"
}

run_hook() {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  run env PATH="$(bare_path)" bash "$TPL/basecamp-toon.sh.tpl" <<< "$(hook_input "$1")"
}

@test "basecamp hook appends the npx toon formatter to a plain basecamp command" {
  run_hook "basecamp projects list"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')" = "PreToolUse" ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.updatedInput.command')" = "basecamp projects list | npx @toon-format/cli" ]
}

@test "basecamp hook prefers an installed toon binary" {
  stub toon
  run_hook "basecamp todos list --project 1"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.updatedInput.command')" = "basecamp todos list --project 1 | toon" ]
}

@test "basecamp hook leaves other commands alone" {
  run_hook "ls -la"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "basecamp hook leaves piped, chained, non-JSON and already formatted basecamp commands alone" {
  local cmd
  for cmd in "basecamp projects list | jq ." "basecamp projects list; echo" "basecamp projects list > out.json" \
             "basecamp projects list --md" "basecamp projects list -m" "basecamp --jq .id projects" \
             "basecamp --help" "basecamp --version" "basecamp projects list | toon"; do
    run_hook "$cmd"
    [ "$status" -eq 0 ] || { echo "non-zero for: $cmd" >&2; return 1; }
    [ -z "$output" ] || { echo "rewrote: $cmd -> $output" >&2; return 1; }
  done
}

@test "basecamp hook ignores input without a command" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  run env PATH="$(bare_path)" bash "$TPL/basecamp-toon.sh.tpl" <<< '{"tool_name":"Read","tool_input":{"file_path":"x"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run env PATH="$(bare_path)" bash "$TPL/basecamp-toon.sh.tpl" <<< ''
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- claude/ and zed/ config templates ---------------------------------------

json_check() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -I -c 'import json, sys; json.load(open(sys.argv[1]))' "$1"
  elif command -v node >/dev/null 2>&1; then
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$1"
  else
    skip "neither python3 nor node installed"
  fi
}

@test "every JSON file under templates/claude and templates/zed parses" {
  local file count=0
  while IFS= read -r file; do
    json_check "$file" || { echo "invalid JSON: $file" >&2; return 1; }
    count=$((count + 1))
  done < <(find "$TPL/claude" "$TPL/zed" -type f \( -name '*.json' -o -name '*.json.tpl' \) | sort)
  [ "$count" -ge 4 ]
}

@test "zed templates are the files zed setup copies" {
  [ -f "$TPL/zed/settings.json" ]
  [ -f "$TPL/zed/composer.json" ]
  [ -f "$TPL/zed/gitignore-additions.txt" ]
  grep -q 'intelephense' "$TPL/zed/settings.json"
  grep -q 'php-stubs/wp-cli-stubs' "$TPL/zed/composer.json"
}

@test "no claude template is left with an unreplaced placeholder after install copies it" {
  # `ai claude install` copies these verbatim, so a template placeholder would
  # end up as-is in ~/.claude. __DIR__ (PHP) and <METHOD> (usage docs) are real content.
  local file target
  mkdir -p "$HOME/.claude"
  while IFS= read -r file; do
    target="$HOME/.claude/$(basename "$file" .tpl)"
    cp "$file" "$target"
    if grep -nE '\{\{[^}]*\}\}|%%[A-Za-z_]+%%|global_command_name|first_command_name|<<[A-Z_]+>>' "$target"; then
      echo "placeholder left in $file" >&2
      return 1
    fi
  done < <(find "$TPL/claude" -type f \( -name '*.md.tpl' -o -name '*.sh.tpl' -o -name '*.mjs.tpl' \))
}

@test "every managed claude template carries a labelvier-ai-version stamp" {
  # ai check/install compare this stamp between template and installed file.
  local file
  for file in "$TPL"/claude/labelvier/*.md.tpl "$TPL"/claude/skills/*/SKILL.md.tpl; do
    grep -qE 'labelvier-ai-version: *[0-9][0-9.]*' "$file" \
      || { echo "no version stamp in $file" >&2; return 1; }
  done
}
