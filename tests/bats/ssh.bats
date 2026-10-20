#!/usr/bin/env bats
# inc/ssh.sh: hand-rolled dispatch. A known subcommand (alias, list, search,
# remove) manages ~/.ssh/config in the sandbox $HOME; anything else is forwarded
# verbatim to the real ssh binary, which is a stub here.

load test_helper
setup()    { setup_sandbox; stub ssh; }
teardown() { teardown_sandbox; }

SSH_CONFIG_REL=".ssh/config"

ssh_config() { cat "$HOME/$SSH_CONFIG_REL"; }

# Permission bits as ls prints them ("drwx------"), portable across BSD and GNU stat.
mode_of() { ls -ld "$1" | cut -c1-10; }

# --- dispatch ---------------------------------------------------------------

@test "bare ssh prints the docs and does not call ssh" {
  run_cli ssh
  assert_output_contains "Available functions:"
  assert_output_contains "alias"
  assert_output_contains "list"
  assert_output_contains "search"
  assert_output_contains "remove"
  [ -z "$(stub_calls)" ]
}

@test "--help right after a subcommand prints its description and runs nothing" {
  run_cli ssh alias --help
  [ "$status" -eq 0 ]
  assert_output_contains "alias"
  assert_output_contains "Add an SSH host alias"
  [ ! -e "$HOME/$SSH_CONFIG_REL" ]
  [ -z "$(stub_calls)" ]

  run_cli ssh remove --help
  [ "$status" -eq 0 ]
  assert_output_contains "Remove an SSH host alias"
  [ ! -e "$HOME/$SSH_CONFIG_REL" ]
}

@test "a bare --help is not a subcommand and is forwarded to ssh" {
  # not a declared function, so it goes to the real binary like any flag
  run_cli ssh --help
  assert_stub_called '^ssh --help$'
}

@test "a name that is not a subcommand is forwarded to ssh, not reported as unknown" {
  # unlike _dispatch, ssh.sh treats anything unknown as a host or ssh flag
  run_cli ssh nosuchsub
  [ "$status" -eq 0 ]
  refute_output_contains "Unknown command"
  assert_stub_called '^ssh nosuchsub$'
}

@test "ssh flags and host are forwarded verbatim with their exit code" {
  stub ssh 'echo "stub ssh: $*"; exit 7'
  run_cli ssh -p 2222 -o StrictHostKeyChecking=no deploy@example.com ls -la /www
  [ "$status" -eq 7 ]
  [ "$output" = "stub ssh: -p 2222 -o StrictHostKeyChecking=no deploy@example.com ls -la /www" ]
  [ "$(stub_calls)" = "ssh -p 2222 -o StrictHostKeyChecking=no deploy@example.com ls -la /www" ]
}

@test "ssh -G host is forwarded (used by other commands)" {
  stub ssh 'echo "hostname example.com"'
  run_cli ssh -G myalias
  [ "$status" -eq 0 ]
  [ "$output" = "hostname example.com" ]
  [ "$(stub_calls)" = "ssh -G myalias" ]
}

# --- alias ------------------------------------------------------------------

