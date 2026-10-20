#!/usr/bin/env bats
# inc/deploy.sh: staging/production deploys via npm scripts, the deploy log in
# git notes and the SiteGround cache purge over ssh. Git is real (a repo with a
# bare "origin" in the sandbox); npm and ssh are stubs.

load test_helper
setup()    { setup_sandbox; }
teardown() { teardown_sandbox; }

# A repo on master with a bare origin and master pushed with upstream, cwd inside it.
make_deploy_repo() {
  local repo remote="$TEST_TMP/remote.git"
  repo="$(make_git_repo)"
  git init -q --bare "$remote"
  git -C "$repo" remote add origin "$remote"
  git -C "$repo" push -q -u origin master 2>/dev/null
  cd "$repo"
}

# Write a .env with the production/staging deploy settings and commit + push it,
# so the working directory stays clean and HEAD still matches its upstream.
commit_env() {
  make_env "$@"
  git add .env
  git commit -q -m "env"
  git push -q origin master 2>/dev/null
}

full_env() {
  commit_env \
    "DEPLOY_STAGING_HOSTNAME=staging.example.com" \
    "DEPLOY_STAGING_USER=stage" \
    "DEPLOY_STAGING_PORT=18765" \
    "DEPLOY_STAGING_PATH=/home/stage/www/wp-content/themes/site" \
    'DEPLOY_PRODUCTION_HOSTNAME="prod.example.com"' \
    "DEPLOY_PRODUCTION_USER=deploy" \
    "DEPLOY_PRODUCTION_PORT=18765" \
    "DEPLOY_PRODUCTION_PATH='/home/deploy/www/wp-content/themes/site'"
}

# npm stub: `npm pkg get scripts` reports both deploy scripts, everything else succeeds.
stub_npm_with_scripts() {
  stub npm 'case "$1" in pkg) echo "{\"deploy\": \"rsync\", \"deploy-staging\": \"rsync\"}" ;; esac; exit 0'
}

# Exact (fixed string) match on one recorded stub call line.
assert_stub_line() {
  stub_calls | grep -qF -- "$1" || {
    echo "expected a stub call line containing: $1" >&2
    echo "recorded calls:" >&2
    stub_calls >&2
    return 1
  }
}

PROD_PURGE="ssh -p 18765 -o ConnectTimeout=10 deploy@prod.example.com cd '/home/deploy/www/wp-content/themes/site' 2>/dev/null || exit 3; command -v wp >/dev/null 2>&1 || exit 4; wp help sg >/dev/null 2>&1 || exit 5; wp sg purge"
STAGING_PURGE="ssh -p 18765 -o ConnectTimeout=10 stage@staging.example.com cd '/home/stage/www/wp-content/themes/site' 2>/dev/null || exit 3; command -v wp >/dev/null 2>&1 || exit 4; wp help sg >/dev/null 2>&1 || exit 5; wp sg purge"

# --- dispatch ---------------------------------------------------------------

@test "bare deploy prints the docs and runs nothing" {
  stub npm; stub ssh
  run_cli deploy
  assert_output_contains "Available functions:"
  assert_output_contains "staging"
  assert_output_contains "production"
  assert_output_contains "log"
  [ -z "$(stub_calls)" ]
}

@test "staging --help prints its description without deploying" {
  stub npm; stub ssh
  run_cli deploy staging --help
  [ "$status" -eq 0 ]
  assert_output_contains "staging"
  assert_output_contains "--skip-purge"
  [ -z "$(stub_calls)" ]
}

@test "production --help prints its description without deploying" {
  stub npm; stub ssh
  run_cli deploy production --help
  [ "$status" -eq 0 ]
  assert_output_contains "production"
  assert_output_contains "--force"
  assert_output_contains "--yes"
  [ -z "$(stub_calls)" ]
}

@test "log --help prints its description" {
  run_cli deploy log --help
  [ "$status" -eq 0 ]
  assert_output_contains "log"
  assert_output_contains "latest first"
}

@test "unknown subcommand is reported" {
  stub npm; stub ssh
  run_cli deploy nope
  [ "$status" -eq 1 ]
  assert_output_contains "Unknown command: nope"
}

# --- _env_value -------------------------------------------------------------

