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
}
teardown() { teardown_sandbox; }

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
