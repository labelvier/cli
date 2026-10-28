#!/usr/bin/env bats
# inc/gitops.sh: the GitOps wizard for Laravel on SiteGround. gh, ssh, scp, ssh-keygen and
# composer are stubs; the tests assert on the recorded calls and on the files that get written.

load test_helper

setup() {
  setup_sandbox
  mkdir -p "$HOME/.ssh"
  make_git_repo "$TEST_TMP/project" >/dev/null
  cd "$TEST_TMP/project"
  echo '{"require":{"laravel/framework":"^12.0"}}' > composer.json

  stub gh 'case "$1 $2" in "auth status") exit 0 ;; "repo view") echo acme/shop ;; "secret list") printf "DEPLOY_STAGING_PORT\tUpdated\n" ;; *) exit 0 ;; esac'
  stub composer
  stub scp
  # SiteGround knows example.com; the stub replaces the siteground function, which would win over a stub on PATH.
  stub siteground-stub 'case "$1" in site:ssh) echo "ssh -p 18765 u1-abc@c1.sgvps.net" ;; *) exit 0 ;; esac'
  export GITOPS_SITEGROUND=siteground-stub
  stub ssh-keygen 'f=""; while [ $# -gt 0 ]; do [ "$1" = "-f" ] && f="$2"; shift; done
    echo "PRIVATE-KEY-BODY" > "$f"; echo "ssh-ed25519 AAAATEST gitops" > "$f.pub"'
  # Server: logs in, default php is 8.4, does not know the key yet, has shared/.env and .htaccess,
  # carries over .env from the old layout and has public_html as a real directory.
  stub ssh 'case "$*" in
    *"php -v"*) printf "PHP 8.4.2 (cli)\n" ;;
    *"grep -qF"*) exit 1 ;;
    *"[ -L "*) echo dir ;;
    *"cd ~/www/example.com"*) echo .env ;;
  esac'
  export GITOPS_STATE_DIR="$TEST_TMP/state"
}
teardown() { teardown_sandbox; }

# Answers in prompt order: domain, base branch, composer require,
# authorize key, public_html choice, create github secrets, create staging branch, commit files.
wizard_answers() {
  printf '%s\n' "example.com" "" "y" "y" "${1:-1}" "y" "n" "n"
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
  run_cli gitops scaffold <<< $'\n8.4\nn\n'
  [ "$status" -eq 0 ]
  grep -q "set('application', 'shop')" deploy.php
  ! grep -q "bin/php" deploy.php
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
  run_cli gitops scaffold <<< $'\n8.4\ny\n'
  assert_stub_called '^composer require --dev deployer/deployer'
}

@test "gitops setup walks through the server, key, web root and GitHub" {
  run_cli gitops <<< "$(wizard_answers 1)"
  [ "$status" -eq 0 ]
  assert_output_contains "Step 8/8"
  # Deploy key: created outside the project, 600 for the private part, authorized on the server.
  [ -f "$TEST_TMP/state/acme_shop-staging" ]
  [ "$(file_mode "$TEST_TMP/state")" = "700" ]
  assert_stub_called "authorized_keys"
  assert_stub_called "-p 18765 -i $TEST_TMP/state/acme_shop-staging -o IdentitiesOnly=yes u1-abc@c1.sgvps.net true"
  # Server layout: shared/ prepared, old .env carried over, existing public_html moved aside, never deleted.
  assert_stub_called "mkdir -p ~/www/example.com/shared/public"
  assert_stub_called "mv ~/www/example.com/public_html ~/www/example.com/public_html.bak-"
  refute_stub_called "rm -rf"
  # GitHub: environment and the five secrets, scoped to the environment.
  assert_stub_called "^gh api --method PUT repos/acme/shop/environments/staging"
  assert_stub_called "^gh secret set DEPLOY_STAGING_HOSTNAME --env staging --repo acme/shop --body c1.sgvps.net"
  assert_stub_called "^gh secret set DEPLOY_STAGING_USER --env staging --repo acme/shop --body u1-abc"
  assert_stub_called "^gh secret set DEPLOY_STAGING_PORT --env staging --repo acme/shop --body 18765"
  assert_stub_called "^gh secret set DEPLOY_STAGING_PATH --env staging --repo acme/shop --body ~/www/example.com"
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
  run_cli gitops <<< $'example.com\n\ny\ny\n2\nexample.com\ny\nn\nn\n'
  [ "$status" -eq 0 ]
  assert_stub_called "rm -rf ~/www/example.com/public_html"
}

@test "gitops setup leaves a symlinked public_html alone" {
  stub ssh 'case "$*" in
    *"php -v"*) printf "PHP 8.4.2 (cli)\n" ;;
    *"grep -qF"*) exit 1 ;;
    *"[ -L "*) echo link ;;
    *readlink*) echo /home/u1-abc/www/example.com/app/current/public ;;
  esac'
  run_cli gitops <<< $'example.com\n\ny\ny\ny\nn\nn\n'
  [ "$status" -eq 0 ]
  assert_output_contains "already a symlink"
  refute_stub_called "mv "
}

