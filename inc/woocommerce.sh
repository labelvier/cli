#!/bin/bash

# Enable woocommerce scss compilation.
function woocommerce() {
  # Check if we are in the right directory
  if [ ! -f "./wp-content/themes/labelvier/src/main.scss" ]; then
    echo "You are not in the right directory. Please run this command from the root of your theme."
    exit 1
  fi

  # If second argument is 'add' or 'remove', add or remove the woocommerce styling
  if [ "$1" = "add" ]; then
    echo "Adding woocommerce styling"
    # Remove optionally orphan folder
    git submodule deinit -f ./wp-content/themes/labelvier/src/scss/g-plugins/woocommerce/upstream &> /dev/null || true
    git rm -f ./wp-content/themes/labelvier/src/scss/g-plugins/woocommerce/upstream &> /dev/null || true
    rm -rf .git/modules/wp-content/themes/labelvier/src/scss/g-plugins/woocommerce/upstream &> /dev/null || true

    # Add a git submodule for the woocommerce scss files from https://github.com/woocommerce/woocommerce.git to the theme folder
    # Checkout the to-be submodule
    # I did not find a way to add submodule in 1 step without checking out
    git clone --depth=1 --no-checkout https://github.com/woocommerce/woocommerce.git ./wp-content/themes/labelvier/src/scss/g-plugins/woocommerce/upstream

    # Add as a submodule
    git submodule add https://github.com/woocommerce/woocommerce.git ./wp-content/themes/labelvier/src/scss/g-plugins/woocommerce/upstream

    # Move the .git dir from path/some-repo/.git into parent repo's .git
    git submodule absorbgitdirs

    # Note there is no "submodule.sub.sparsecheckout" key
    git -C ./wp-content/themes/labelvier/src/scss/g-plugins/woocommerce/upstream config core.sparseCheckout true

    # This pattern determines which files within some-repo.git get checked out.
    # Note quoted wildcards to avoid their expansion by shell
    echo 'plugins/woocommerce/client/legacy/css/*'  >> .git/modules/wp-content/themes/labelvier/src/scss/g-plugins/woocommerce/upstream/info/sparse-checkout

    # Actually do the checkout
    git submodule update --force --checkout

    # Get the contents from the package.json file and echo only one key
    DEV_SCRIPT=$(node -p -e "require('./package.json').scripts.dev");
    # If the dev script doesn't contain 'git submodule update --remote' prepend it
    if [[ ! $DEV_SCRIPT == *"git submodule update --remote"* ]]; then
      echo "Adding git submodule update --remote to dev script"
      # Prepend the git submodule update --remote to the dev script
      npm pkg set scripts.dev "git submodule update --remote && $DEV_SCRIPT"
    fi

  elif [ "$1" = "remove" ]; then
    echo "Removing woocommerce styling"
    # Remove woocommerce styling from the scss file
    # Remove the submodule
    git submodule deinit -f ./wp-content/themes/labelvier/src/scss/g-plugins/woocommerce/upstream
    git rm -f ./wp-content/themes/labelvier/src/scss/g-plugins/woocommerce/upstream
    rm -rf .git/modules/wp-content/themes/labelvier/src/scss/g-plugins/woocommerce/upstream

    # Get the contents from the package.json file and echo only one key
    DEV_SCRIPT=$(node -p -e "require('./package.json').scripts.dev");
    # If the dev script contains 'git submodule update --remote' remove it
    if [[ $DEV_SCRIPT == *"git submodule update --remote"* ]]; then
      echo "Removing git submodule update --remote from dev script"
      # Remove the git submodule update --remote from the dev script
      npm pkg set scripts.dev "${DEV_SCRIPT/git submodule update --remote && /}"
    fi
  else
    echo "Usage: $main_function woocommerce <add|remove>"
    exit 1
  fi
}
