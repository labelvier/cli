#!/usr/bin/env bats
# inc/gitops.sh: the GitOps wizard for Laravel on SiteGround. gh, ssh, scp, ssh-keygen and
# composer are stubs; the tests assert on the recorded calls and on the files that get written.

load test_helper

setup() {
  setup_sandbox
  mkdir -p "$HOME/.ssh"
  printf 'Host prod\n  HostName c1.sgvps.net\n  User u1-abc\n  Port 18765\n' > "$HOME/.ssh/config"
  make_git_repo "$TEST_TMP/project" >/dev/null
  cd "$TEST_TMP/project"
  echo '{"require":{"laravel/framework":"^12.0"}}' > composer.json

  stub gh 'case "$1 $2" in "auth status") exit 0 ;; "repo view") echo acme/shop ;; "secret list") printf "DEPLOY_STAGING_PORT\tUpdated\n" ;; *) exit 0 ;; esac'
  stub composer
  stub scp
  stub ssh-keygen 'f=""; while [ $# -gt 0 ]; do [ "$1" = "-f" ] && f="$2"; shift; done
    echo "PRIVATE-KEY-BODY" > "$f"; echo "ssh-ed25519 AAAATEST gitops" > "$f.pub"'
  # Server: logs in, has php84, does not know the key yet, has shared/.env and .htaccess,
  # carries over .env from the old layout and has public_html as a real directory.
  stub ssh 'case "$*" in
    "-G prod") printf "hostname c1.sgvps.net\nuser u1-abc\nport 18765\n" ;;
    *"grep -qF"*) exit 1 ;;
    *"[ -L "*) echo dir ;;
    *"cd ~/www/example.com/app"*) echo .env ;;
  esac'
  export GITOPS_STATE_DIR="$TEST_TMP/state"
}
teardown() { teardown_sandbox; }

# Answers in prompt order: base branch, php version, composer require, ssh alias, domain, deploy path,
# web root, authorize key, public_html choice, create github secrets, create staging branch.
wizard_answers() {
  printf '%s\n' "" "" "y" "prod" "example.com" "" "" "y" "${1:-1}" "y" "n"
}

@test "gitops --help and subcommand help print the documentation" {
  run_cli gitops --help
  assert_output_contains "setup - Wizard"
  run_cli gitops status --help
  assert_output_contains "status - Show what is in place"
  [ -z "$(stub_calls)" ]
}

@test "gitops outside a Laravel project stops before touching anything" {
  echo '{"require":{}}' > composer.json
  run_cli gitops scaffold
  [ "$status" -eq 1 ]
  assert_output_contains "No Laravel project found"
  refute_stub_called '^ssh'
}

@test "gitops without a gh login stops" {
  stub gh 'case "$1 $2" in "auth status") exit 1 ;; esac'
  run_cli gitops scaffold
  [ "$status" -eq 1 ]
  assert_output_contains "GitHub CLI is not logged in"
}

@test "gitops scaffold writes deploy.php and the workflow with the placeholders filled in" {
  run_cli gitops scaffold <<< $'\n\nn\n'
  [ "$status" -eq 0 ]
  grep -q "set('application', 'shop')" deploy.php
  grep -q "/usr/local/bin/php84" deploy.php
  grep -q "git@github.com:acme/shop.git" deploy.php
  grep -q "branches: \[develop\]" .github/workflows/deploy-staging.yml
  grep -q "php-version: '8.4'" .github/workflows/deploy-staging.yml
  ! grep -rqE "__(APP|REPO_URL|PHP_BIN|PHP_VERSION|BASE_BRANCH)__" deploy.php .github/workflows/deploy-staging.yml
}

@test "gitops scaffold leaves existing files alone and does not ask again" {
  echo "// mine" > deploy.php
  mkdir -p .github/workflows && echo "mine" > .github/workflows/deploy-staging.yml
  run_cli gitops scaffold <<< "n"
  [ "$status" -eq 0 ]
  [ "$(cat deploy.php)" = "// mine" ]
  assert_output_contains "already exist"
}

@test "gitops scaffold requires deployer when it is missing and the answer is yes" {
  run_cli gitops scaffold <<< $'\n\ny\n'
  assert_stub_called '^composer require --dev deployer/deployer'
}

