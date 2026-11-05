#!/usr/bin/env bats
# inc/changelog.sh through the real entry point: reads the repo's CHANGELOG.md.

load test_helper
setup()    { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "bare changelog prints its documentation" {
  run_cli changelog
  [ "$status" -eq 0 ]
  assert_output_contains "Available functions:"
  assert_output_contains "latest - Prints the newest released version"
}

@test "changelog latest prints the newest released entry, not Unreleased" {
  run_cli changelog latest
  [ "$status" -eq 0 ]
  [ "$(plain_output | head -1 | cut -c1-5)" = "## [1" ]
  refute_output_contains "[Unreleased]"
  [ "$(plain_output | grep -c '^## \[')" -eq 1 ]
}

@test "changelog show prints one version" {
  run_cli changelog show 1.3.0
  [ "$status" -eq 0 ]
  [ "$(plain_output | head -1 | cut -c1-10)" = "## [1.3.0]" ]
  [ "$(plain_output | grep -c '^## \[')" -eq 1 ]
}

@test "changelog show fails for an unknown version" {
  run_cli changelog show 0.0.0
  [ "$status" -eq 1 ]
  assert_output_contains "No changelog entry for version 0.0.0"
}

@test "changelog show without a version fails with usage" {
  run_cli changelog show
  [ "$status" -eq 1 ]
  assert_output_contains "Usage:"
}

@test "changelog all prints the whole file" {
  run_cli changelog all
  [ "$status" -eq 0 ]
  assert_output_contains "# Changelog"
  assert_output_contains "[Unreleased]"
}

@test "changelog latest --help prints the description and does not run" {
  run_cli changelog latest --help
  [ "$status" -eq 0 ]
  assert_output_contains "latest - Prints the newest released version"
  refute_output_contains "## ["
}
