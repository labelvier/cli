#!/usr/bin/env bats
# inc/migrate.sh: migrate a WordPress site from a VPS to SiteGround over ssh, and local -> staging.
#
# migrate keeps its state in $__dir/.migration and $__dir/migration_profiles, where
# $__dir is the CLI checkout. Going through the real entry point would write into
# the repo, so every stateful test loads the functions with load_cli and points
# __dir at the sandbox first. Only the docs/help tests use run_cli.

load test_helper
setup() {
  setup_sandbox
  load_cli
  __dir="$TEST_TMP/cli"
  mkdir -p "$__dir"
  CONFIG="$__dir/.migration"
  PROFILES="$__dir/migration_profiles"
  SRC="srcuser@src.example.com"
  DST="dstuser@c125667.sgvps.net"
  DST_PATH="www/new.example.com/public_html"
}
teardown() { teardown_sandbox; }

# Succeeds when the stub log contains a line matching each pattern, in this order.
assert_calls_in_order() {
  local last=0 n pattern
  for pattern in "$@"; do
    n=$(grep -nE -- "$pattern" "$STUB_LOG" | awk -F: -v last="$last" '$1 > last {print $1; exit}')
    if [ -z "$n" ]; then
      echo "expected a stub call after line $last matching: $pattern" >&2
      echo "recorded calls:" >&2
      cat "$STUB_LOG" >&2
      return 1
    fi
    last=$n
  done
}

# A complete migration config / profile, as `start` writes it. $1 = file.
write_migration_config() {
  cat > "$1" <<EOF
ssh_username=srcuser
ssh_hostname=src.example.com
ssh_port=22
ssh_path=wordpress/current
ssh_domain_destination=new.example.com
ssh_username_destination=dstuser
ssh_hostname_destination=c125667.sgvps.net
ssh_port_destination=18765
ssh_path_destination=www/new.example.com/public_html
EOF
}

# ssh that plays both servers for a full migration run. Tunable through
# MIGRATE_TEST_MULTISITE (0/1), MIGRATE_TEST_SUBDOMAIN (0/1) and
# MIGRATE_TEST_INACTIVE (space separated inactive plugins on the destination).
stub_migration_ssh() {
  stub ssh '
eval "cmd=\${$#}"
case "$cmd" in
  *"ls .ssh/id_ed25519.pub"*) exit "${MIGRATE_TEST_NO_DEST_KEY:-0}" ;;
  *"cat .ssh/id_ed25519.pub"*) echo "ssh-ed25519 AAAA dest@c125667" ;;
  *"grep -q"*"authorized_keys"*) exit "${MIGRATE_TEST_KEY_MISSING:-0}" ;;
  *"--version"*) echo "WP-CLI 2.10.0" ;;
  *"option get siteurl"*) echo "https://old.example.com" ;;
  *"config get table_prefix"*) echo "wp_" ;;
  *"config get MULTISITE"*) echo "${MIGRATE_TEST_MULTISITE:-0}" ;;
  *"config get SUBDOMAIN_INSTALL"*) echo "${MIGRATE_TEST_SUBDOMAIN:-0}" ;;
  *"config list --format=csv --path=www/"*) printf "name,value,type\nDB_NAME,dst,constant\nWP_DEBUG,false,constant\n" ;;
  *"config list --format=csv"*) printf "name,value,type\nDB_NAME,src,constant\nWP_DEBUG,false,constant\nCUSTOM_URL,https://old.example.com/x,constant\n" ;;
  *"grep -o"*"ini_set"*) exit 1 ;;
  *"grep -o"*"WP_DEBUG"*) echo "define( '"'"'WP_DEBUG'"'"', false )" ;;
  *"plugin status warpdrive"*) echo "Status: Active" ;;
  *"plugin list --field=name"*) echo "wordpress-starter" ;;
  *"plugin list --status=inactive"*) echo "${MIGRATE_TEST_INACTIVE-akismet sg-cachepress}" ;;
  *"site list"*)
    if [ "${MIGRATE_TEST_MULTISITE:-0}" = "1" ]; then echo "1 old.example.com /"; else echo "Error: This is not a multisite installation."; fi ;;
  *"cat www/"*".htaccess"*) printf "# BEGIN WordPress\nRewriteEngine On\n# END WordPress\nAddType image/webp .webp\n" ;;
