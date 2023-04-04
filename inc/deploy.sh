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

    # check if there are any uncommitted changes, if so exit with message
    if [[ $(git status | grep "Changes not staged for commit") ]]; then
      echo "There are uncommitted changes, please commit them and try again"
      exit 1
    fi

    # check if there is a staging branch, if not create it
    if [[ -z $(git branch --list staging) ]]; then
      git checkout -b staging
    else
      git checkout staging
    fi

    # merge current branch into staging
    echo "Merge $current_branch into staging"
    git merge --no-ff --no-edit $current_branch


    # check if we are on the staging branch, if not exit with message
    if [[ $(git branch --list | grep \* | sed 's/\* //g') != "staging" ]]; then
      echo "You are not on the staging branch, please check any errors and try again"
      exit 1
    fi

    # do a pull to make sure we have the latest changes
    git pull origin staging

    # check if the --all-features flag is passed
    if [[ "$1" == "--all-features" ]]; then
      # if so, deploy all feature branches to staging
      echo "Deploying all feature branches to staging"
      # get all feature branches
      local feature_branches=$(git branch --list feature/* | sed 's/feature\///g')
      # loop through all feature branches
      for feature_branch in $feature_branches; do
        # merge the feature branch into staging
        echo "Merge feature/$feature_branch into staging"
        # don't merge the current branch because it is already merged
        if [[ "$feature_branch" != "$current_branch" ]]; then
          git merge --no-ff --no-edit feature/$feature_branch
        fi
      done
    else
      # if not, deploy the current branch to staging
      git merge --no-ff --no-edit
    fi

    # check if we have a merge conflict, if so exit with message
    if [[ $(git status | grep "both modified") ]]; then
      echo "There is a merge conflict, please resolve it and try again"
      exit 1
    fi

    # push the staging branch to the remote
    git push origin staging

    # check if the npm run deploy-staging exists
    npm run deploy-staging

    #switch back to the previous branch
    git checkout -
  }

  main "$@"
)