@test "_env_value strips quotes and takes the last definition" {
  load_cli
  make_env 'A=one' 'B="two words"' "C='three'" 'A=last' 'D=x=y'
  run deploy _env_value A
  [ "$output" = "last" ]
  run deploy _env_value B
  [ "$output" = "two words" ]
  run deploy _env_value C
  [ "$output" = "three" ]
  run deploy _env_value D
  [ "$output" = "x=y" ]
  run deploy _env_value MISSING
  [ -z "$output" ]
}

@test "_env_value fails without a .env" {
  load_cli
  run deploy _env_value A
  [ "$status" -eq 1 ]
}

# --- staging ----------------------------------------------------------------

@test "staging aborts when the deploy-staging npm script is missing" {
  stub npm 'case "$1" in pkg) echo "{}" ;; esac'
  stub ssh
  make_deploy_repo
  full_env
  run_cli deploy staging
  [ "$status" -eq 1 ]
  assert_output_contains "npm script 'deploy-staging' not found"
  refute_stub_called '^npm run'
  refute_stub_called '^ssh'
}

@test "staging aborts on uncommitted changes" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  full_env
  echo "dirty" > README.md
  run_cli deploy staging
  [ "$status" -eq 1 ]
  assert_output_contains "There are uncommitted changes"
  refute_stub_called '^npm run'
  refute_stub_called '^ssh'
}

@test "staging merges, pushes, deploys and purges in that order, then returns to the branch" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  full_env
  git checkout -q -b feature/thing
  echo "feature" > feature.txt
  git add feature.txt && git commit -q -m "feature"

  run_cli deploy staging
  [ "$status" -eq 0 ]
  assert_output_contains "Purging the SiteGround cache on staging.example.com"
  assert_output_contains "SiteGround cache purged."

  # exact calls, in order
  [ "$(stub_calls | sed -n 1p)" = "npm pkg get scripts" ]
  [ "$(stub_calls | sed -n 2p)" = "npm run deploy-staging" ]
  [ "$(stub_calls | sed -n 3p)" = "$STAGING_PURGE" ]
  [ "$(stub_calls | wc -l | tr -d ' ')" = "3" ]

  # back on the feature branch, staging pushed to origin with the feature commit
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature/thing" ]
  git rev-parse --verify -q origin/staging >/dev/null
  git merge-base --is-ancestor feature/thing origin/staging
}

@test "staging merges the current branch into an existing origin/staging" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  full_env
  git branch staging
  git push -q origin staging 2>/dev/null
  git branch -D staging
  git checkout -q -b feature/one
  echo "one" > one.txt && git add one.txt && git commit -q -m "one"

  run_cli deploy staging
  [ "$status" -eq 0 ]
  assert_output_contains "Merge feature/one into staging"
  git merge-base --is-ancestor feature/one origin/staging
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature/one" ]
}

@test "staging --all-features also merges the other feature branches" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  full_env
  git checkout -q -b feature/one
  echo "one" > one.txt && git add one.txt && git commit -q -m "one"
  git checkout -q master
  git checkout -q -b feature/two
  echo "two" > two.txt && git add two.txt && git commit -q -m "two"

  run_cli deploy staging --all-features
  [ "$status" -eq 0 ]
  assert_output_contains "Deploying all feature branches to staging"
  assert_output_contains "Merge feature/one into staging"
  git merge-base --is-ancestor feature/one origin/staging
  git merge-base --is-ancestor feature/two origin/staging
}

@test "staging --skip-purge deploys without touching the server" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  full_env
  run_cli deploy staging --skip-purge
  [ "$status" -eq 0 ]
  assert_stub_called '^npm run deploy-staging$'
  refute_stub_called '^ssh'
  refute_output_contains "Purging"
}

@test "staging aborts when npm run deploy-staging fails and does not purge" {
  stub npm 'case "$1" in pkg) echo "{\"deploy-staging\": \"x\"}" ;; run) exit 2 ;; esac'
  stub ssh
  make_deploy_repo
  full_env
  run_cli deploy staging
  [ "$status" -eq 1 ]
  assert_output_contains "npm run deploy-staging failed, aborting deploy"
  refute_stub_called '^ssh'
}

@test "staging skips the purge with a message when .env has no staging server" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  commit_env "DEPLOY_PRODUCTION_HOSTNAME=prod.example.com"
  run_cli deploy staging
  [ "$status" -eq 0 ]
  assert_output_contains "No DEPLOY_STAGING_HOSTNAME/USER/PATH in .env, skipping the cache purge."
  refute_stub_called '^ssh'
}