esac
exit 0'
  stub scp
  stub ssh-copy-id
}

# --- docs & help ------------------------------------------------------------

@test "bare migrate prints its functions" {
  run_cli migrate
  assert_output_contains "Available functions:"
  assert_output_contains "load"
  assert_output_contains "staging"
  assert_output_contains "start"
  assert_output_contains "sync-status"
}

@test "subcommand --help prints the description and runs nothing" {
  stub ssh; stub docker; stub npm
  run_cli migrate start --help
  assert_output_contains "Start a new migration from one server to another"
  run_cli migrate load --help
  assert_output_contains "Loads the configuration file from migration_profiles"
  run_cli migrate staging --help
  assert_output_contains "Start a new migration from the localhost to a server"
  run_cli migrate sync-status --help
  assert_output_contains "Show the status of the sync uploads script"
  refute_stub_called '.'
}

# --- load (profiles) ----------------------------------------------------------

@test "load without a migration_profiles directory exits 1" {
  stub ssh
  run migrate load
  [ "$status" -eq 1 ]
  assert_output_contains "No migration profiles found, please create one first."
  refute_stub_called '^ssh'
}

@test "load with an empty migration_profiles directory exits 1" {
  stub ssh
  mkdir -p "$PROFILES"
  run migrate load
  [ "$status" -eq 1 ]
  assert_output_contains "No migration profiles found"
}

@test "load copies the chosen profile to .migration and runs the migration" {
  stub_migration_ssh
  mkdir -p "$PROFILES"
  write_migration_config "$PROFILES/acme"
  echo "migration_profile_name=acme" >> "$PROFILES/acme"
  # select 1 = acme; then: uploads n, fallback n, plugins i i, keep .migration n
  run migrate load <<< $'1\nnniin'
  [ "$status" -eq 0 ]
  assert_output_contains "Please select a migration profile:"
  assert_output_contains "wp CLI is available on the source server, version WP-CLI 2.10.0"
  assert_output_contains "Flushing the rewrite rules on the destination server..."
  [ -f "$CONFIG" ]
  cmp -s "$CONFIG" "$PROFILES/acme"
  # a loaded profile has a name, so it is not asked to be saved again
  refute_output_contains "Saving the migration profile"
  assert_stub_called "^ssh -p 22 $SRC wp --allow-root db export migration_export.sql --path=wordpress/current --default-character-set=utf8mb4$"
}

# --- start: menu for an active migration --------------------------------------------

@test "start with an active migration: No exits without running anything" {
  stub ssh; stub scp; stub ssh-copy-id
  write_migration_config "$CONFIG"
  run migrate start <<< "2"
  [ "$status" -eq 0 ]
  assert_output_contains "A migration is already in progress (from src.example.com to c125667.sgvps.net), do you want to continue?"
  refute_stub_called '.'
  [ -f "$CONFIG" ]
}

@test "start with an active migration: View prints the file and asks again" {
  stub ssh; stub scp; stub ssh-copy-id
  write_migration_config "$CONFIG"
  run migrate start <<< $'3\n2'
  [ "$status" -eq 0 ]
  assert_output_contains "ssh_hostname_destination=c125667.sgvps.net"
  refute_stub_called '.'
}

@test "start with an active migration: Start new removes the file and asks for new credentials" {
  stub ssh; stub scp
  stub ssh-copy-id 'exit 1'
  write_migration_config "$CONFIG"
  # 5 = Start new migration; then n (no ssh config), username/hostname/port/path, ssh-copy-id fails
  run migrate start <<< $'5\nnbob\nvps.example.com\n\n\n'
  [ "$status" -eq 1 ]
  assert_output_contains "SSH credentials for the source server are incorrect"
  assert_stub_called '^ssh-copy-id -p 22 bob@vps.example.com$'
  [ ! -f "$CONFIG" ]
}

# --- start: asking for credentials ----------------------------------------------------

@test "start with an empty ssh config host exits 1" {
  stub ssh; stub ssh-copy-id
  run migrate start <<< $'y\n'
  [ "$status" -eq 1 ]
  assert_output_contains "The ssh config host is empty, please try again."
  refute_stub_called '^ssh'
}

