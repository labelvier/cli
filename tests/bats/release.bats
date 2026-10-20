#!/usr/bin/env bats
# inc/release.sh: start, cancel/abort, finish and merge-features, with real
# git inside a sandbox repository and a local bare remote for every push.

load test_helper
setup() {
  setup_sandbox
  # Non-fast-forward merges must never wait for an editor.
  export GIT_EDITOR=true
  REPO="$(make_git_repo)"
  cd "$REPO"
}
teardown() { teardown_sandbox; }

# Current branch of $REPO.
current_branch() { git -C "$REPO" symbolic-ref --short HEAD; }

# Subject of the last commit on the current branch of $REPO.
last_commit_subject() { git -C "$REPO" log -1 --pretty=%s; }

# Switch $REPO to develop, the branch `release start` expects.
on_develop() { git -C "$REPO" checkout -q develop; }

# Give $REPO a local bare remote (origin) with master and develop pushed and
# tracked, so `git push` inside the CLI lands there instead of on the network.
add_bare_remote() {
  BARE="$TEST_TMP/origin.git"
  git clone -q --bare "$REPO" "$BARE"
  git -C "$REPO" remote add origin "$BARE"
  git -C "$REPO" push -q -u origin master develop
}

# Commit a file on the current branch of $REPO.
commit_file() {
  echo "$2" > "$REPO/$1"
  git -C "$REPO" add "$1"
  git -C "$REPO" commit -q -m "add $1"
}

# A WordPress theme layout the way the .env + style.scss lookup expects it.
make_theme_with_version() {
  local theme_path="/wp-content/themes/demo" version="$1"
  make_env "DEV_THEME_PATH=$theme_path"
  mkdir -p ".$theme_path/src/scss"
  printf '/*\nTheme Name: Demo\nVersion: %s\n*/\n' "$version" > ".$theme_path/src/scss/style.scss"
  git add -A && git commit -q -m "theme"
}

make_package_json() {
  printf '{\n  "name": "demo",\n  "version": "%s"\n}\n' "$1" > package.json
  git add package.json && git commit -q -m "package.json"
}

# --- docs and dispatch -----------------------------------------------------

@test "release without a subcommand prints its documentation" {
  run_cli release
  assert_output_contains "Available functions:"
  assert_output_contains "start"
  assert_output_contains "cancel"
  assert_output_contains "finish"
  assert_output_contains "merge-features"
}

@test "release start --help prints the description and does not start a release" {
  on_develop
  run_cli release start --help
  [ "$status" -eq 0 ]
  assert_output_contains "start <optional-version>"
  assert_output_contains "Creates a new release branch"
  [ "$(current_branch)" = "develop" ]
}

@test "bare release exits 0" {
  skip "bug: _echo_documentation ends on a failing read, so a bare 'release' exits 1 instead of 0"
  run_cli release
  [ "$status" -eq 0 ]
}

@test "release with an unknown subcommand is reported" {
  run_cli release nope
  [ "$status" -eq 1 ]
  assert_output_contains "Unknown command: nope"
}

# --- start: guards ---------------------------------------------------------

@test "start refuses outside a git repository" {
  mkdir "$TEST_TMP/plain" && cd "$TEST_TMP/plain"
  run_cli release start
  [ "$status" -eq 1 ]
  assert_output_contains "You are not in a git repository"
}

@test "start refuses when not on develop" {
  [ "$(current_branch)" = "master" ]
  run_cli release start 1.0.0
  [ "$status" -eq 1 ]
  assert_output_contains "You are not on the develop branch"
  [ "$(current_branch)" = "master" ]
  ! git show-ref --verify --quiet refs/heads/release/1.0.0
}

@test "start --force starts a release from another branch" {
  make_package_json 1.0.0
  [ "$(current_branch)" = "master" ]
  run_cli release start --force <<< "y"
  [ "$status" -eq 0 ]
  [ "$(current_branch)" = "release/1.0.1" ]
}

