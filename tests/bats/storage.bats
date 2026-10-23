#!/usr/bin/env bats
# inc/storage.sh: storage summary, WebP conversion and leftover-file cleanup on SiteGround hosts over ssh.

load test_helper
setup()    { setup_sandbox; }
teardown() { teardown_sandbox; }

WP_PATH="/home/customer/www/example.com/public_html"

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

# ssh that answers the "find the WordPress path" probe and ignores the rest.
stub_ssh_with_wp_path() {
  stub ssh 'case "$*" in *"find /home/customer/www/*/public_html"*) echo "/home/customer/www/example.com/public_html" ;; esac; exit 0'
  stub scp
}

# --- docs & help ------------------------------------------------------------

@test "bare storage prints its functions" {
  run_cli storage
  assert_output_contains "Available functions:"
  assert_output_contains "summary"
  assert_output_contains "convert-to-webp"
  assert_output_contains "cleanup"
}

@test "subcommand --help prints the description without connecting" {
  stub ssh
  run_cli storage summary --help
  [ "$status" -eq 0 ]
  assert_output_contains "Generate a storage summary"
  run_cli storage convert-to-webp --help
  [ "$status" -eq 0 ]
  assert_output_contains "Convert images to WebP"
  run_cli storage cleanup --help
  [ "$status" -eq 0 ]
  assert_output_contains "leftover .sql, .zip, .tar and .log files"
  refute_stub_called '^ssh'
}

# --- summary ------------------------------------------------------------------

@test "summary without a host exits 1" {
  stub ssh
  run_cli storage summary
  [ "$status" -eq 1 ]
  assert_output_contains "Please provide a ssh host"
  refute_stub_called '^ssh'
}

@test "summary exits when no WordPress path is found on the host" {
  stub ssh
  stub scp
  run_cli storage summary myhost
  [ "$status" -eq 1 ]
  assert_output_contains "No WordPress installation found"
  refute_stub_called '^scp'
}

@test "summary uploads tree.sh and runs it on wp-content with depth 0 by default" {
  stub_ssh_with_wp_path
  run_cli storage summary myhost
  [ "$status" -eq 0 ]
  assert_output_contains "Analyzing 'wp-content' in WordPress path: $WP_PATH"
  assert_calls_in_order \
    "^ssh myhost find /home/customer/www/\*/public_html -maxdepth 0" \
    "^scp $CLI_ROOT/inc/\.\./templates/tree\.sh\.tpl myhost:/home/customer/tree\.sh$" \
    '^ssh myhost chmod \+x /home/customer/tree\.sh$' \
    "^ssh myhost /bin/bash /home/customer/tree\.sh $WP_PATH/wp-content 0$"
}

@test "summary passes the max depth through" {
  stub_ssh_with_wp_path
  run_cli storage summary myhost 3
  [ "$status" -eq 0 ]
  assert_stub_called "^ssh myhost /bin/bash /home/customer/tree\.sh $WP_PATH/wp-content 3$"
}

# --- convert-to-webp ------------------------------------------------------------

@test "convert-to-webp without a host prints usage and exits 1" {
  stub ssh
  run_cli storage convert-to-webp
  [ "$status" -eq 1 ]
  assert_output_contains "Usage: ./labelvier storage convert-to-webp <host> [options]"
  assert_output_contains "--dry-run"
  refute_stub_called '^ssh'
}

@test "convert-to-webp rejects an unknown option before connecting" {
  stub ssh
  run_cli storage convert-to-webp myhost --bogus
  [ "$status" -eq 1 ]
  assert_output_contains "Unknown option: --bogus"
  refute_stub_called '^ssh'
}

@test "convert-to-webp exits when no WordPress path is found" {
  stub ssh
  stub scp
  run_cli storage convert-to-webp myhost
  [ "$status" -eq 1 ]
  assert_output_contains "No WordPress installation found"
  refute_stub_called '^scp'
}

@test "convert-to-webp runs the script on uploads with the defaults" {
  stub_ssh_with_wp_path
  run_cli storage convert-to-webp myhost
  [ "$status" -eq 0 ]
  assert_output_contains "Target path: $WP_PATH/wp-content/uploads"
  assert_output_contains "Quality:       85"
  assert_output_contains "Dry run:       false"
  assert_output_contains "WebP conversion completed."
  assert_output_contains "ssh myhost 'rm /home/customer/convert-to-webp.sh'"
  assert_calls_in_order \
    "^scp $CLI_ROOT/inc/\.\./templates/convert-to-webp\.sh\.tpl myhost:/home/customer/convert-to-webp\.sh$" \
    '^ssh myhost chmod \+x /home/customer/convert-to-webp\.sh$' \
    "^ssh myhost QUALITY=85 DRY_RUN=false CREATE_BACKUP=false PARALLEL_JOBS=4 AUTO_YES=false BACKGROUND_MODE=false /bin/bash /home/customer/convert-to-webp\.sh $WP_PATH/wp-content/uploads$"
}