@test "start resolves the source server from the ssh config (ssh -G)" {
  stub ssh 'case "$1" in -G) printf "user bob\nhostname vps.example.com\nport 2222\n" ;; esac'
  stub ssh-copy-id 'exit 1'
  run migrate start <<< $'ymyvps\n\n'
  [ "$status" -eq 1 ]
  assert_stub_called '^ssh -G myvps$'
  assert_stub_called '^ssh-copy-id -p 2222 bob@vps.example.com$'
}

@test "start removes the half-written config when the destination credentials fail" {
  stub ssh
  stub ssh-copy-id 'case "$*" in *dstuser*) exit 1 ;; esac'
  run migrate start <<< $'nsrcuser\nsrc.example.com\n\n\nnew.example.com\nndstuser\n\n\n\n'
  [ "$status" -eq 1 ]
  assert_output_contains "SSH credentials for the destination server are incorrect"
  assert_stub_called "^ssh-copy-id -p 22 $SRC$"
  assert_stub_called "^ssh-copy-id -p 18765 $DST$"
  [ ! -f "$CONFIG" ]
}

@test "start without a destination domain defaults the path to the source siteurl and skips search-replace" {
  stub_migration_ssh
  run migrate start <<< $'nsrcuser\nsrc.example.com\n\n\n\nndstuser\n\n\n\nnnniin'
  [ "$status" -eq 0 ]
  assert_calls_in_order \
    "^ssh-copy-id -p 22 $SRC$" \
    "^ssh -p 22 $SRC wp --allow-root option get siteurl --path=wordpress/current$" \
    "^ssh-copy-id -p 18765 $DST$"
  grep -q '^ssh_domain_destination=$' "$CONFIG"
  grep -q '^ssh_path_destination=www/old.example.com/public_html$' "$CONFIG"
  refute_stub_called 'search-replace'
  refute_stub_called 'config get MULTISITE'
}

@test "start writes the full config from the answers, with the siteground defaults" {
  stub_migration_ssh
  run migrate start <<< $'nsrcuser\nsrc.example.com\n\n\nnew.example.com\nndstuser\n\n\n\nnnniin'
  [ "$status" -eq 0 ]
  assert_calls_in_order "^ssh-copy-id -p 22 $SRC$" "^ssh-copy-id -p 18765 $DST$"
  # the last answer was n, so the config is kept and can be compared
  [ -f "$CONFIG" ]
  expected="$(write_migration_config /dev/stdout)"
  [ "$(cat "$CONFIG")" = "$expected" ]
}

@test "start saves the config as a profile when asked" {
  stub_migration_ssh
  mkdir -p "$PROFILES"
  write_migration_config "$CONFIG"
  # 1 = continue; save y + name; uploads n, fallback n, plugins i i, delete y
  run migrate start <<< $'1\nyacme\nnniiy'
  [ "$status" -eq 0 ]
  assert_output_contains "Saving the migration profile..."
  [ -f "$PROFILES/acme" ]
  grep -q '^migration_profile_name=acme$' "$PROFILES/acme"
  grep -q '^migration_saved=true$' "$PROFILES/acme"
  grep -q '^ssh_hostname_destination=c125667.sgvps.net$' "$PROFILES/acme"
  [ ! -f "$CONFIG" ]
}

@test "start saves a profile also when migration_profiles does not exist yet" {
  stub_migration_ssh
  write_migration_config "$CONFIG"
  run migrate start <<< $'1\nyacme\nnniiy'
  [ "$status" -eq 0 ]
  [ -f "$PROFILES/acme" ]
  [ ! -d "$TEST_TMP/migration_profiles" ]
}

# --- run: the migration steps ----------------------------------------------------------------