# --- production -------------------------------------------------------------

@test "production refuses outside a git repository" {
  stub npm; stub ssh
  run_cli deploy production
  [ "$status" -eq 1 ]
  assert_output_contains "not in a git repository"
  [ -z "$(stub_calls)" ]
}

@test "production aborts when the deploy npm script is missing" {
  stub npm 'case "$1" in pkg) echo "{\"deploy-staging\": \"x\"}" ;; esac'
  stub ssh
  make_deploy_repo
  full_env
  run_cli deploy production
  [ "$status" -eq 1 ]
  assert_output_contains "npm script 'deploy' not found"
  refute_stub_called '^npm run'
}

@test "production refuses from a feature branch" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  full_env
  git checkout -q -b feature/nope
  run_cli deploy production <<< "y"
  [ "$status" -eq 1 ]
  assert_output_contains "You are on feature/nope. Only deploy production from master/main or a release/* branch"
  refute_stub_called '^npm run'
  refute_stub_called '^ssh'
}

@test "production refuses when master differs from its remote" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  full_env
  echo "ahead" > ahead.txt && git add ahead.txt && git commit -q -m "ahead"
  run_cli deploy production <<< "y"
  [ "$status" -eq 1 ]
  assert_output_contains "master differs from its remote"
  refute_stub_called '^npm run'
}

@test "production asks for confirmation and aborts on n" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  full_env
  run_cli deploy production <<< "n"
  [ "$status" -eq 1 ]
  assert_output_contains "Deploying to the production environment:"
  assert_output_contains "Project: repo"
  assert_output_contains "Branch:  master"
  assert_output_contains "Aborting deploy."
  refute_stub_called '^npm run'
  refute_stub_called '^ssh'
}

@test "production deploys on y, logs it and purges the SiteGround cache" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  full_env
  git tag 1.2.3
  run_cli deploy production <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "Version: 1.2.3"
  assert_output_contains "Deployed repo 1.2.3 to the production environment."
  assert_output_contains "Purging the SiteGround cache on prod.example.com"
  assert_output_contains "SiteGround cache purged."

  [ "$(stub_calls | sed -n 1p)" = "npm pkg get scripts" ]
  [ "$(stub_calls | sed -n 2p)" = "npm run deploy" ]
  [ "$(stub_calls | sed -n 3p)" = "$PROD_PURGE" ]

  # the record is in the deploys notes ref, locally and on origin
  local record
  record="$(git notes --ref=deploys show HEAD)"
  echo "$record" | grep -q "| production | 1.2.3 | $(git rev-parse --short HEAD) | master | Test <test@example.com> | success$"
  git -C "$TEST_TMP/remote.git" show refs/notes/deploys >/dev/null
}

@test "production --yes skips the question" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  full_env
  run_cli deploy production --yes < /dev/null
  [ "$status" -eq 0 ]
  refute_output_contains "Deploy this to the LIVE environment?"
  assert_stub_called '^npm run deploy$'
}

@test "production --force deploys from any branch with uncommitted changes" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  full_env
  git checkout -q -b feature/hotfix
  echo "dirty" > README.md
  run_cli deploy production --force --yes < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Warning: feature/hotfix has no upstream"
  assert_stub_called '^npm run deploy$'
}

@test "production from a release branch takes the version from the branch name" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  full_env
  git checkout -q -b release/2.0.0
  run_cli deploy production --yes < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Version: 2.0.0"
  git notes --ref=deploys show HEAD | grep -q "| 2.0.0 | .* | release/2.0.0 |"
}

@test "production keeps the npm exit code on failure, logs it and does not purge" {
  stub npm 'case "$1" in pkg) echo "{\"deploy\": \"x\"}" ;; run) exit 3 ;; esac'
  stub ssh
  make_deploy_repo
  full_env
  run_cli deploy production <<< "y"
  [ "$status" -eq 3 ]
  assert_output_contains "npm run deploy failed with exit code 3."
  git notes --ref=deploys show HEAD | grep -q "| failed$"
  refute_stub_called '^ssh'
  refute_output_contains "Purging"
}

