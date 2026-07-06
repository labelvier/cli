#!/bin/bash

deploy() (

  # Local filename to echo the documentation.
  local filename="deploy.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")

  # Runs the command.
  function main() {
    # try to run the subcommand passed as the second argument and that function exists
    if [[ -n "$1" ]] && type -t "$1" | grep -q 'function'; then
      # attach any remaining arguments to the function
      "$1" "${@:2}"
    else
      # if no subcommand is passed, run the documentation function
      _echo_documentation "$filename"
    fi
  }

  # @function staging
  # @description merges the current branch to staging branch and deploys the staging branch  to the staging environment. Use --all-features to deploy all feature/ branches to staging.
  function staging() {
    # get current branch
    local current_branch=$(git branch --list | grep \* | sed 's/\* //g')

    # on exit: stay on staging if there's a merge conflict so the user can resolve it,
    # otherwise always switch back to the original branch
    trap 'if git status | grep -q "both modified\|Unmerged paths"; then
      echo -e "${__red}Merge conflict on staging — resolve manually, then push staging before switching back: git push && git checkout $current_branch${__reset}"
    else
      git checkout "$current_branch" 2>/dev/null
    fi' EXIT

    # check if npm run deploy-staging script exists before doing anything, if --skip-deploy-staging-check is present, anywhere in the arguments, skip this check
    # if ! npm pkg get scripts | grep -q "deploy-staging"; and [[ ! " $* " == *" --skip-deploy-staging-check "* ]]; then
    if [[ ! " $* " == *" --skip-deploy-staging-check "* ]] && ! npm pkg get scripts | grep -q "deploy-staging"; then
      echo "npm script 'deploy-staging' not found, aborting deploy"
      echo "override by using --skip-deploy-staging-check the flag"
      exit 1
    fi

    # check if there are any uncommitted changes (staged or unstaged), if so exit with message
    if [[ -n $(git status --porcelain) ]]; then
      echo "There are uncommitted changes, please commit or stash them and try again"
      exit 1
    fi

    # fetch latest remote info; abort on failure
    git fetch || { echo "git fetch failed, aborting deploy"; exit 1; }
    # always delete local staging so it can never be leading
    if git branch --list staging | grep -q staging; then
      git branch -D staging
    fi

    # (re)create local staging branch
    if git branch -r --list origin/staging | grep -q "origin/staging"; then
      # upstream staging exists: create local branch tracking it, then merge current branch in
      git checkout -b staging origin/staging || { echo "git checkout staging failed, aborting deploy"; exit 1; }
      echo "Merge $current_branch into staging"
      git merge --no-ff --no-edit "$current_branch" || { echo "git merge failed, aborting deploy"; exit 1; }
    else
      # no upstream staging: base local staging on current branch
      git checkout -b staging || { echo "git checkout -b staging failed, aborting deploy"; exit 1; }
    fi

    # check if we are on the staging branch, if not exit with message
    if [[ $(git branch --list | grep \* | sed 's/\* //g') != "staging" ]]; then
      echo "You are not on the staging branch, please check any errors and try again"
      exit 1
    fi

    # check if the --all-features flag is passed
    if [[ "$1" == "--all-features" ]]; then
      # if so, deploy all feature branches to staging
      echo "Deploying all feature branches to staging"
      # get all feature branches
      local feature_branches=$(git branch --list "feature/*" | sed 's/.*feature\///g')
      # loop through all feature branches
      for feature_branch in $feature_branches; do
        # merge the feature branch into staging; skip current branch (already merged above)
        if [[ "feature/$feature_branch" != "$current_branch" ]]; then
          echo "Merge feature/$feature_branch into staging"
          git merge --no-ff --no-edit "feature/$feature_branch" || { echo "git merge feature/$feature_branch failed, aborting deploy"; exit 1; }
        fi
      done
    fi

    # check if we have a merge conflict, if so exit with message
    if [[ $(git status | grep "both modified") ]]; then
      echo "There is a merge conflict, please resolve it and try again"
      exit 1
    fi

    # force-with-lease: safe force push since we always rebuild staging from origin
    git push --force-with-lease origin staging || { echo "git push failed, aborting deploy"; exit 1; }

    # deploy to staging
    npm run deploy-staging || { echo "npm run deploy-staging failed, aborting deploy"; exit 1; }

    # return to original branch
    git checkout "$current_branch" || { echo "git checkout $current_branch failed, please check the state of your repository and try again"; exit 1; }
  }

  main "$@"
)