@test "gitops setup stops when SiteGround does not know the domain" {
  stub siteground-stub 'exit 1'
  run_cli gitops <<< $'nope.example\n'
  [ "$status" -eq 1 ]
  assert_output_contains "SiteGround does not know 'nope.example'"
  refute_stub_called "^ssh"
  refute_stub_called "^gh secret set"
}

@test "gitops setup uses the SiteGround host and checks your own key" {
  run_cli gitops <<< "$(wizard_answers 1)"
  assert_output_contains "example.com found in SiteGround: u1-abc@c1.sgvps.net:18765"
  assert_output_contains "Your own SSH key can log in"
  assert_stub_called "^siteground-stub site:ssh example.com"
  refute_stub_called "site:ssh-key"
}

@test "gitops setup offers to authorize your key when the login fails" {
  stub ssh 'exit 255'
  run_cli gitops <<< $'example.com\ny\n'
  [ "$status" -eq 1 ]
  assert_output_contains "Your own SSH key cannot log in yet"
  assert_stub_called "^siteground-stub site:ssh-key example.com"
  assert_output_contains "Still cannot log in as u1-abc@c1.sgvps.net:18765"
  refute_stub_called "^gh secret set"
}

@test "gitops setup stops when authorizing your key is declined" {
  stub ssh 'exit 255'
  run_cli gitops <<< $'example.com\nn\n'
  [ "$status" -eq 1 ]
  refute_stub_called "site:ssh-key"
}

@test "gitops status lists what is missing" {
  run_cli gitops status
  assert_output_contains "deploy.php missing"
  assert_output_contains "no deploy key yet"
  assert_output_contains "secret DEPLOY_STAGING_PORT"
  assert_output_contains "secret DEPLOY_STAGING_SSH_KEY missing"
}

# Project that needs PHP 8.3 on a server whose default php is 8.1.
php_too_old() {
  echo '{"require":{"php":"^8.3","laravel/framework":"^12.0"}}' > composer.json
  stub ssh 'case "$*" in
    *"php -v"*) cat "$TEST_TMP/server-php" ;;
    *"grep -qF"*) exit 1 ;;
  esac'
  echo "PHP 8.1.9 (cli)" > "$TEST_TMP/server-php"
}

@test "gitops setup warns when the default server PHP is too old and offers siteground" {
  php_too_old
  run_cli gitops <<< $'example.com\ny\n8.3\nn\n'
  assert_output_contains "Server PHP is 8.1, the project needs >= 8.3"
  assert_stub_called "^siteground-stub site:php example.com --php 8.3"
}

@test "gitops setup leaves PHP alone when the update is declined" {
  php_too_old
  run_cli gitops <<< $'example.com\nn\n\nn\n'
  assert_output_contains "Fix it in Site Tools"
  refute_stub_called "site:php"
}

@test "gitops setup is quiet about PHP when the default version is new enough" {
  run_cli gitops <<< "$(wizard_answers 1)"
  assert_output_contains "Server PHP 8.4"
  refute_output_contains "needs >="
}

# A project with the files written by the wizard, a bare origin and the answers up to the publish step.
publish_setup() {
  git init -q --bare "$TEST_TMP/origin.git"
  git remote add origin "$TEST_TMP/origin.git"
  git push -q origin master develop
}

@test "gitops setup commits the files and pushes to the base branch when asked" {
  publish_setup
  git checkout -q develop
  run_cli gitops <<< "$(printf '%s\n' example.com "" y y 1 y n y y)"
  [ "$status" -eq 0 ]
  assert_output_contains "Step 8/8 · Activate GitOps"
  [ "$(git log -1 --format=%s)" = "ci: deploy staging with Deployer via GitHub Actions" ]
  [ "$(git rev-parse develop)" = "$(git --git-dir="$TEST_TMP/origin.git" rev-parse develop)" ]
  assert_output_contains "GitHub Actions deploys from now on"
}

@test "gitops setup pushes a feature branch to the base branch only as a fast-forward" {
  publish_setup
  git checkout -q -b feature/x
  run_cli gitops <<< "$(printf '%s\n' example.com "" y y 1 y n y y)"
  [ "$status" -eq 0 ]
  [ "$(git rev-parse feature/x)" = "$(git --git-dir="$TEST_TMP/origin.git" rev-parse develop)" ]
}

@test "gitops setup leaves everything unpushed when the push is declined" {
  publish_setup
  git checkout -q develop
  run_cli gitops <<< "$(printf '%s\n' example.com "" y y 1 y n y n)"
  assert_output_contains "Not pushed"
  [ "$(git rev-parse develop)" != "$(git --git-dir="$TEST_TMP/origin.git" rev-parse develop)" ]
}
