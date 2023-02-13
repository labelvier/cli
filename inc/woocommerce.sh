#!/bin/bash

# Enable woocommerce scss compilation.
woocommerce() (

  # Local filename to echo the documentation.
  local filename="woocommerce.sh"

  # Runs the command.
  function main() {
    # try to run the subcommand passed as the second argument and that function exists
    if [[ -n "$1" ]] && type -t "$1" | grep -q 'function'; then
      "$1"
    else
      # if no subcommand is passed, run the documentation function
      _echo_documentation "$filename"
    fi
  }

  # @function add
  # @description Enable woocommerce scss compilation. Adds a submodule from the woocommerce repository.
  function add() {
    _needs_active_wptakeoff_project

    # check if we have an .env file
    if [ -f .env ]; then
      # get the DEV_THEME_PATH from the .env file
        local theme_folder_name=$(grep THEME_FOLDER_NAME .env | cut -d '=' -f2)
        # exit if the DEV_THEME_PATH is not set
        if [ -z "$theme_folder_name" ]; then
          echo "THEME_FOLDER_NAME is not set in the .env file"
          exit 1
        fi
    fi

    echo "Adding woocommerce styling"
    # Remove optionally orphan folder
    git submodule deinit -f ./wp-content/themes/$theme_folder_name/src/scss/g-plugins/woocommerce/upstream &>/dev/null || true
    git rm -f ./wp-content/themes/$theme_folder_name/src/scss/g-plugins/woocommerce/upstream &>/dev/null || true
    rm -rf .git/modules/wp-content/themes/$theme_folder_name/src/scss/g-plugins/woocommerce/upstream &>/dev/null || true

    # Add a git submodule for the woocommerce scss files from https://github.com/woocommerce/woocommerce.git to the theme folder
    # Checkout the to-be submodule
    # I did not find a way to add submodule in 1 step without checking out
    git clone --depth=1 --no-checkout https://github.com/woocommerce/woocommerce.git ./wp-content/themes/$theme_folder_name/src/scss/g-plugins/woocommerce/upstream

    # Add as a submodule
    git submodule add https://github.com/woocommerce/woocommerce.git ./wp-content/themes/$theme_folder_name/src/scss/g-plugins/woocommerce/upstream

    # Move the .git dir from path/some-repo/.git into parent repo's .git
    git submodule absorbgitdirs

    # Note there is no "submodule.sub.sparsecheckout" key
    git -C ./wp-content/themes/$theme_folder_name/src/scss/g-plugins/woocommerce/upstream config core.sparseCheckout true

    # This pattern determines which files within some-repo.git get checked out.
    # Note quoted wildcards to avoid their expansion by shell
    echo 'plugins/woocommerce/client/legacy/css/*' >>.git/modules/wp-content/themes/$theme_folder_name/src/scss/g-plugins/woocommerce/upstream/info/sparse-checkout

    # Actually do the checkout
    git submodule update --force --checkout

    # Get the contents from the package.json file and echo only one key
    DEV_SCRIPT=$(node -p -e "require('./package.json').scripts.dev")
    # If the dev script doesn't contain 'git submodule update --remote' prepend it
    if [[ ! $DEV_SCRIPT == *"git submodule update --remote"* ]]; then
      echo "Adding git submodule update --remote to dev script"
      # Prepend the git submodule update --remote to the dev script
      npm pkg set scripts.dev="git submodule update --remote && $DEV_SCRIPT"
    fi

    echo "Done"
  }

  # @function remove
  # @description Disable woocommerce scss compilation. Removes the submodule from the woocommerce repository.
  function remove() {
    # check if we have an .env file
    if [ -f .env ]; then
      # get the THEME_FOLDER_NAME from the .env file
        local theme_folder_name=$(grep THEME_FOLDER_NAME .env | cut -d '=' -f2)
        # exit if the THEME_FOLDER_NAME is not set
        if [ -z "$theme_folder_name" ]; then
          echo "THEME_FOLDER_NAME is not set in the .env file"
          exit 1
        fi
    fi

    _needs_active_wptakeoff_project
    echo "Removing woocommerce styling"
    # Remove woocommerce styling from the scss file
    # Remove the submodule
    git submodule deinit -f ./wp-content/themes/$theme_folder_name/src/scss/g-plugins/woocommerce/upstream
    git rm -f ./wp-content/themes/$theme_folder_name/src/scss/g-plugins/woocommerce/upstream
    rm -rf .git/modules/wp-content/themes/$theme_folder_name/src/scss/g-plugins/woocommerce/upstream

    # Get the contents from the package.json file and echo only one key
    DEV_SCRIPT=$(node -p -e "require('./package.json').scripts.dev")
    # If the dev script contains 'git submodule update --remote' remove it
    if [[ $DEV_SCRIPT == *"git submodule update --remote"* ]]; then
      echo "Removing git submodule update --remote from dev script"
      # Remove the git submodule update --remote from the dev script
      npm pkg set scripts.dev "${DEV_SCRIPT/git submodule update --remote && /}"
    fi
  }

  main "$@"
)