@test "run executes the database, files and config steps in order" {
  stub_migration_ssh
  write_migration_config "$CONFIG"
  echo "migration_profile_name=acme" >> "$CONFIG"
  # 1 = continue; uploads n, fallback n, akismet d, sg-cachepress a, delete y
  run migrate start <<< $'1\nnnday'
  [ "$status" -eq 0 ]
  assert_output_contains "Flushing the rewrite rules on the destination server..."
  assert_output_contains "Clearing..."
  assert_calls_in_order \
    "^ssh -p 18765 $DST ls .ssh/id_ed25519.pub$" \
    "^ssh -p 18765 $DST cat .ssh/id_ed25519.pub$" \
    "^ssh -p 22 $SRC grep -q \"ssh-ed25519 AAAA dest@c125667\" .ssh/authorized_keys$" \
    "^ssh -p 22 $SRC wp --allow-root --version$" \
    "^ssh -p 22 $SRC wp --allow-root db export migration_export.sql --path=wordpress/current --default-character-set=utf8mb4$" \
    "^ssh -p 18765 $DST scp -o StrictHostKeyChecking=no  -P 22 $SRC:migration_export.sql ./migration_export.sql$" \
    "^ssh -p 18765 $DST wp --allow-root db export migration_backup.sql --path=$DST_PATH$" \
    "^ssh -p 18765 $DST wp --allow-root db reset --yes --path=\"$DST_PATH\"$" \
    "^ssh -p 18765 $DST wp --allow-root db import ~/migration_export.sql --path=$DST_PATH$" \
    "^ssh -p 18765 $DST rm migration_export.sql$" \
    "^ssh -p 22 $SRC wp --allow-root config get table_prefix --path=wordpress/current$" \
    "^ssh -p 18765 $DST wp --allow-root config set table_prefix wp_ --path=$DST_PATH$" \
    "^ssh -p 18765 $DST rsync -e \"ssh -p 22\" -av --stats $SRC:wordpress/current/wp-content/\{themes,plugins,languages\} \"./$DST_PATH/wp-content\"$" \
    "^ssh -p 22 $SRC wp --allow-root option get siteurl --path=wordpress/current$" \
    "^ssh -p 18765 $DST wp --allow-root search-replace https://old.example.com https://new.example.com --path=$DST_PATH --all-tables$" \
    "^ssh -p 18765 $DST wp --allow-root config get MULTISITE --path=$DST_PATH$" \
    "^ssh -p 18765 $DST wp --allow-root config list --format=csv --path=$DST_PATH$" \
    "^ssh -p 22 $SRC wp --allow-root config list --format=csv --path=wordpress/current$" \
    "^ssh -n -p 18765 $DST wp --allow-root config set 'CUSTOM_URL' 'https://new.example.com/x' --type=constant --path=$DST_PATH$" \
    "^ssh -p 18765 $DST grep -o \"ini_set\('display_errors', '0'\);\" $DST_PATH/wp-config.php$" \
    "^ssh -p 18765 $DST grep -o \"define\( 'WP_DEBUG', false \)\" $DST_PATH/wp-config.php$" \
    "^ssh -p 18765 $DST sed -i \"s/define\( 'WP_DEBUG', false \);/define\( 'WP_DEBUG', false \);ini_set\('display_errors', '0'\);/g\" $DST_PATH/wp-config.php$" \
    "^ssh -p 18765 $DST wp --allow-root plugin status warpdrive --path=$DST_PATH --allow-root \| grep -o 'Status: Active'" \
    "^ssh -p 18765 $DST wp --allow-root plugin delete warpdrive --path=$DST_PATH$" \
    "^ssh -p 18765 $DST wp --allow-root plugin list --field=name --path=$DST_PATH --allow-root \| grep -o 'wordpress-starter'$" \
    "^ssh -p 18765 $DST wp --allow-root plugin delete wordpress-starter --path=$DST_PATH$" \
    "^ssh -p 18765 $DST wp --allow-root plugin list --status=inactive --field=name --path=$DST_PATH$" \
    "^ssh -p 18765 $DST wp --allow-root plugin delete akismet --path=$DST_PATH$" \
    "^ssh -p 18765 $DST wp --allow-root plugin activate sg-cachepress --path=$DST_PATH$" \
    "^ssh -p 18765 $DST wp --allow-root sg optimize webp enable --path=$DST_PATH$" \
    "^ssh -p 18765 $DST wp --allow-root sg optimize dynamic-cache enable --path=$DST_PATH$" \
    "^ssh -p 18765 $DST wp --allow-root sg optimize file-cache enable --path=$DST_PATH$" \
    "^ssh -p 18765 $DST wp --allow-root sg memcached enable --path=$DST_PATH$" \
    "^ssh -p 18765 $DST wp --allow-root cache flush --path=$DST_PATH$" \
    "^ssh -p 18765 $DST wp --allow-root rewrite flush --path=$DST_PATH$" \
    "^ssh -p 18765 $DST wp --allow-root site list --path=$DST_PATH$"
  # the source's constants that the destination already has are not re-set
  refute_stub_called "config set 'DB_NAME'"
  refute_stub_called "config set 'WP_DEBUG'"
  refute_stub_called "config set 'name'"
  # not a multisite: no wp_blogs replace, no .htaccess rewrite
  refute_stub_called 'wp_blogs'
  refute_stub_called '^scp'
  # no uploads were synced
  refute_stub_called 'sync_uploads'
  # the temporary csv files are cleaned up and the migration cleared on y
  [ ! -f wp-config.csv ]
  [ ! -f wp-config.migrated.csv ]
  [ ! -f "$CONFIG" ]
}