@test "start refuses when the release branch already exists" {
  on_develop
  git branch release/2.0.0
  run_cli release start 2.0.0
  [ "$status" -eq 1 ]
  assert_output_contains "Release branch release/2.0.0 already exists"
  [ "$(current_branch)" = "develop" ]
}

@test "start refuses a non-semantic target version" {
  on_develop
  make_package_json 1.0.0
  run_cli release start banana
  [ "$status" -eq 1 ]
  assert_output_contains "Target version banana is not semantic"
  [ "$(current_branch)" = "develop" ]
}

@test "start refuses when the detected current version is not semantic" {
  on_develop
  make_package_json next
  run_cli release start
  [ "$status" -eq 1 ]
  assert_output_contains "Version next is not semantic"
}

# --- start: version detection order ----------------------------------------

@test "start takes the version from the theme style.scss named in .env" {
  on_develop
  make_theme_with_version 1.2.3
  make_package_json 9.9.9
  run_cli release start
  [ "$status" -eq 0 ]
  assert_output_contains "Found version 1.2.3 in"
  assert_output_contains "New version: 1.2.4"
  [ "$(current_branch)" = "release/1.2.4" ]
  grep -q "Version: 1.2.4" wp-content/themes/demo/src/scss/style.scss
  [ "$(last_commit_subject)" = "Updated version in wp-content/themes/demo/src/scss/style.scss to 1.2.4" ]
  # package.json is not touched when the theme file is the source
  grep -q '"version": "9.9.9"' package.json
  [ -z "$(git status --porcelain)" ]
}

@test "start falls back to the theme style.css when there is no style.scss" {
  on_develop
  make_env "DEV_THEME_PATH=/wp-content/themes/demo"
  mkdir -p wp-content/themes/demo
  printf '/*\nVersion: 3.0.0\n*/\n' > wp-content/themes/demo/style.css
  git add -A && git commit -q -m theme
  run_cli release start
  [ "$status" -eq 0 ]
  assert_output_contains "Found version 3.0.0 in"
  [ "$(current_branch)" = "release/3.0.1" ]
  grep -q "Version: 3.0.1" wp-content/themes/demo/style.css
}

@test "start falls back to package.json and asks before bumping it" {
  on_develop
  make_package_json 1.0.0
  run_cli release start <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "No .env file found"
  assert_output_contains "Found version 1.0.0 in package.json"
  [ "$(current_branch)" = "release/1.0.1" ]
  grep -q '"version": "1.0.1"' package.json
  [ "$(last_commit_subject)" = "chore(package.json): updated version to 1.0.1" ]
  [ -z "$(git status --porcelain)" ]
}

@test "start leaves package.json alone when the bump is declined" {
  on_develop
  make_package_json 1.0.0
  run_cli release start <<< "n"
  [ "$status" -eq 0 ]
  assert_output_contains "Leaving package.json at 1.0.0"
  [ "$(current_branch)" = "release/1.0.1" ]
  grep -q '"version": "1.0.0"' package.json
  [ "$(last_commit_subject)" = "package.json" ]
}

@test "start falls back to a VERSION file after package.json" {
  on_develop
  commit_file VERSION 2.5.0
  run_cli release start <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "No package.json file found"
  assert_output_contains "Found version 2.5.0 in VERSION"
  [ "$(current_branch)" = "release/2.5.1" ]
  [ "$(cat VERSION)" = "2.5.1" ]
  [ "$(last_commit_subject)" = "chore(VERSION): updated version to 2.5.1" ]
}

@test "start prefers package.json over a VERSION file" {
  on_develop
  make_package_json 1.0.0
  commit_file VERSION 5.0.0
  run_cli release start <<< "y"
  [ "$status" -eq 0 ]
  [ "$(current_branch)" = "release/1.0.1" ]
  [ "$(cat VERSION)" = "5.0.0" ]
}

