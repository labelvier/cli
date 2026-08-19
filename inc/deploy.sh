#!/bin/bash

deploy() (

  # Local filename to echo the documentation.
  local filename="deploy.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")
  # The ref holding the shared production deployment records.
  local notes_ref="refs/notes/deploys"

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

  # @function production
  # @description Deploys the current branch to the production environment with the local `npm run deploy` script and keeps track of who deployed what and when. Only allowed from master/main or a release/* branch. Use --force to skip the branch, working directory and remote checks, --yes to skip the confirmation and --skip-deploy-check to skip the npm script check.
  function production() {
    # check if we are in a git repository
    if [ ! -d .git ]; then
      echo "You are not in a git repository, exiting."
      exit 1
    fi

    # check if the npm run deploy script exists. Match on '"deploy":' so deploy-staging does not count as a match.
    if ! _flag_is_present "skip-deploy-check" "$@" && ! npm pkg get scripts | grep -q '"deploy":'; then
      echo "npm script 'deploy' not found, aborting deploy"
      echo "override by using the --skip-deploy-check flag"
      exit 1
    fi

    # check if there are any uncommitted changes (staged or unstaged), if so exit with message
    if ! _flag_is_present "force" "$@" && [ -n "$(git status --porcelain)" ]; then
      echo "There are uncommitted changes, please commit or stash them. Or use --force to ignore this."
      exit 1
    fi

    # deploying to production is only allowed from master/main or a release branch, release.sh handles the merging
    local branch=$(git rev-parse --abbrev-ref HEAD)
    if ! _flag_is_present "force" "$@" \
      && [ "$branch" != "master" ] && [ "$branch" != "main" ] \
      && [[ ! $branch =~ ^.*release\/.*$ ]]; then
      echo "You are on $branch. Only deploy production from master/main or a release/* branch, or use --force."
      exit 1
    fi

    # fetch latest remote info; abort on failure
    git fetch || { echo "git fetch failed, aborting deploy"; exit 1; }

    # compare with the upstream branch when there is one. Release branches are often local only, so only warn there.
    if git rev-parse --abbrev-ref '@{u}' > /dev/null 2>&1; then
      if [ "$(git rev-parse HEAD)" != "$(git rev-parse '@{u}')" ] && ! _flag_is_present "force" "$@"; then
        echo "$branch differs from its remote, please push or pull first. Or use --force to ignore this."
        exit 1
      fi
    else
      echo -e "${__red}Warning: $branch has no upstream, deploying unpushed local commits.${__reset}"
    fi

    # collect the information we want to keep track of
    local version
    if [[ $branch =~ ^.*release\/.*$ ]]; then
      # the release tag is only created by 'release finish', so take the version from the branch name
      version="${branch##*/}"
    else
      version=$(git describe --tags --abbrev=0 2>/dev/null || echo "unknown")
    fi
    local commit=$(git rev-parse --short HEAD)
    local deployer="$(git config user.name) <$(git config user.email)>"
    local project=$(basename "$(pwd)")

    # confirm the deployment because this goes straight to production
    echo -e "${__bold}Deploying to the production environment:${__reset}"
    echo -e "  Project: $project"
    echo -e "  Version: $version"
    echo -e "  Branch:  $branch ($commit)"
    echo -e "  By:      $deployer"
    if ! _flag_is_present "yes" "$@"; then
      read -p "Deploy this to the LIVE environment? [y/N] " -n 1 -r
      echo ""
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting deploy."
        exit 1
      fi
    fi

    # deploy to production, but keep the exit code so a failed deployment gets logged as well
    npm run deploy
    local deploy_status=$?

    # log the deployment. A logging problem may never change the outcome of the deployment itself.
    if [ "$deploy_status" -eq 0 ]; then
      _log_deploy "success" "$version" "$commit" "$branch" "$deployer"
      echo -e "${__green}Deployed $project $version to the production environment.${__reset}"
    else
      _log_deploy "failed" "$version" "$commit" "$branch" "$deployer"
      echo -e "${__red}npm run deploy failed with exit code $deploy_status.${__reset}"
    fi

    exit $deploy_status
  }

  # @function log <optional-amount>
  # @description Shows the production deployments of this project, latest first. The default amount is 20.
  function log() {
    local amount="${1:-20}"

    # check if we are in a git repository
    if [ ! -d .git ]; then
      echo "You are not in a git repository, exiting."
      exit 1
    fi

    # notes are not fetched by default, so ask for the ref explicitly
    _fetch_deploy_notes

    # check if there is anything logged at all
    if [ -z "$(git notes --ref=deploys list 2>/dev/null)" ]; then
      echo "No production deployments logged for this project yet."
      exit 0
    fi

    # every record starts with an ISO timestamp, so a reverse sort gives us the latest deployments first
    echo -e "${__bold}Production deployments of $(basename "$(pwd)"):${__reset}"
    git notes --ref=deploys list | awk '{print $2}' | while read -r noted_commit; do
      git notes --ref=deploys show "$noted_commit"
    done | sort -r | head -n "$amount"
  }

  # Fetch the notes ref, forced so a record from a parallel deploy can never be overwritten by ours.
  function _fetch_deploy_notes() {
    git fetch -q origin "+$notes_ref:$notes_ref" 2> /dev/null
  }

  # Append a deployment record to the shared notes ref and push it to origin.
  function _log_deploy() {
    local status="$1"
    local record="$(date -u +%Y-%m-%dT%H:%M:%SZ) | production | $2 | $3 | $4 | $5 | $status"

    # retry once, a deployment from a colleague can win the race for the notes ref
    if _write_deploy_note "$record" || _write_deploy_note "$record"; then
      return 0
    fi

    # never fail the deployment over a logging problem, hand the record to the user instead
    echo -e "${__red}Could not store the deployment record, please pass it on manually:${__reset}"
    echo "$record"
  }

  # Write a single record to the notes ref and publish it.
  function _write_deploy_note() {
    local record="$1"

    _fetch_deploy_notes
    # only append when the record is not already there, so a retry after a failed push cannot duplicate it
    if ! git notes --ref=deploys show HEAD 2> /dev/null | grep -qF "$record"; then
      git notes --ref=deploys append -m "$record" || return 1
    fi
    git push -q origin "$notes_ref" 2> /dev/null || return 1
  }

  main "$@"
)