@test "run keeps the migration file when the final answer is n" {
  stub_migration_ssh
  write_migration_config "$CONFIG"
  echo "migration_profile_name=acme" >> "$CONFIG"
  run migrate start <<< $'1\nnniin'
  [ "$status" -eq 0 ]
  [ -f "$CONFIG" ]
}

@test "run creates the destination key pair and authorizes it on the source when missing" {
  stub_migration_ssh
  export MIGRATE_TEST_NO_DEST_KEY=1 MIGRATE_TEST_KEY_MISSING=1
  write_migration_config "$CONFIG"
  echo "migration_profile_name=acme" >> "$CONFIG"
  run migrate start <<< $'1\nnniin'
  [ "$status" -eq 0 ]
  assert_output_contains "The destination server does not have a public key in the .ssh directory, we'll add it first."
  assert_output_contains "The public key of the destination server is not added to the source server, we'll add it first."
  assert_calls_in_order \
    "^ssh -p 18765 $DST ls .ssh/id_ed25519.pub$" \
    "^ssh -p 18765 $DST ssh-keygen -t ed25519 -b 4096 -C \"$DST\"$" \
    "^ssh -p 22 $SRC echo \"ssh-ed25519 AAAA dest@c125667\" >> .ssh/authorized_keys$"
}

@test "run falls back to the plesk wp binary and stops when wp cli is missing on the source" {
  stub ssh 'case "$*" in *"--version"*) echo "bash: wp: command not found" ;; esac; exit 0'
  stub scp; stub ssh-copy-id
  write_migration_config "$CONFIG"
  echo "migration_profile_name=acme" >> "$CONFIG"
  run migrate start <<< $'1\n'
  [ "$status" -eq 1 ]
  assert_output_contains "trying with /opt/plesk/php/8.2/bin/php  /usr/local/bin/wp"
  assert_output_contains "The wp CLI is not available on the source server, so we cannot start the migration."
  assert_calls_in_order \
    "^ssh -p 22 $SRC wp --allow-root --version$" \
    "^ssh -p 22 $SRC /opt/plesk/php/8.2/bin/php  /usr/local/bin/wp --version$"
  refute_stub_called 'db export'
  refute_stub_called 'db reset'
}

@test "run does not delete or activate inactive plugins on i" {
  stub_migration_ssh
  write_migration_config "$CONFIG"
  echo "migration_profile_name=acme" >> "$CONFIG"
  run migrate start <<< $'1\nnniin'
  [ "$status" -eq 0 ]
  assert_stub_called "plugin list --status=inactive"
  refute_stub_called 'plugin delete akismet'
  refute_stub_called 'plugin activate'
  refute_stub_called 'sg optimize'
}

@test "run activates a plugin network wide on n" {
  stub_migration_ssh
  export MIGRATE_TEST_INACTIVE="akismet"
  write_migration_config "$CONFIG"
  echo "migration_profile_name=acme" >> "$CONFIG"
  run migrate start <<< $'1\nnnnn'
  [ "$status" -eq 0 ]
  assert_stub_called "^ssh -p 18765 $DST wp --allow-root plugin activate akismet --network --path=$DST_PATH$"
  refute_stub_called 'plugin delete akismet'
}