@test "gitops setup walks through the server, key, web root and GitHub" {
  run_cli gitops <<< "$(wizard_answers 1)"
  [ "$status" -eq 0 ]
  assert_output_contains "Step 6/6"
  # Deploy key: created outside the project, 600 for the private part, authorized on the server.
  [ -f "$TEST_TMP/state/acme_shop-staging" ]
  [ "$(file_mode "$TEST_TMP/state")" = "700" ]
  assert_stub_called "authorized_keys"
  assert_stub_called "-i $TEST_TMP/state/acme_shop-staging -o IdentitiesOnly=yes prod true"
  # Server layout: shared/ prepared, old .env carried over, existing public_html moved aside, never deleted.
  assert_stub_called "mkdir -p ~/www/example.com/app/shared/public"
  assert_stub_called "mv ~/www/example.com/public_html ~/www/example.com/public_html.bak-"
  refute_stub_called "rm -rf"
  # GitHub: environment and the five secrets, scoped to the environment.
  assert_stub_called "^gh api --method PUT repos/acme/shop/environments/staging"
  assert_stub_called "^gh secret set DEPLOY_STAGING_HOSTNAME --env staging --repo acme/shop --body c1.sgvps.net"
  assert_stub_called "^gh secret set DEPLOY_STAGING_USER --env staging --repo acme/shop --body u1-abc"
  assert_stub_called "^gh secret set DEPLOY_STAGING_PORT --env staging --repo acme/shop --body 18765"
  assert_stub_called "^gh secret set DEPLOY_STAGING_PATH --env staging --repo acme/shop --body ~/www/example.com/app"
  assert_stub_called "^gh secret set DEPLOY_STAGING_SSH_KEY --env staging --repo acme/shop"
}

@test "gitops setup never prints the private key or sends an .env to GitHub" {
  run_cli gitops <<< "$(wizard_answers 1)"
  refute_output_contains "PRIVATE-KEY-BODY"
  refute_stub_called "PRIVATE-KEY-BODY"
  refute_stub_called "^gh secret set .*ENV"
  refute_stub_called "^gh .*\.env"
}

@test "gitops setup deletes public_html only after the domain is typed" {
  run_cli gitops <<< "$(wizard_answers 2)"
  [ "$status" -ne 0 ]
  assert_output_contains "Not confirmed, nothing deleted"
  refute_stub_called "rm -rf"
  refute_stub_called "^gh secret set"
}

@test "gitops setup deletes public_html when the domain is typed" {
  run_cli gitops <<< $'\n\ny\nprod\nexample.com\n\n\ny\n2\nexample.com\ny\nn\n'
  [ "$status" -eq 0 ]
  assert_stub_called "rm -rf ~/www/example.com/public_html"
}

@test "gitops setup leaves a symlinked public_html alone" {
  stub ssh 'case "$*" in
    "-G prod") printf "hostname c1.sgvps.net\nuser u1-abc\nport 18765\n" ;;
    *"grep -qF"*) exit 1 ;;
    *"[ -L "*) echo link ;;
    *readlink*) echo /home/u1-abc/www/example.com/app/current/public ;;
  esac'
  run_cli gitops <<< $'\n\ny\nprod\nexample.com\n\n\ny\ny\nn\n'
  [ "$status" -eq 0 ]
  assert_output_contains "already a symlink"
  refute_stub_called "mv "
}

@test "gitops setup stops when the server login fails" {
  stub ssh 'case "$*" in "-G prod") echo "hostname h" ;; *) exit 255 ;; esac'
  run_cli gitops <<< $'\n\ny\nprod\n'
  [ "$status" -eq 1 ]
  assert_output_contains "Cannot log in as 'prod'"
  refute_stub_called "^gh secret set"
}

@test "gitops status lists what is missing" {
  run_cli gitops status
  assert_output_contains "deploy.php missing"
  assert_output_contains "no deploy key yet"
  assert_output_contains "secret DEPLOY_STAGING_PORT"
  assert_output_contains "secret DEPLOY_STAGING_SSH_KEY missing"
}
