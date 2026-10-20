#!/usr/bin/env bats
# Smoke: the entry point, dispatch and the sandbox itself work.

load test_helper
setup()    { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "bare call prints usage and exits 1" {
  run_cli
  [ "$status" -eq 1 ]
  assert_output_contains "Usage:"
  assert_output_contains "Possible commands:"
}

@test "unknown command is reported" {
  run_cli nope
  [ "$status" -eq 1 ]
  assert_output_contains "Unknown command: nope"
}

@test "hello world runs through dispatch" {
  run_cli hello world
  [ "$status" -eq 0 ]
  assert_output_contains "Hello"
}

@test "stubs record their calls" {
  stub ssh 'echo stubbed'
  run ssh host ls
  [ "$status" -eq 0 ]
  [ "$output" = "stubbed" ]
  assert_stub_called '^ssh host ls$'
  refute_stub_called '^rsync'
}

@test "load_cli exposes helpers for unit tests" {
  load_cli
  run _is_semantic_version 1.2.3
  [ "$status" -eq 0 ]
  run _is_semantic_version banana
  [ "$status" -ne 0 ]
}