@test "run skips the inactive plugin loop when there are none" {
  stub_migration_ssh
  export MIGRATE_TEST_INACTIVE=""
  write_migration_config "$CONFIG"
  echo "migration_profile_name=acme" >> "$CONFIG"
  run migrate start <<< $'1\nnnn'
  [ "$status" -eq 0 ]
  refute_stub_called 'plugin delete akismet'
  refute_stub_called 'plugin activate'
  [ -f "$CONFIG" ]
}

@test "run syncs the uploads through the sync script on the destination on y" {
  stub_migration_ssh
  write_migration_config "$CONFIG"
  echo "migration_profile_name=acme" >> "$CONFIG"
  run migrate start <<< $'1\nyiin'
  [ "$status" -eq 0 ]
  assert_output_contains "Syncing the wp-content uploads directory to the destination server..."
  assert_calls_in_order \
    "^scp -o StrictHostKeyChecking=no -P 18765 $CLI_ROOT/inc/\.\./templates/sync_uploads\.sh\.tpl $DST:sync_uploads\.sh$" \
    "^ssh -p 18765 $DST bash sync_uploads.sh srcuser src.example.com 22 wordpress/current/wp-content/uploads $DST_PATH/wp-content &$"
  refute_output_contains "fallback"
}

@test "run configures a cross-domain uploads fallback instead of syncing" {
  stub_migration_ssh
  stub scp 'for a in "$@"; do [ -f "$a" ] && cp "$a" "$TEST_TMP/scp-captured"; done; exit 0'
  write_migration_config "$CONFIG"
  echo "migration_profile_name=acme" >> "$CONFIG"
  # uploads n, fallback y + domain (trailing slash is stripped), plugins i i, delete n
  run migrate start <<< $'1\nnyhttps://old.example.com/\niin'
  [ "$status" -eq 0 ]
  assert_output_contains "Cross-domain fallback configured successfully."
  assert_calls_in_order \
    "^ssh -p 18765 $DST mkdir -p $DST_PATH/wp-content/uploads$" \
    "^scp -o StrictHostKeyChecking=no -P 18765 .htaccess.uploads.tmp $DST:$DST_PATH/wp-content/uploads/.htaccess$"
  refute_stub_called 'sync_uploads'
  [ ! -f .htaccess.uploads.tmp ]
  grep -qF 'RewriteRule ^(.*)$ https://old.example.com/wp-content/uploads/$1 [L,R=302]' "$TEST_TMP/scp-captured"
  grep -q '^# Start crossdomain fallback$' "$TEST_TMP/scp-captured"
}

@test "run on a subdomain multisite also replaces wp_blogs and rewrites .htaccess" {
  stub_migration_ssh
  export MIGRATE_TEST_MULTISITE=1 MIGRATE_TEST_SUBDOMAIN=1
  write_migration_config "$CONFIG"
  echo "migration_profile_name=acme" >> "$CONFIG"
  run migrate start <<< $'1\nnniin'
  [ "$status" -eq 0 ]
  assert_output_contains "This is a subdomain multisite."
  assert_calls_in_order \
    "^ssh -p 18765 $DST wp --allow-root search-replace https://old.example.com https://new.example.com --path=$DST_PATH --all-tables$" \
    "^ssh -p 18765 $DST wp --allow-root config get MULTISITE --path=$DST_PATH$" \
    "^ssh -p 18765 $DST wp --allow-root search-replace old.example.com new.example.com --url=old.example.com --path=$DST_PATH wp_blogs$" \
    "^ssh -p 18765 $DST wp --allow-root site list --path=$DST_PATH$" \
    "^ssh -p 18765 $DST cat $DST_PATH/.htaccess$" \
    "^ssh -p 18765 $DST wp --allow-root config get SUBDOMAIN_INSTALL --path=$DST_PATH$" \
    "^scp -o StrictHostKeyChecking=no -P 18765 .htaccess $DST:$DST_PATH/.htaccess$"
  # the rewritten .htaccess (left in the cwd) has the multisite block and keeps the rest
  grep -q 'Using subdomain network type' .htaccess
  grep -q '^# BEGIN WordPress$' .htaccess
  grep -q '^# END WordPress$' .htaccess
  grep -q '^AddType image/webp .webp$' .htaccess
  ! grep -q '^RewriteEngine On$' .htaccess
}

