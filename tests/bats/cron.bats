#!/usr/bin/env bats
# inc/cron.sh: deploys the cron runner to a SiteGround host over ssh/scp.
# Every remote command is stubbed; the tests assert on the recorded calls.

load test_helper
setup() {
  setup_sandbox
  # Default remote: `find` reports one project folder, everything else succeeds.
  stub ssh 'case "$*" in *find*) echo /home/customer/www/example.com/public_html ;; esac'
  stub scp
  stub rsync
  # SiteGround: no cron jobs yet, adding one succeeds.
  stub siteground-stub 'case "$*" in *--json*) echo "[]" ;; esac'
  export CRON_SITEGROUND=siteground-stub
}
teardown() { teardown_sandbox; }

# Runs the CLI without a controlling terminal, so _confirm cannot ask.
run_cli() {
  run perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$CLI" "$@" < /dev/null
}

# Runs `cron <args>` without a terminal after eval-ing <code> (an override of _confirm).
run_cron_with() {
  local code="$1"
  shift
  run perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' \
    bash -c 'source "$1"; load_cli; eval "$2"; shift 2; cron "$@"' _ \
    "$CLI_ROOT/tests/bats/test_helper.bash" "$code" "$@" < /dev/null
}

YES='_confirm() { echo "$1 -> y"; return 0; }'
NO='_confirm() { echo "$1 -> n"; return 1; }'

@test "bare cron prints its documentation" {
  run_cli cron
  assert_output_contains "Available functions:"
  assert_output_contains "deploy - Deploy the cron job to a server"
}

@test "cron deploy --help prints the description without touching the server" {
  run_cli cron deploy --help
  assert_output_contains "deploy - Deploy the cron job to a server"
  [ -z "$(stub_calls)" ]
}

@test "cron deploy without a host asks for one and fails" {
  run_cli cron deploy
  [ "$status" -eq 1 ]
  assert_output_contains "Please provide a ssh host to deploy to."
  [ -z "$(stub_calls)" ]
}

@test "cron deploy looks up the public_html folder on the host" {
  run_cli cron deploy myhost
  [ "$status" -eq 0 ]
  assert_stub_called '^ssh myhost find /home/customer/www/\*/public_html -maxdepth 0'
}

@test "cron deploy disables WP cron in the found project folder" {
  run_cli cron deploy myhost
  [ "$status" -eq 0 ]
  assert_stub_called '^ssh myhost cd /home/customer/www/example\.com/public_html && wp config set DISABLE_WP_CRON true --raw$'
}

@test "cron deploy uploads the runner template and makes it executable" {
  run_cli cron deploy myhost
  [ "$status" -eq 0 ]
  assert_stub_called '^scp .*/templates/run_cron_jobs\.sh\.tpl myhost:/home/customer/run_cron_jobs\.sh$'
  assert_stub_called '^ssh myhost chmod \+x /home/customer/run_cron_jobs\.sh$'
  refute_stub_called '^rsync'
}

@test "cron deploy runs find, wp config, scp and chmod in that order" {
  run_cli cron deploy myhost
  [ "$status" -eq 0 ]
  [ "$(stub_calls | wc -l | tr -d ' ')" = "4" ]
  [[ "$(stub_calls | sed -n 1p)" == ssh\ myhost\ find* ]]
  [[ "$(stub_calls | sed -n 2p)" == *"wp config set"* ]]
  [[ "$(stub_calls | sed -n 3p)" == scp\ * ]]
  [[ "$(stub_calls | sed -n 4p)" == *"chmod +x"* ]]
}

@test "cron deploy prints the cronjob line to add on success" {
  run_cli cron deploy myhost
  [ "$status" -eq 0 ]
  assert_output_contains "Success!"
  assert_output_contains "*/5 * * * * /bin/bash /home/customer/run_cron_jobs.sh"
}

@test "cron deploy without a terminal skips the SiteGround question and prints the line" {
  run_cli cron deploy myhost
  [ "$status" -eq 0 ]
  assert_output_contains "Add this cron job to example.com through SiteGround now? [Y/n] (no terminal to ask on, skipped)"
  assert_output_contains "Add the following cronjob to the server:"
  refute_stub_called '^siteground-stub'
}

@test "cron deploy adds the cron job through SiteGround on yes" {
  run_cron_with "$YES" deploy myhost
  [ "$status" -eq 0 ]
  assert_output_contains "Add this cron job to example.com through SiteGround now? -> y"
  assert_stub_called '^siteground-stub site:cron example\.com --json$'
  assert_stub_called '^siteground-stub site:cron example\.com --add /bin/bash /home/customer/run_cron_jobs\.sh --at \*/5 \* \* \* \*$'
  refute_output_contains "Add the following cronjob to the server:"
}

@test "cron deploy does not touch SiteGround on no and prints the line" {
  run_cron_with "$NO" deploy myhost
  [ "$status" -eq 0 ]
  refute_stub_called '^siteground-stub'
  assert_output_contains "Add the following cronjob to the server:"
}

@test "cron deploy does not add the cron job twice" {
  stub siteground-stub 'case "$*" in *--json*) echo "[{\"cmd\": \"/bin/bash /home/customer/run_cron_jobs.sh\"}]" ;; esac'
  run_cron_with "$YES" deploy myhost
  [ "$status" -eq 0 ]
  assert_output_contains "example.com already runs /bin/bash /home/customer/run_cron_jobs.sh, nothing added."
  refute_stub_called '--add'
}

@test "cron deploy falls back to the line when SiteGround cannot list the cron jobs" {
  stub siteground-stub 'exit 1'
  run_cron_with "$YES" deploy myhost
  [ "$status" -eq 0 ]
  assert_output_contains "Could not read the cron jobs of example.com."
  refute_stub_called '--add'
  assert_output_contains "*/5 * * * * /bin/bash /home/customer/run_cron_jobs.sh"
}

@test "cron deploy falls back to the line when adding fails" {
  stub siteground-stub 'case "$*" in *--json*) echo "[]" ;; *) exit 1 ;; esac'
  run_cron_with "$YES" deploy myhost
  [ "$status" -eq 0 ]
  assert_output_contains "Adding the cron job to example.com failed."
  assert_output_contains "Add the following cronjob to the server:"
}

@test "cron deploy stops when no project folder is found on the host" {
  stub ssh
  run_cli cron deploy myhost
  [ "$status" -eq 1 ]
  assert_output_contains "No project folder found. Exiting."
  refute_stub_called '^scp'
  refute_stub_called 'wp config'
}

@test "unknown cron subcommand is reported and fails" {
  run_cli cron install
  [ "$status" -eq 1 ]
  assert_output_contains "Unknown command: install"
  [ -z "$(stub_calls)" ]
}