@test "alias creates ~/.ssh and the config with safe permissions and appends the Host block" {
  run_cli ssh alias web 203.0.113.10 deploy 18765 ~/.ssh/id_ed25519 < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Added alias 'web' -> deploy@203.0.113.10."
  assert_output_contains "Connect with: ssh web"
  [ "$(mode_of "$HOME/.ssh")" = "drwx------" ]
  [ "$(mode_of "$HOME/$SSH_CONFIG_REL")" = "-rw-------" ]
  [ "$(ssh_config)" = "
Host web
    HostName 203.0.113.10
    User deploy
    Port 18765
    IdentityFile $HOME/.ssh/id_ed25519" ]
  [ -z "$(stub_calls)" ]
}

@test "alias omits User, IdentityFile and the default port 22" {
  run_cli ssh alias bare example.com "" 22 "" < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Added alias 'bare' -> example.com."
  [ "$(ssh_config)" = "
Host bare
    HostName example.com" ]
}

@test "alias prompts for missing values and defaults the port to 18765" {
  # answers: name, hostname, user, port (empty = default), identity (empty)
  run_cli ssh alias <<< $'prompted\nhost.example.com\nroot\n\n\n'
  [ "$status" -eq 0 ]
  assert_output_contains "Added alias 'prompted' -> root@host.example.com."
  [ "$(ssh_config)" = "
Host prompted
    HostName host.example.com
    User root
    Port 18765" ]
}

@test "alias requires a name and a hostname" {
  run_cli ssh alias < /dev/null
  [ "$status" -eq 1 ]
  assert_output_contains "Alias name and HostName are required."
  [ ! -e "$HOME/$SSH_CONFIG_REL" ]
}

@test "alias refuses a duplicate name, case-insensitively" {
  run_cli ssh alias web example.com deploy 18765 "" < /dev/null
  [ "$status" -eq 0 ]
  run_cli ssh alias WEB other.example.com deploy 18765 "" < /dev/null
  [ "$status" -eq 1 ]
  assert_output_contains "Alias 'WEB' already exists in $HOME/$SSH_CONFIG_REL."
  [ "$(grep -c '^Host ' "$HOME/$SSH_CONFIG_REL")" = "1" ]
}

@test "alias appends to an existing config without touching other entries" {
  mkdir -p "$HOME/.ssh"
  printf 'Host *\n    ServerAliveInterval 60\n\nHost old\n    HostName old.example.com\n' > "$HOME/$SSH_CONFIG_REL"
  run_cli ssh alias new new.example.com "" 22 "" < /dev/null
  [ "$status" -eq 0 ]
  grep -q "^Host \*$" "$HOME/$SSH_CONFIG_REL"
  grep -q "^    HostName old.example.com$" "$HOME/$SSH_CONFIG_REL"
  [ "$(tail -n 2 "$HOME/$SSH_CONFIG_REL")" = "Host new
    HostName new.example.com" ]
}

# --- list -------------------------------------------------------------------

@test "list prints every alias and hides the Host * wildcard" {
  mkdir -p "$HOME/.ssh"
  printf 'Host *\n    ServerAliveInterval 60\n\nHost web\n    HostName a\n\n  host db\n    HostName b\n' > "$HOME/$SSH_CONFIG_REL"
  run_cli ssh list
  [ "$status" -eq 0 ]
  assert_output_contains "SSH aliases in $HOME/$SSH_CONFIG_REL:"
  assert_output_contains "  web"
  assert_output_contains "  db"
  refute_output_contains "*"
}

@test "list creates an empty config when there is none" {
  run_cli ssh list
  [ -f "$HOME/$SSH_CONFIG_REL" ]
  [ "$(mode_of "$HOME/$SSH_CONFIG_REL")" = "-rw-------" ]
  assert_output_contains "SSH aliases in"
}

# --- search -----------------------------------------------------------------

@test "search prints the matching Host block" {
  mkdir -p "$HOME/.ssh"
  printf 'Host web\n    HostName web.example.com\n    User deploy\n\nHost db\n    HostName db.example.com\n' > "$HOME/$SSH_CONFIG_REL"
  run_cli ssh search db
  [ "$status" -eq 0 ]
  [ "$output" = "Host db
    HostName db.example.com" ]
}

@test "search reports no match with exit 1" {
  mkdir -p "$HOME/.ssh"
  printf 'Host web\n    HostName web.example.com\n' > "$HOME/$SSH_CONFIG_REL"
  run_cli ssh search nothing
  [ "$status" -eq 1 ]
  assert_output_contains "No match for 'nothing'."
}

@test "search prompts for the pattern and requires one" {
  mkdir -p "$HOME/.ssh"
  printf 'Host web\n    HostName web.example.com\n' > "$HOME/$SSH_CONFIG_REL"
  run_cli ssh search <<< "web"
  [ "$status" -eq 0 ]
  assert_output_contains "HostName web.example.com"

  run_cli ssh search < /dev/null
  [ "$status" -eq 1 ]
  assert_output_contains "Search pattern is required."
}

# --- remove -----------------------------------------------------------------

@test "remove deletes only that Host block and keeps the others" {
  mkdir -p "$HOME/.ssh"
  printf 'Host web\n    HostName web.example.com\n    User deploy\nHost db\n    HostName db.example.com\nHost webmail\n    HostName mail.example.com\n' > "$HOME/$SSH_CONFIG_REL"
  run_cli ssh remove web < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Removed alias 'web'."
  [ "$(ssh_config)" = "Host db
    HostName db.example.com
Host webmail
    HostName mail.example.com" ]
  [ "$(mode_of "$HOME/$SSH_CONFIG_REL")" = "-rw-------" ]
  [ ! -e "$HOME/$SSH_CONFIG_REL.tmp" ]
}

@test "remove prompts for the name when none is given" {
  mkdir -p "$HOME/.ssh"
  printf 'Host web\n    HostName web.example.com\n' > "$HOME/$SSH_CONFIG_REL"
  run_cli ssh remove <<< "web"
  [ "$status" -eq 0 ]
  assert_output_contains "Removed alias 'web'."
  [ -z "$(ssh_config)" ]
}

@test "remove fails for an unknown alias and leaves the config untouched" {
  mkdir -p "$HOME/.ssh"
  printf 'Host web\n    HostName web.example.com\n' > "$HOME/$SSH_CONFIG_REL"
  run_cli ssh remove nope < /dev/null
  [ "$status" -eq 1 ]
  assert_output_contains "Alias 'nope' not found in $HOME/$SSH_CONFIG_REL."
  [ "$(ssh_config)" = "Host web
    HostName web.example.com" ]
}

@test "remove requires a name" {
  run_cli ssh remove < /dev/null
  [ "$status" -eq 1 ]
  assert_output_contains "Alias name is required."
}
