#!/bin/bash

starterkit() (

  # Local filename to echo the documentation.
  local filename="starterkit.sh"

  # Runs the command.
  function main() {
    echo "Running $this_filename"
    # try to run the subcommand passed as the second argument and that function exists
    if [[ -n "$1" ]] && type -t "$1" | grep -q 'function'; then
      "$1"
    else
      # if no subcommand is passed, run the documentation function
      _echo_documentation "$filename"
    fi
  }

  # @function install
  # @description Installs the starterkit.
  function install() {
    # Ask for the project name
    read -p "What is the name of your project (root folder)? " project_name
    # exit if no project name is given
    if [[ -z "$project_name" ]]; then
      echo "No project name given. Exiting."
      exit 1
    fi

    # Ask which branch to use (default master)
    read -p "Which branch from the starter kit do you want to use? (default: master) " branch
    branch=${branch:-master}

    # Ask what the theme name should be
    read -p "What should the theme name be? (default: labelvier, don't use spaces) " theme_name
    theme_name=${theme_name:-labelvier}

    # Bail if the theme name has spaces
    if [[ "$theme_name" =~ " " ]]; then
      echo "Theme name cannot contain spaces. Exiting."
      exit 1
    fi

    # Download and install the latest version of the wp-takeoff starter kit with a depth of 1
    git clone -b $branch --single-branch --depth 1 git@bitbucket.org:labelvier/wordpress-starter-kit.git $project_name || exit 1
    cd $project_name || exit 1
    rm -rf .git

    # Rename the theme folder wp-content/themes/labelvier to the theme name (if it's not labelvier)
    if [[ "$theme_name" != "labelvier" ]]; then
      mv wp-content/themes/labelvier wp-content/themes/$theme_name
      # in the example.env file replace the theme name for the lines which start with THEME_FOLDER_NAME DEV_THEME_PATH ubuntu and mac friendly
      sed -i.bak "s/labelvier/$theme_name/g" example.env && rm example.env.bak
      # Rename $theme-path: "/wp-content/themes/labelvier" in _variables.scss
      sed -i.bak "s/\$theme-path: \"\/wp-content\/themes\/labelvier\"/\$theme-path: \"\/wp-content\/themes\/$theme_name\"/g" wp-content/themes/$theme_name/src/scss/a-settings/_variables.scss && rm wp-content/themes/$theme_name/src/scss/a-settings/_variables.scss.bak
      # Rename Theme Name: Labelvier in style.scss
      sed -i.bak "s/Theme Name: Labelvier/Theme Name: $theme_name/g" wp-content/themes/$theme_name/src/scss/style.scss && rm wp-content/themes/$theme_name/src/scss/style.scss.bak
    fi


    # Copy the example.env file to .env
    cp example.env .env

    # Install the dependencies
    echo "Installing dependencies... (npm install)"
    npm run install || exit 1

    # Ask if you want to install woocommerce
    read -p "Do you want to install woocommerce? (y/n) " woocommerce
    if [[ "$woocommerce" == "y" ]]; then
      # Install woocommerce
      echo "Adding woocommerce support..."
      woocomerce add
    fi

    # Create a new git repository (don't output the output)
    git init
    git add .
    git commit -m "Initial commit" > /dev/null

    # Ask if the user already has a remote repository
    read -p "Do you already have an empty remote repository? (y/n) " remote_repo
    if [[ "$remote_repo" == "y" ]]; then
      # Ask for the remote repository url
      read -p "What is the url of your empty remote repository? (example: git@bitbucket.org:labelvier/example.git) " remote_repo_url
      # Add the remote repository
      git remote add origin $remote_repo_url
      # Push the code to the remote repository
      git push -u origin master
    fi

    echo "Installation complete"
  }

  # @function fix-permissions
  # @description Fixes the permissions of the project.
  function fix-permissions() {
    # Check if there is a docker container running with wordpress in the name
    wordpress_container=$(docker ps -qf "name=wordpress")
    if [[ -n "$wordpress_container" ]]; then
      echo "Fixing permissions...";
      # Fix the permissions
      docker exec -it "$wordpress_container" chown -R www-data:www-data /var/www/html
      echo "Permissions fixed.";
    else
      echo "There is no wordpress docker container running. Please start the docker container and try again."
    fi
  }

  main "$@"
)