@test "start without any version source offers to create a VERSION file" {
  on_develop
  # Enter = yes to creating the file, then the current version.
  run_cli release start < <(printf '\n2.0.0\n')
  [ "$status" -eq 0 ]
  assert_output_contains "No VERSION file found"
  [ "$(current_branch)" = "release/2.0.0" ]
  [ "$(cat VERSION)" = "2.0.0" ]
  [ "$(last_commit_subject)" = "chore(VERSION): add VERSION file with 2.0.0" ]
}

@test "start without any version source defaults the created VERSION file to 1.0.0" {
  on_develop
  run_cli release start < <(printf '\n\n')
  [ "$status" -eq 0 ]
  [ "$(current_branch)" = "release/1.0.0" ]
  [ "$(cat VERSION)" = "1.0.0" ]
}

@test "start without any version source exits when no VERSION file is wanted" {
  on_develop
  run_cli release start <<< "n"
  [ "$status" -eq 1 ]
  assert_output_contains "give the new version: labelvier release start <version>"
  [ "$(current_branch)" = "develop" ]
  [ ! -f VERSION ]
}

@test "start with an explicit version but no source offers a VERSION file for next time" {
  on_develop
  run_cli release start 4.0.0 <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "Custom version given: 4.0.0"
  [ "$(current_branch)" = "release/4.0.0" ]
  [ "$(cat VERSION)" = "4.0.0" ]
  [ "$(last_commit_subject)" = "chore(VERSION): add VERSION file with 4.0.0" ]
}

@test "start with an explicit version and no source can skip the VERSION file" {
  on_develop
  run_cli release start 4.0.0 <<< "n"
  [ "$status" -eq 0 ]
  [ "$(current_branch)" = "release/4.0.0" ]
  [ ! -f VERSION ]
  [ "$(last_commit_subject)" = "initial" ]
}

# --- start: bump flags -----------------------------------------------------

@test "start with an explicit version uses it instead of bumping" {
  on_develop
  make_package_json 1.0.0
  run_cli release start 3.1.4 <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "Custom version given: 3.1.4"
  assert_output_contains "New version: 3.1.4"
  [ "$(current_branch)" = "release/3.1.4" ]
  grep -q '"version": "3.1.4"' package.json
  [ "$(last_commit_subject)" = "chore(package.json): updated version to 3.1.4" ]
}

@test "start bumps the patch version by default" {
  on_develop
  make_package_json 1.2.3
  run_cli release start <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "New version: 1.2.4"
  [ "$(current_branch)" = "release/1.2.4" ]
}

@test "start --minor bumps the minor version and resets patch" {
  on_develop
  make_package_json 1.2.3
  run_cli release start --minor <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "New version: 1.3.0"
  [ "$(current_branch)" = "release/1.3.0" ]
  grep -q '"version": "1.3.0"' package.json
}

@test "start --major bumps the major version and resets the rest" {
  on_develop
  make_package_json 1.2.3
  run_cli release start --major <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "New version: 2.0.0"
  [ "$(current_branch)" = "release/2.0.0" ]
  grep -q '"version": "2.0.0"' package.json
}

@test "start keeps a pre-release suffix when bumping the patch" {
  on_develop
  make_theme_with_version "1.2.3-beta"
  run_cli release start
  [ "$status" -eq 0 ]
  assert_output_contains "New version: 1.2.4-beta"
  [ "$(current_branch)" = "release/1.2.4-beta" ]
  grep -q "Version: 1.2.4-beta" wp-content/themes/demo/src/scss/style.scss
}

@test "start creates the release branch from develop" {
  on_develop
  commit_file develop.txt "only on develop"
  make_package_json 1.0.0
  run_cli release start <<< "y"
  [ "$status" -eq 0 ]
  [ "$(current_branch)" = "release/1.0.1" ]
  git merge-base --is-ancestor develop release/1.0.1
  [ -f develop.txt ]
  ! git merge-base --is-ancestor release/1.0.1 master
}

# --- cancel / abort --------------------------------------------------------

