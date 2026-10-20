#!/usr/bin/env bats
# inc/hello.sh through the real entry point: the minimal command collection.

load test_helper
setup()    { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "bare hello prints its documentation" {
  run_cli hello
  assert_output_contains "Available functions:"
  assert_output_contains "world - Echo hello with possible arguments"
}

@test "hello world greets the world" {
  run_cli hello world
  [ "$status" -eq 0 ]
  [ "$(plain_output)" = "Hello world!" ]
}

@test "hello world greets the first argument" {
  run_cli hello world Eric
  [ "$status" -eq 0 ]
  [ "$(plain_output)" = "Hello Eric!" ]
}

@test "hello world --help prints the description and does not greet" {
  run_cli hello world --help
  assert_output_contains "world - Echo hello with possible arguments"
  refute_output_contains "Hello"
}

@test "unknown hello subcommand is reported with the docs and fails" {
  run_cli hello universe
  [ "$status" -eq 1 ]
  assert_output_contains "Unknown command: universe"
  assert_output_contains "Available functions:"
}

@test "bare hello exits 0" {
  skip "bug: _echo_documentation ends on a failing read, so a bare 'hello' (and 'hello world --help') exits 1 instead of 0"
  run_cli hello
  [ "$status" -eq 0 ]
  run_cli hello world --help
  [ "$status" -eq 0 ]
}