@test "production --skip-purge leaves the cache alone" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  full_env
  run_cli deploy production --yes --skip-purge < /dev/null
  [ "$status" -eq 0 ]
  assert_stub_called '^npm run deploy$'
  refute_stub_called '^ssh'
  refute_output_contains "Purging"
}

# --- the purge itself -------------------------------------------------------

@test "purge is skipped with a message when there is no .env" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  run_cli deploy production --yes < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "No DEPLOY_PRODUCTION_HOSTNAME/USER/PATH in .env, skipping the cache purge."
  refute_stub_called '^ssh'
}

@test "purge is skipped when .env lacks the user or path" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  commit_env "DEPLOY_PRODUCTION_HOSTNAME=prod.example.com" "DEPLOY_PRODUCTION_PORT=18765"
  run_cli deploy production --yes < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "No DEPLOY_PRODUCTION_HOSTNAME/USER/PATH in .env, skipping the cache purge."
  refute_stub_called '^ssh'
}

@test "purge omits -p when .env has no port" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  commit_env "DEPLOY_PRODUCTION_HOSTNAME=prod.example.com" "DEPLOY_PRODUCTION_USER=deploy" "DEPLOY_PRODUCTION_PATH=/www/theme"
  run_cli deploy production --yes < /dev/null
  [ "$status" -eq 0 ]
  assert_stub_line "ssh -o ConnectTimeout=10 deploy@prod.example.com cd '/www/theme' 2>/dev/null || exit 3;"
  refute_stub_called '^ssh -p'
}

@test "purge is skipped when the server has no wp-cli (probe exit 4)" {
  stub_npm_with_scripts
  stub ssh 'exit 4'
  make_deploy_repo
  full_env
  run_cli deploy production --yes < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "No wp-cli on prod.example.com, skipping the cache purge."
  refute_output_contains "cache purged"
}

@test "purge is skipped when the server has no wp sg (probe exit 5)" {
  stub_npm_with_scripts
  stub ssh 'exit 5'
  make_deploy_repo
  full_env
  run_cli deploy production --yes < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "No 'wp sg' (SiteGround Optimizer) on prod.example.com, skipping the cache purge."
}

@test "purge reports a missing deploy path (exit 3) without failing the deploy" {
  stub_npm_with_scripts
  stub ssh 'exit 3'
  make_deploy_repo
  full_env
  run_cli deploy production --yes < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Could not find /home/deploy/www/wp-content/themes/site on prod.example.com, cache not purged."
}

@test "a failed purge never fails the deploy" {
  stub_npm_with_scripts
  stub ssh 'exit 255'
  make_deploy_repo
  full_env
  run_cli deploy production --yes < /dev/null
  [ "$status" -eq 0 ]
  assert_output_contains "Deployed repo unknown to the production environment."
  assert_output_contains "Purging the SiteGround cache failed, purge it manually: wp sg purge"
  assert_stub_line "$PROD_PURGE"
}

# --- log --------------------------------------------------------------------

@test "log refuses outside a git repository" {
  run_cli deploy log
  [ "$status" -eq 1 ]
  assert_output_contains "not in a git repository"
}

@test "log says so when nothing was deployed yet" {
  make_deploy_repo
  run_cli deploy log
  [ "$status" -eq 0 ]
  assert_output_contains "No production deployments logged for this project yet."
}

@test "log lists the production deployments, latest first and limited by amount" {
  stub_npm_with_scripts; stub ssh
  make_deploy_repo
  full_env
  git notes --ref=deploys append -m "2024-01-01T10:00:00Z | production | 1.0.0 | abc1234 | master | Test <test@example.com> | success"
  git notes --ref=deploys append -m "2024-02-01T10:00:00Z | production | 1.1.0 | def5678 | master | Test <test@example.com> | success"
  git push -q origin refs/notes/deploys 2>/dev/null

  run_cli deploy log
  [ "$status" -eq 0 ]
  assert_output_contains "Production deployments of repo:"
  [ "$(plain_output | sed -n 2p)" = "2024-02-01T10:00:00Z | production | 1.1.0 | def5678 | master | Test <test@example.com> | success" ]
  [ "$(plain_output | sed -n 3p)" = "2024-01-01T10:00:00Z | production | 1.0.0 | abc1234 | master | Test <test@example.com> | success" ]

  run_cli deploy log 1
  [ "$status" -eq 0 ]
  assert_output_contains "1.1.0"
  refute_output_contains "1.0.0"
}
