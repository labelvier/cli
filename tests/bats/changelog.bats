#!/usr/bin/env bats
# inc/changelog.sh through the real entry point: shows the repo's CHANGELOG.md.

load test_helper
setup()    { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "changelog prints the whole CHANGELOG.md straight away (no pager when piped)" {
  run_cli changelog
  [ "$status" -eq 0 ]
  assert_output_contains "# Changelog"
  assert_output_contains "[Unreleased]"
  assert_output_contains "## [1.3.0]"
}

@test "changelog does not print the command documentation" {
  run_cli changelog
  refute_output_contains "Available functions:"
}

@test "changelog --help prints a description and not the changelog" {
  run_cli changelog --help
  [ "$status" -eq 0 ]
  assert_output_contains "changelog - Reads the CHANGELOG.md in a pager"
  refute_output_contains "# Changelog"
}
