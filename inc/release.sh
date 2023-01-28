#!/bin/bash

release() (

  # Local filename to echo the documentation.
  local filename="release.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")
  # force flag
  local force=0

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

  # @function start
  # @description Creates a new release branch, tries to check if there is any package.json file and updates the version.
  function start() {
    _check_force_flag "$@"
    # check if we are on the develop branch and --force is not set
    local branch=$(git rev-parse --abbrev-ref HEAD)
    if [ $force -eq 0 ] && [ "$branch" != "develop" ]; then
        echo "You are not on the develop branch, use --force to start a release branch from $branch."
        return 1
    fi
  }

  # @function finish
  # @description Merges the release branch into master and develop, and tags the release.
  function finish() {
    # Check if the force flag is set
    echo "$@"
    # echo all arguments
    for word in "$@"; do echo $word; done
    _check_force_flag "$@"


    # check if we have a version which is not --force or empty
    if [ -z "$1" ] || [ "$1" = "--force" ]; then
        # If not check if we have a git branch with a version
        local branch=$(git rev-parse --abbrev-ref HEAD)
        echo "branch: $branch"
        # Check if we are in a release/* branch
        if [[ $branch =~ ^.*release\/.*$ ]]; then
            # Extract the version from the branch name, last part after the last /
            local version=${branch##*/}
            echo "version: $version"
        else
            echo "We are not in a release/* branch, exiting."
            return 1
        fi
    else
        local version=$1
    fi

    # Check if we have any open files in the working directory and --force is not set
    if [ $force -eq 0 ] && [ -n "$(git status --porcelain)" ]; then
        echo "You have open files in your working directory, please commit or stash them. Or use --force to ignore this."
        return 1
    fi

    git checkout master
    git merge $branch
    git tag -a "$version" -m ""
    git push
    git push --tags

    git checkout develop
    git merge $branch
    git push

    git branch -d $branch
  }

  _check_force_flag() {
    # Check if the force flag is set
    force=0
    # loop to all arguments and check if --force is present
    for i in "$@"
    do
        if [ "$i" = "--force" ]; then
            force=1
        fi
    done

    local version=0
    # check if we have $3 and if it not a --variable
    if [ -n "$3" ] && [[ ! $3 =~ ^--.*$ ]]; then
        version=$3
    else
      echo "No version given, trying to find one."
      version=""
      # check if we have an .env file
      if [ -f .env ]; then
        # get the DEV_THEME_PATH from the .env file
        local dev_theme_path=$(grep DEV_THEME_PATH .env | cut -d '=' -f2)
        # check if we have a dev_theme_path
        if [ -n "$dev_theme_path" ]; then
          dev_theme_path="$(pwd)$dev_theme_path"
          # check if we have a src/scss/style.scss file in the dev_theme_path
          echo "Checking for $dev_theme_path/src/scss/style.scss"
          if [ -f "$dev_theme_path/src/scss/style.scss" ]; then
            # get the version from the style.scss file, format is 'Version: 1.0.0'
            version=$(grep 'Version:' "$dev_theme_path/src/scss/style.scss")
            # remove the 'Version: ' part with sed
            version=$(echo $version | sed 's/Version: //')
            # remove any whitespaces
            version=$(echo $version | xargs)
            # check if version is not empty
            if [ "$version" ]; then
              echo "Found version $version in $dev_theme_path/src/scss/style.scss"
            else
              echo "No version found in $dev_theme_path/src/scss/style.scss"
            fi
          else
            echo "No src/scss/style.scss file found in $dev_theme_path."
          fi
        else
          echo "No DEV_THEME_PATH found in .env file."
        fi
      else
        echo "No .env file found."
      fi

      # check if $version is not ""
      if [ "$version" = "" ]; then
        echo "No version found, exiting."
        return 1
      fi
    fi

  }

  main "$@"
)
