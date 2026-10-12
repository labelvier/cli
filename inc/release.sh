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
    _dispatch "$filename" "$@"
  }

  # @function start <optional-version>
  # @description Creates a new release branch, tries to check if there is any package.json file and updates the version. Possible flags are --minor and --major. Standard version is patch. If no version is given, we'll check if there is a WordPress theme in the .env file and try to get the version from the style.scss file. If that fails, we'll check if there is a package.json file in the root, get the version from there and ask before bumping it. If that fails, we'll do the same with a VERSION file in the root. If that fails, give the version yourself and we'll offer to create a VERSION file.
  function start() {
    # Create the release branch and stop immediately when it cannot be created.
    function _create_release_branch() {
      local release_branch="$1"

      if git show-ref --verify --quiet "refs/heads/$release_branch"; then
        echo "Release branch $release_branch already exists, exiting."
        exit 1
      fi

      if ! git checkout -b "$release_branch"; then
        echo "Error: Failed to create release branch $release_branch."
        exit 1
      fi
    }

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
    local oldversion=0
    local path="0"
    local message=""
    local custom_version=""
    local using_package_json=0
    local using_version_file=0
    local create_version_file=0
    local no_version_source=0

    # Capture an explicitly requested release version when it was provided.
    if [ -n "$1" ] && [[ ! $1 =~ ^--.*$ ]]; then
      custom_version="$1"
      echo "Custom version given: $custom_version"
    else
      echo "No version given, trying to find one."
    fi

    # Detect the current release version from the configured theme or package file.
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
    fi

    if [ "$path" = "0" ] && [ -f package.json ]; then
      # Fallback to package.json when no theme version file was detected.
      # take the value of the first "version" key, with or without a trailing comma
      version=$(grep -m1 '"version"' package.json | sed -E 's/.*"version"[^"]*"([^"]*)".*/\1/')
      # check if version is not empty
      if [ "$version" ]; then
        echo "Found version $version in package.json"
        using_package_json=1
      else
        echo "No version found in package.json"
      fi
    elif [ "$path" = "0" ]; then
      echo "No package.json file found."
    fi

    # Fallback to a VERSION file in the root when neither a theme file nor package.json gave a version.
    if [ "$path" = "0" ] && [ "$using_package_json" = "0" ]; then
      if [ -f VERSION ]; then
        version=$(head -n 1 VERSION | tr -d '[:space:]')
        if [ "$version" ]; then
          echo "Found version $version in VERSION"
          using_version_file=1
        else
          echo "No version found in VERSION"
        fi
      else
        echo "No VERSION file found."
      fi
    fi

    if [ "$path" = "0" ] && [ "$using_package_json" = "0" ] && [ "$using_version_file" = "0" ]; then
      no_version_source=1
    fi

    # Without any version source the new version cannot be calculated, so it has to be given.
    if [ -z "$custom_version" ] && [ "$no_version_source" = "1" ]; then
      echo "No version file found, give the new version: labelvier release start <version>"
      echo "Tip: add a VERSION file with the current version (echo 1.0.0 > VERSION), so the next release can bump it."
      exit 1
    fi

    # Validate the detected current version before calculating the release version.
    # Skip when a custom version was given — the current version is only needed to bump from.
    if [ -z "$custom_version" ] && ! _is_semantic_version "$version"; then
      echo "Version $version is not semantic, exiting."
      exit 1
    fi

    oldversion=$version
    # Calculate the next release version unless a custom target version was supplied.
    if [ -n "$custom_version" ]; then
      version="$custom_version"
    elif _flag_is_present "minor" "$@"; then
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

    # Validate the target release version before creating the release branch.
    if ! _is_semantic_version "$version"; then
      echo "Target version $version is not semantic, exiting."
      exit 1
    fi

    echo "New version: $version"

    # package.json in the root is only a backup source, so ask before bumping it.
    if [ "$using_package_json" = "1" ]; then
      read -p "No theme version file found. Bump package.json from $oldversion to $version? [Y/n] " -n 1 -r
      echo ""
      if [[ $REPLY =~ ^[Nn]$ ]]; then
        using_package_json=0
        echo "Leaving package.json at $oldversion."
      fi
    fi

    # The VERSION file is the last backup source, so ask before bumping it too.
    if [ "$using_version_file" = "1" ]; then
      read -p "No theme version file or package.json found. Bump VERSION from $oldversion to $version? [Y/n] " -n 1 -r
      echo ""
      if [[ $REPLY =~ ^[Nn]$ ]]; then
        using_version_file=0
        echo "Leaving VERSION at $oldversion."
      fi
    fi

    # Without any version source, suggest a VERSION file so the next release can find its version.
    if [ "$no_version_source" = "1" ]; then
      read -p "No version file found. Create a VERSION file with $version, so the next release can bump it? [Y/n] " -n 1 -r
      echo ""
      if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        create_version_file=1
      fi
    fi

    # Create the release branch before applying the version bump.
    _create_release_branch "release/${version// /-}"
    # Update and stage the theme version file when one was detected.
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
      # Update and stage package.json when it is the active version source.
      sed -i '' "s/\"version\": \"$oldversion\"/\"version\": \"$version\"/g" package.json
      message="chore(package.json): updated version to $version"
      # commit the changed file
      git add package.json
    fi

    if [ "$using_version_file" = "1" ] || [ "$create_version_file" = "1" ]; then
      # Write the new version to the VERSION file, or create it when there was no version source.
      echo "$version" > VERSION
      if [ "$create_version_file" = "1" ]; then
        message="chore(VERSION): add VERSION file with $version"
      else
        message="chore(VERSION): updated version to $version"
      fi
      git add VERSION
    fi
    # commit the changed file if messages is not empty
    if [ "$message" ]; then
      git commit -m "$message"
      echo "$message"
    fi
  }

  # @function cancel
  # @description Cancels the release.
  function cancel() {
    # Determine whether the current branch is a release branch that can be cancelled.
    local branch=$(git rev-parse --abbrev-ref HEAD)
    local fallback_branch=""

    if [[ $branch =~ ^.*release\/.*$ ]]; then
      # Choose a safe branch to return to before deleting the release branch.
      if git show-ref --verify --quiet refs/heads/develop; then
        fallback_branch="develop"
      elif git show-ref --verify --quiet refs/heads/master; then
        fallback_branch="master"
      elif git show-ref --verify --quiet refs/heads/main; then
        fallback_branch="main"
      else
        echo "No develop, master, or main branch found to switch back to, exiting."
        exit 1
      fi

      # Confirm the release cancellation before deleting the branch.
      read -p "Are you sure you want to delete the release branch $branch? [y/N] " -n 1 -r
      echo ""

      # delete the branch if the answer is y
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Switch away from the release branch before deleting it.
        if ! git checkout "$fallback_branch"; then
          echo "Error: Failed to checkout $fallback_branch."
          exit 1
        fi

        if ! git branch -D "$branch"; then
          echo "Error: Failed to delete release branch $branch."
          exit 1
        fi

        echo "Deleted release branch $branch"
      fi
    fi
  }

  # @function abort
  # @description Alias for cancel, matching the common git merge --abort habit.
  function abort() {
    # Delegate to the release cancellation flow so both commands behave identically.
    cancel "$@"
  }

  # @function finish
  # @description Merges the release branch into master (or main) and develop, and tags the release.
  function finish() {
    # Track which local merge steps have completed successfully.
    local master_merged=0
    local develop_merged=0
    local has_develop_branch=0

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

    # check if we there is a master branch (exact match)
    local master_branch=""
    if git show-ref --verify --quiet refs/heads/master; then
        master_branch="master"
    elif git show-ref --verify --quiet refs/heads/main; then
        master_branch="main"
    else
        echo "No master or main branch found, exiting."
        exit 1
    fi

    # checkout the master branch
    echo "Checking out $master_branch branch..."
    if ! git checkout "$master_branch"; then
        echo "Error: Failed to checkout $master_branch branch."
        exit 1
    fi

    # merge the release branch into master/main
    echo "Merging $branch into $master_branch..."
    if ! git merge "$branch"; then
        echo "Error: Failed to merge $branch into $master_branch. Please resolve conflicts manually."
        exit 1
    fi

    master_merged=1

    # Merge the release branch into develop before publishing any release refs.
    if git show-ref --verify --quiet refs/heads/develop; then
        has_develop_branch=1
        echo "Merging into develop branch..."
        if ! git checkout develop; then
            echo "Error: Failed to checkout develop branch."
            exit 1
        fi
        if ! git merge "$branch"; then
            echo "Error: Failed to merge $branch into develop. Please resolve conflicts manually."
            exit 1
        fi
        develop_merged=1
    else
        echo "No develop branch found, not merging to develop."
    fi

    # Create and publish the release only after all local merges have succeeded.
    if [ "$master_merged" -eq 1 ] && { [ "$has_develop_branch" -eq 0 ] || [ "$develop_merged" -eq 1 ]; }; then
        if ! git checkout "$master_branch"; then
            echo "Error: Failed to checkout $master_branch branch before tagging."
            exit 1
        fi

        echo "Creating tag $version..."
        if ! git tag -a "$version" -m ""; then
            echo "Error: Failed to create tag $version."
            exit 1
        fi

        echo "Pushing $master_branch..."
        if ! git push; then
            echo "Error: Failed to push $master_branch branch."
            exit 1
        fi

        if [ "$has_develop_branch" -eq 1 ]; then
            if ! git checkout develop; then
                echo "Error: Failed to checkout develop branch before pushing."
                exit 1
            fi

            echo "Pushing develop..."
            if ! git push; then
                echo "Error: Failed to push develop branch."
                exit 1
            fi
        fi

        echo "Pushing tags..."
        if ! git push --tags; then
            echo "Error: Failed to push tags."
            exit 1
        fi

        git branch -d "$branch"
    else
        echo "Release branch $branch is kept because not all local merge steps completed successfully."
        exit 1
    fi
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