@test "run on a subfolder multisite writes the subfolder rewrite rules" {
  stub_migration_ssh
  export MIGRATE_TEST_MULTISITE=1 MIGRATE_TEST_SUBDOMAIN=0
  write_migration_config "$CONFIG"
  echo "migration_profile_name=acme" >> "$CONFIG"
  run migrate start <<< $'1\nnniin'
  [ "$status" -eq 0 ]
  assert_output_contains "This is a subfolder multisite."
  grep -q 'Using subfolder network type' .htaccess
  grep -qF 'RewriteRule ^([_0-9a-zA-Z-]+/)?wp-admin$ $1wp-admin/ [R=301,L]' .htaccess
}

# --- sync-status -----------------------------------------------------------------------------

@test "sync-status without an active migration or saved profiles exits 1 before any ssh" {
  stub ssh
  run migrate sync-status
  [ "$status" -eq 1 ]
  assert_output_contains "No active migration found."
  assert_output_contains "No migration profiles found either"
  refute_stub_called '^ssh'
}

@test "sync-status with an empty migration_profiles directory exits 1 before any ssh" {
  stub ssh
  mkdir -p "$PROFILES"
  run migrate sync-status
  [ "$status" -eq 1 ]
  assert_output_contains "No migration profiles found either"
  refute_stub_called '^ssh'
}

@test "sync-status without an active migration lets you pick a saved profile" {
  stub ssh 'case "$*" in *"ls sync_uploads.sh"*) echo sync_uploads.sh ;; *"ls .sync_running"*) exit 1 ;; *"xargs cat"*) echo "last sync: 1234 files" ;; esac; exit 0'
  mkdir -p "$PROFILES"
  write_migration_config "$PROFILES/acme"
  run migrate sync-status <<< "1"
  [ "$status" -eq 1 ]
  assert_output_contains "No active migration found."
  assert_output_contains "last sync: 1234 files"
  assert_output_contains "The sync uploads script is not running on the destination server"
  assert_calls_in_order \
    "^ssh -p 18765 $DST ls sync_uploads.sh$" \
    "^ssh -p 18765 $DST ls .sync_running$" \
    "^ssh -p 18765 $DST ls -t sync-uploads-\* \| head -1 \| xargs cat$"
}

@test "sync-status without a sync script on the destination exits 1" {
  stub ssh
  write_migration_config "$CONFIG"
  run migrate sync-status
  [ "$status" -eq 1 ]
  assert_output_contains "No sync uploads script found on the destination server."
  assert_stub_called "^ssh -p 18765 $DST ls sync_uploads.sh$"
  refute_stub_called 'tail -f'
}

@test "sync-status tails the log of a running sync" {
  stub ssh 'case "$*" in *"ls sync_uploads.sh"*) echo sync_uploads.sh ;; *"ls .sync_running"*) echo .sync_running ;; *"tail -f"*) echo "syncing 42%" ;; esac; exit 0'
  write_migration_config "$CONFIG"
  run migrate sync-status
  [ "$status" -eq 0 ]
  assert_output_contains "The sync uploads script is running on the destination server"
  assert_output_contains "syncing 42%"
  assert_stub_called "^ssh -p 18765 $DST tail -f sync-uploads.log$"
}

# --- staging (local docker -> staging server) -------------------------------------------------

# Docker with both containers up and an npm with a db:export script.
stub_staging_env() {
  stub docker 'case "$*" in
  "ps -q --filter name=wordpress") echo abc123 ;;
  "ps -q --filter name=db") echo def456 ;;
  "ps --filter name=wordpress") printf "CONTAINER ID   NAMES\nabc123   proj-wordpress-1\n" ;;
esac; exit 0'
  stub npm 'if [ "$1" = run ] && [ $# -eq 1 ]; then printf "Lifecycle scripts:\n  db:export\n    docker compose exec db mysqldump\n"; fi; exit 0'
  stub rsync
  stub ssh
  stub openssl 'echo s3cret'
}