@test "cancel deletes the release branch and returns to develop after a yes" {
  on_develop
  git checkout -q -b release/1.0.0
  run_cli release cancel <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "Deleted release branch release/1.0.0"
  [ "$(current_branch)" = "develop" ]
  ! git show-ref --verify --quiet refs/heads/release/1.0.0
}

@test "cancel keeps the release branch after a no" {
  on_develop
  git checkout -q -b release/1.0.0
  run_cli release cancel <<< "n"
  [ "$status" -eq 0 ]
  refute_output_contains "Deleted release branch"
  [ "$(current_branch)" = "release/1.0.0" ]
}

@test "cancel does nothing when not on a release branch" {
  on_develop
  run_cli release cancel <<< "y"
  [ "$status" -eq 0 ]
  refute_output_contains "Are you sure"
  [ "$(current_branch)" = "develop" ]
}

@test "cancel falls back to master when there is no develop branch" {
  git branch -D develop
  git checkout -q -b release/1.0.0
  run_cli release cancel <<< "y"
  [ "$status" -eq 0 ]
  [ "$(current_branch)" = "master" ]
  ! git show-ref --verify --quiet refs/heads/release/1.0.0
}

@test "abort is an alias for cancel" {
  on_develop
  git checkout -q -b release/1.0.0
  run_cli release abort <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "Deleted release branch release/1.0.0"
  [ "$(current_branch)" = "develop" ]
}

# --- finish ----------------------------------------------------------------

@test "finish refuses when not on a release branch" {
  on_develop
  run_cli release finish
  [ "$status" -eq 1 ]
  assert_output_contains "We are not in a release/* branch"
}

@test "finish refuses outside a git repository" {
  mkdir "$TEST_TMP/plain" && cd "$TEST_TMP/plain"
  run_cli release finish
  [ "$status" -eq 1 ]
  assert_output_contains "You are not in a git repository"
}

@test "finish refuses with uncommitted changes" {
  on_develop
  git checkout -q -b release/1.0.0
  echo dirty > dirty.txt
  run_cli release finish
  [ "$status" -eq 1 ]
  assert_output_contains "You have open files in your working directory"
  [ "$(current_branch)" = "release/1.0.0" ]
}

@test "finish merges into master and develop, tags, pushes and removes the branch" {
  add_bare_remote
  on_develop
  git checkout -q -b release/1.0.0
  commit_file VERSION 1.0.0
  run_cli release finish
  [ "$status" -eq 0 ]
  assert_output_contains "Creating tag 1.0.0"
  # Both branches contain the release commit and the tag points at master.
  [ "$(git rev-parse master)" = "$(git rev-parse develop)" ]
  [ "$(git show master:VERSION)" = "1.0.0" ]
  git show-ref --verify --quiet refs/tags/1.0.0
  [ "$(git rev-parse 1.0.0^{commit})" = "$(git rev-parse master)" ]
  ! git show-ref --verify --quiet refs/heads/release/1.0.0
  [ "$(current_branch)" = "develop" ]
  # Everything landed on the bare remote.
  [ "$(git -C "$BARE" rev-parse master)" = "$(git rev-parse master)" ]
  [ "$(git -C "$BARE" rev-parse develop)" = "$(git rev-parse develop)" ]
  git -C "$BARE" show-ref --verify --quiet refs/tags/1.0.0
}

@test "finish makes a merge commit when master moved on" {
  add_bare_remote
  commit_file hotfix.txt "on master"
  git push -q origin master
  on_develop
  git checkout -q -b release/1.1.0
  commit_file VERSION 1.1.0
  run_cli release finish
  [ "$status" -eq 0 ]
  [ "$(git show master:VERSION)" = "1.1.0" ]
  [ "$(git show master:hotfix.txt)" = "on master" ]
  [ "$(git rev-list --merges --count master)" -eq 1 ]
  git -C "$BARE" show-ref --verify --quiet refs/tags/1.1.0
}

