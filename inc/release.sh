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

  # @function start
  # @description Creates a new release branch, tries to check if there is any package.json file and updates the version. Possible flags are --minor and --major. Standard version is patch.
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
    # check if we have $3 and if it not a --variable
    if [ -n "$3" ] && [[ ! $3 =~ ^--.*$ ]]; then
        version=$3
    else
      echo "No version given, trying to find one."
      version="0"
      # check if we have an .env file
      if [ -f .env ]; then
        # get the DEV_THEME_PATH from the .env file
        local dev_theme_path=$(grep DEV_THEME_PATH .env | cut -d '=' -f2)
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

      # check if $version is not ""
      if [ "$version" = "0" ]; then
        echo "No version found, exiting."
        exit 1
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

      # update the version in the style.scss file
      if [ -f "$dev_theme_path/src/scss/style.scss" ]; then
        # replace the version in the style.scss file
        sed -i '' "s/Version: $oldversion/Version: $version/g" "$dev_theme_path/src/scss/style.scss"
        message="Updated version in $dev_theme_path/src/scss/style.scss to $version"
        # commit the changed file
        git add "$dev_theme_path/src/scss/style.scss"
        git commit -m "$message"
        echo "$message"
      fi

      if [ "$using_package_json" = "1" ]; then
        # update the version in the package.json file
        sed -i '' "s/\"version\": \"$oldversion\"/\"version\": \"$version\"/g" package.json
        message="Updated version in package.json to $version"
        # commit the changed file
        git add package.json
        git commit -m "$message"
        echo "$message"
      fi

      # checkout a new branch, replace spaces with minus
      git checkout -b "release/${version// /-}"
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

  main "$@"
)