make_staging_env() {
  make_env \
    "DEPLOY_STAGING_HOSTNAME=staging.example.com" \
    "DEPLOY_STAGING_USER=deploy" \
    "DEPLOY_STAGING_PORT=2222" \
    "DEPLOY_STAGING_PATH=/var/www/staging/wp-content/themes" \
    "DEV_TABLE_PREFIX=wp_" \
    "DEV_HOST=https://project.test"
}

@test "staging exits 1 when the wordpress container is not running" {
  stub docker
  stub npm
  run migrate staging
  [ "$status" -eq 1 ]
  assert_output_contains "The wordpress docker is not running"
  refute_stub_called '^npm'
}

@test "staging exits 1 when the db container is not running" {
  stub docker 'case "$*" in "ps -q --filter name=wordpress") echo abc123 ;; esac; exit 0'
  stub npm
  run migrate staging
  [ "$status" -eq 1 ]
  assert_output_contains "The database docker is not running"
  refute_stub_called '^npm'
}

@test "staging exits 1 when npm run db:export is not available" {
  stub docker 'echo abc123'
  stub npm
  stub rsync
  run migrate staging
  [ "$status" -eq 1 ]
  assert_output_contains "The npm run db:export command is not available"
  refute_stub_called '^rsync'
}

@test "staging exits 1 without an .env file" {
  stub_staging_env
  run migrate staging
  [ "$status" -eq 1 ]
  assert_output_contains "We need an .env file"
  refute_stub_called '^rsync'
}

@test "staging does nothing when the overwrite is not confirmed" {
  stub_staging_env
  make_staging_env
  run migrate staging <<< "n"
  [ "$status" -eq 1 ]
  refute_output_contains "Let's go!"
  refute_stub_called '^npm run db:export'
  refute_stub_called '^rsync'
  refute_stub_called '^ssh'
}

@test "staging exits 1 when no destination domain is given" {
  stub_staging_env
  make_staging_env
  run migrate staging <<< $'y\n'
  [ "$status" -eq 1 ]
  assert_output_contains "Let's go!"
  assert_output_contains "We need a domain name"
  refute_stub_called '^npm run db:export'
  refute_stub_called '^rsync'
}

@test "staging exports the db, rsyncs plugins, uploads and dump, imports and deploys" {
  stub_staging_env
  make_staging_env
  run migrate staging <<< $'yhttps://staging.example.com\n'
  [ "$status" -eq 0 ]
  assert_output_contains "Done! You can now visit https://staging.example.com."
  assert_calls_in_order \
    '^npm run db:export$' \
    '^rsync -av -e ssh -p2222 -o ConnectTimeout=10 ./wp-content/plugins deploy@staging.example.com:/var/www/staging/wp-content$' \
    '^rsync -av -e ssh -p2222 -o ConnectTimeout=10 ./wp-content/uploads deploy@staging.example.com:/var/www/staging/wp-content$' \
    '^rsync -az -e ssh -p2222 -o ConnectTimeout=10 ./wp-db-dump/db.sql deploy@staging.example.com:/var/www/staging$' \
    '^ssh -p2222 deploy@staging.example.com .*db reset --yes --path=/var/www/staging$' \
    '^ssh -p2222 deploy@staging.example.com .*db import /var/www/staging/db.sql --path=/var/www/staging$' \
    '^ssh -p2222 deploy@staging.example.com rm /var/www/staging/db.sql$' \
    '^ssh -p2222 deploy@staging.example.com .*config set table_prefix wp_ --path=/var/www/staging$' \
    '^ssh -p2222 deploy@staging.example.com .*search-replace https://project.test https://staging.example.com --path=/var/www/staging --all-tables$' \
    '^npm run deploy-staging$' \
    '^ssh -p2222 deploy@staging.example.com .*user update --all --user_pass=s3cret$'
}

@test "staging runs the remote wp cli commands as 'wp --allow-root'" {
  stub_staging_env
  make_staging_env
  run migrate staging <<< $'yhttps://staging.example.com\n'
  [ "$status" -eq 0 ]
  assert_stub_called '^ssh -p2222 deploy@staging.example.com wp --allow-root db reset --yes --path=/var/www/staging$'
}