@test "finish --force ignores uncommitted changes" {
  add_bare_remote
  on_develop
  git checkout -q -b release/1.0.0
  echo scratch > untracked.txt
  run_cli release finish --force
  [ "$status" -eq 0 ]
  git show-ref --verify --quiet refs/tags/1.0.0
}

@test "finish without a develop branch only merges into master" {
  add_bare_remote
  git branch -D develop
  git checkout -q -b release/1.0.0
  commit_file VERSION 1.0.0
  run_cli release finish
  [ "$status" -eq 0 ]
  assert_output_contains "No develop branch found, not merging to develop"
  [ "$(current_branch)" = "master" ]
  [ "$(git show master:VERSION)" = "1.0.0" ]
  git -C "$BARE" show-ref --verify --quiet refs/tags/1.0.0
}

@test "finish keeps the release branch and does not tag when the push fails" {
  on_develop
  git checkout -q -b release/1.0.0
  commit_file VERSION 1.0.0
  # No remote at all: the merges succeed locally, the push cannot.
  run_cli release finish
  [ "$status" -eq 1 ]
  assert_output_contains "Failed to push master branch"
  git show-ref --verify --quiet refs/heads/release/1.0.0
  [ "$(git show master:VERSION)" = "1.0.0" ]
}

@test "finish does not create a CHANGELOG" {
  add_bare_remote
  on_develop
  git checkout -q -b release/1.0.0
  commit_file VERSION 1.0.0
  run_cli release finish
  [ "$status" -eq 0 ]
  [ ! -f CHANGELOG.md ]
}

# --- merge-features --------------------------------------------------------

@test "merge-features reports when there are no feature branches" {
  on_develop
  run_cli release merge-features
  [ "$status" -eq 0 ]
  assert_output_contains "There are no feature branches to merge."
}

@test "merge-features merges, pushes and deletes a feature branch after a yes" {
  add_bare_remote
  on_develop
  git checkout -q -b feature/login
  commit_file login.txt "login"
  on_develop
  run_cli release merge-features <<< "y"
  [ "$status" -eq 0 ]
  [ "$(current_branch)" = "develop" ]
  [ -f login.txt ]
  ! git show-ref --verify --quiet refs/heads/feature/login
  [ "$(git -C "$BARE" rev-parse develop)" = "$(git rev-parse develop)" ]
}

@test "merge-features leaves a feature branch alone after a no" {
  on_develop
  git checkout -q -b feature/login
  commit_file login.txt "login"
  on_develop
  run_cli release merge-features <<< "n"
  [ "$status" -eq 0 ]
  git show-ref --verify --quiet refs/heads/feature/login
  [ ! -f login.txt ]
}

@test "merge-features asks per feature branch" {
  add_bare_remote
  on_develop
  git checkout -q -b feature/one
  commit_file one.txt one
  on_develop
  git checkout -q -b feature/two
  commit_file two.txt two
  on_develop
  run_cli release merge-features < <(printf 'ny')
  [ "$status" -eq 0 ]
  git show-ref --verify --quiet refs/heads/feature/one
  ! git show-ref --verify --quiet refs/heads/feature/two
  [ ! -f one.txt ]
  [ -f two.txt ]
}

@test "merge-features offers to switch to develop first" {
  [ "$(current_branch)" = "master" ]
  run_cli release merge-features <<< "y"
  [ "$status" -eq 0 ]
  assert_output_contains "There are no feature branches to merge."
  [ "$(current_branch)" = "develop" ]
}

@test "merge-features exits when switching to develop is declined" {
  run_cli release merge-features <<< "n"
  [ "$status" -eq 1 ]
  assert_output_contains "Exiting."
  [ "$(current_branch)" = "master" ]
}

@test "merge-features refuses with uncommitted changes" {
  on_develop
  echo dirty > dirty.txt
  run_cli release merge-features
  [ "$status" -eq 1 ]
  assert_output_contains "You have open files in your working directory"
}
