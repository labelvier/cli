#!/bin/bash
# shellcheck disable=SC2317

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

  # @function start <optional-version>
  # @description Creates a new release branch, tries to check if there is any package.json file and updates the version. Possible flags are --minor and --major. Standard version is patch. If no version is given, we'll check if there is a WordPress theme in the .env file and try to get the version from the style.scss file. If that fails, we'll check if there is a package.json file and try to get the version from there. If that fails, we'll exit.
  function start() {

    # check if we are in a git repository
    if [ ! -d .git ]; then
        echo "You are not in a git repository, exiting."
        exit 1
    fi

    # check if we are on the develop branch and --force is not set
    local branch=$(git rev-parse --abbrev-ref HEAD)

    if ! _flag_is_present "force" "$@" && [ "$branch" != "develop" ]; then
        echo "You are not on the develop branch, use --force to start a release branch from $branch."
        exit 1
    fi


    local version=0
    # print all arguments
    # check if we have $1 and if it not a --variable
    if [ -n "$1" ] && [[ ! $1 =~ ^--.*$ ]]; then
        echo "Custom version given: $1"
        version=$1
        # checkout new feature branch
        git checkout -b "release/$version"
    else
      echo "No version given, trying to find one."
      version="0"
      path="0"
      # check if we have an .env file
      if [ -f .env ]; then
        # get the lines starting with DEV_THEME_PATH from the .env file
        local dev_theme_path=$(grep "^DEV_THEME_PATH" .env | cut -d "=" -f2)
        # check if we have a dev_theme_path
        if [ -n "$dev_theme_path" ]; then
          dev_theme_path="$(pwd)$dev_theme_path"
          # check if we have a src/scss/style.scss file in the dev_theme_path
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
              path="$dev_theme_path/src/scss/style.scss"
            else
              echo "No version found in $dev_theme_path/src/scss/style.scss"
            fi
          # check for style.css in $dev_theme_path
          elif [ -f "$dev_theme_path/style.css" ]; then
            # get the version from the style.css file, format is 'Version: 1.0.0'
            version=$(grep 'Version:' "$dev_theme_path/style.css")
            # remove the 'Version: ' part with sed
            version=$(echo $version | sed 's/Version: //')
            # remove any whitespaces
            version=$(echo $version | xargs)
            # check if version is not empty
            if [ "$version" ]; then
              echo "Found version $version in $dev_theme_path/style.css"
              path="$dev_theme_path/style.css"
            else
              echo "No version found in $dev_theme_path/style.css"
            fi
          else
            echo "No src/scss/style.scss or style.css file found in $dev_theme_path."
          fi
        else
          echo "No DEV_THEME_PATH found in .env file."
        fi
      else
        echo "No .env file found. Checking for package.json file."
        # check if we have a package.json file
        if [ -f package.json ]; then
          # get the version from the package.json file
          version=$(grep version package.json)
          # remove the 'version: ' part with sed
          version=$(echo $version | sed 's/"version": "//')
          # remove the last " with sed
          version=$(echo $version | sed 's/",//')
          # remove any whitespaces
          version=$(echo $version | xargs)
          # check if version is not empty
          if [ "$version" ]; then
            echo "Found version $version in package.json"
            using_package_json=1
          else
            echo "No version found in package.json"
          fi
        else
          echo "No package.json file found."
        fi
      fi

      # check if version is semantic
      if ! _is_semantic_version "$version"; then
        echo "Version $version is not semantic, exiting."
        exit 1
      fi

      oldversion=$version
      # check if --minor or --major is set
      if _flag_is_present "minor" "$@"; then
        # get the major version
        local major=$(echo $version | cut -d '.' -f1)
        # get the minor version
        local minor=$(echo $version | cut -d '.' -f2)
        # increase the minor version
        minor=$((minor+1))
        # set the version to the new version
        version="$major.$minor.0"
      elif _flag_is_present "major" "$@"; then
        # get the major version
        local major=$(echo $version | cut -d '.' -f1)
        # increase the major version
        major=$((major+1))
        # set the version to the new version
        version="$major.0.0"
      else
        # get the major version
        local major=$(echo $version | cut -d '.' -f1)
        # get the minor version
        local minor=$(echo $version | cut -d '.' -f2)
        # get the patch version from the last dot untill a space or dash
        local patch=$(echo $version | cut -d '.' -f3 | cut -d ' ' -f1 | cut -d '-' -f1)
        # check if there is a space or dash in the version
        if [[ $version =~ .*[[:space:]].* ]] || [[ $version =~ .*-.* ]]; then
          # get the first part untill a space and save the remainder of the string (if there is a space or dash)
          local remainder=$(echo $version | cut -d '.' -f3 | cut -d ' ' -f2 | cut -d '-' -f2)
          # check if the seperator is a dash or space
          if [[ $version =~ .*-.* ]]; then
            # set the seperator to a dash
            local seperator="-"
          else
            # set the seperator to a space
            local seperator=" "
          fi
          # increase the patch version
          patch=$((patch+1))
          # set the version to the new version
          version="$major.$minor.$patch$seperator$remainder"
        else
          # increase the patch version
          patch=$((patch+1))
          # set the version to the new version
          version="$major.$minor.$patch"
        fi
      fi

      echo "New version: $version"
      message=""
      # update the version in the style.scss file
      if [ -f "$path" ]; then
        # make $path relative to the current directory
        root_path=$(pwd);
        path="${path#$root_path/}"
        # replace the version in the style.scss file
        sed -i '' "s/Version: $oldversion/Version: $version/g" "$path"
        message="Updated version in $path to $version"
        # commit the changed file
        git add "$path"
      fi

      if [ "$using_package_json" = "1" ]; then
        # update the version in the package.json file
        sed -i '' "s/\"version\": \"$oldversion\"/\"version\": \"$version\"/g" package.json
        message="chore(package.json): updated version to $version"
        # commit the changed file
        git add package.json
      fi

      # checkout a new branch, replace spaces with minus
      git checkout -b "release/${version// /-}"
      # commit the changed file if messages is not empty
      if [ "$message" ]; then
        git commit -m "$message"
        echo "$message"
      fi
    fi
  }

  # @function cancel
  # @description Cancels the release.
  function cancel() {
    #check if we are in a release branch, if so delete it
    local branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ $branch =~ ^.*release\/.*$ ]]; then
      # ask if we want to delete the branch
      read -p "Are you sure you want to delete the release branch $branch? [y/N] " -n 1 -r
      # delete the branch if the answer is y
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        git checkout develop
        git branch -D $branch
        echo "Deleted release branch $branch"
      fi
    fi
  }

  # @function finish
  # @description Merges the release branch into master and develop, and tags the release.
  function finish() {
    # check if we are in a git repository
    if [ ! -d .git ]; then
        echo "You are not in a git repository, exiting."
        exit 1
    fi

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
        exit 1
    fi

    # Check if we have any open files in the working directory and --force is not set
    if ! _flag_is_present "force" "$@" && [ -n "$(git status --porcelain)" ]; then
        echo "You have open files in your working directory, please commit or stash them. Or use --force to ignore this."
        exit 1
    fi

    # check if we there is a master branch
    local master_branch=$(git branch | grep master)
    if [ -z "$master_branch" ]; then
        echo "No master branch found, trying main."
        # check if we there is a main branch
        local master_branch=$(git branch | grep main)
        if [ -z "$master_branch" ]; then
            echo "No master or main branch found, exiting."
            exit 1
        fi
    fi
    #remove whitespace from $master_branch
    local master_branch="${master_branch// /}"
    # checkout the master branch
    git checkout "$master_branch"
    git merge $branch
    git tag -a "$version" -m ""
    git push
    git push --tags

    # check if we there is a develop branch
    local develop_branch=$(git branch | grep develop)
    if [ -z "$develop_branch" ]; then
        echo "No develop branch found, not merging to develop."
    else
      git checkout develop
      git merge $branch
      git push
    fi
    # delete the release branch
    git branch -d $branch
  }

  # @function merge-features
  # @description Checks if there are open feature branches and asks to merge them to develop.
  function merge-features() {
    # check if we are in a git repository
    if [ ! -d .git ]; then
        echo "You are not in a git repository, exiting."
        exit 1
    fi

    # check if we are on the develop branch
    local branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$branch" != "develop" ]; then
        read -p "You are not on the develop branch, do you want to switch to the develop branch? [y/N] " -n 1 -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git checkout develop
        else
            echo "Exiting."
          exit 1
        fi
    fi

    # check if we have any open files in the working directory and --force is not set
    if ! _flag_is_present "force" "$@" && [ -n "$(git status --porcelain)" ]; then
        echo "You have open files in your working directory, please commit or stash them. Or use --force to ignore this."
        exit 1
    fi

    # get all the feature branches
    local feature_branches=$(git branch | grep feature | sed 's/ //g')
    # check if there are any feature branches
    if [ "$feature_branches" ]; then
        # loop through the feature branches
        for feature_branch in $feature_branches; do
            # ask if we want to merge the feature branch
            read -p "Do you want to merge $feature_branch to develop (and delete the feature branch)? [y/N] " -n 1 -r
            # line break
            echo ""
            # merge the feature branch if the answer is y
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                git checkout develop
                git merge $feature_branch
                git push
                git branch -d $feature_branch
            fi
        done
    else
        echo "There are no feature branches to merge."
    fi
  }

  main "$@"
)