@test "convert-to-webp --dry-run sets DRY_RUN and reports a dry run" {
  stub_ssh_with_wp_path
  run_cli storage convert-to-webp myhost --dry-run
  [ "$status" -eq 0 ]
  assert_output_contains "Dry run:       true"
  assert_output_contains "Dry run completed - no files were modified."
  refute_output_contains "WebP conversion completed."
  assert_stub_called "^ssh myhost QUALITY=85 DRY_RUN=true CREATE_BACKUP=false PARALLEL_JOBS=4 AUTO_YES=false BACKGROUND_MODE=false /bin/bash "
}

@test "convert-to-webp passes every option into the remote environment" {
  stub_ssh_with_wp_path
  run_cli storage convert-to-webp myhost --quality 90 --parallel-jobs 8 --with-backup --yes --path wp-content/uploads/2024
  [ "$status" -eq 0 ]
  assert_output_contains "Target path: $WP_PATH/wp-content/uploads/2024"
  assert_stub_called "^ssh myhost QUALITY=90 DRY_RUN=false CREATE_BACKUP=true PARALLEL_JOBS=8 AUTO_YES=true BACKGROUND_MODE=false /bin/bash /home/customer/convert-to-webp\.sh $WP_PATH/wp-content/uploads/2024$"
}

@test "convert-to-webp --background explains how to follow the remote job" {
  stub_ssh_with_wp_path
  run_cli storage convert-to-webp myhost --background --yes
  [ "$status" -eq 0 ]
  assert_output_contains "Script will run in background mode on the server."
  assert_output_contains "tail -f ~/webp_conversion_background_*.log"
  assert_stub_called "^ssh myhost QUALITY=85 DRY_RUN=false CREATE_BACKUP=false PARALLEL_JOBS=4 AUTO_YES=true BACKGROUND_MODE=true /bin/bash "
}

# --- cleanup --------------------------------------------------------------------

@test "cleanup without an ssh config exits 1" {
  stub ssh
  run_cli storage cleanup
  [ "$status" -eq 1 ]
  assert_output_contains "No SSH config found at $HOME/.ssh/config"
  refute_stub_called '^ssh'
}

@test "cleanup with only wildcard hosts exits 1" {
  stub ssh
  mkdir -p "$HOME/.ssh"
  printf 'Host *\n  ServerAliveInterval 60\n' > "$HOME/.ssh/config"
  run_cli storage cleanup
  [ "$status" -eq 1 ]
  assert_output_contains "No SSH aliases found"
  refute_stub_called '^ssh'
}

@test "cleanup scans every alias, deletes on yes and Enter, skips on n" {
  mkdir -p "$HOME/.ssh"
  printf 'Host *\n  User x\nHost alpha\n  HostName a.example.com\nhost beta\n  HostName b.example.com\n' > "$HOME/.ssh/config"
  # alpha has three leftovers, beta nothing; rm of old.tar fails on the server.
  stub ssh '
case "$*" in
  *"find "*)
    [ "$5" = "alpha" ] && printf "/home/alpha/dump.sql\n/home/alpha/old.tar\n/home/alpha/site.zip\n"
    ;;
  *"stat -c%s"*)
    case "$*" in
      *dump.sql*) echo 2097152 ;;
      *old.tar*) echo 2048 ;;
      *) echo 10 ;;
    esac
    ;;
  *"rm "*)
    case "$*" in *old.tar*) exit 1 ;; esac
    ;;
esac
exit 0'
  run_cli storage cleanup <<< $'y\n\nn\n'
  [ "$status" -eq 0 ]
  assert_output_contains "→ alpha"
  assert_output_contains "→ beta"
  assert_output_contains "Nothing found."
  assert_output_contains "Failed to delete /home/alpha/old.tar."
  assert_output_contains "Skipped."
  assert_output_contains "Files deleted: 1"
  assert_output_contains "Space freed:   2 MB"
  assert_stub_called "^ssh -o ConnectTimeout=2 -o BatchMode=yes alpha "
  assert_stub_called "^ssh -o ConnectTimeout=2 -o BatchMode=yes beta "
  assert_stub_called "^ssh alpha rm '/home/alpha/dump.sql'$"
  assert_stub_called "^ssh alpha rm '/home/alpha/old.tar'$"
  refute_stub_called "rm '/home/alpha/site.zip'"
  refute_stub_called "^ssh beta rm"
}
