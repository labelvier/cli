#!/bin/bash

starterkit() (

  # Local filename to echo the documentation.
  local filename="starterkit.sh"

  # Runs the command.
  function main() {
    # try to run the subcommand passed as the second argument and that function exists
    if [[ -n "$1" ]] && type -t "$1" | grep -q 'function'; then
      "$1"
    else
      # if no subcommand is passed, run the documentation function
      _echo_documentation "inc/$filename"
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
    read -p "Which branch do you want to use? (default: master) " branch
    branch=${branch:-master}

    # Ask what the theme name should be
    read -p "What should the theme name be? (default: labelvier) " theme_name
    theme_name=${theme_name:-labelvier}

    # Download and install the latest version of the wp-takeoff starter kit with a depth of 1
    git clone -b $branch --single-branch --depth 1 git@bitbucket.org:labelvier/wordpress-starter-kit.git $project_name || exit 1
    cd $project_name || exit 1
    rm -rf .git

    # Rename the theme folder wp-content/themes/labelvier to the theme name (if it's not labelvier)
    if [[ "$theme_name" != "labelvier" ]]; then
      mv wp-content/themes/labelvier wp-content/themes/$theme_name
      # in the example.env file replace the theme name for the lines which start with THEME_FOLDER_NAME DEV_THEME_PATH
      sed -i '' "s/labelvier/$theme_name/g" example.env
    fi


    # Copy the example.env file to .env
    cp example.env .env

    # Install the dependencies
    echo "Installing dependencies... (npm install)"
    npm run install || exit 1

    # Create a new git repository (don't output the output)
    git init
    git add .
    git commit -m "Initial commit" > /dev/null

    # Ask if the user already has a remote repository
    read -p "Do you already have an empty remote repository? (y/n) " remote_repo
    if [[ "$remote_repo" == "y" ]]; then
      # Ask for the remote repository url
      read -p "What is the url of your empty remote repository? " remote_repo_url
      # Add the remote repository
      git remote add origin $remote_repo_url
      # Push the code to the remote repository
      git push -u origin master
    fi

    echo "Installation complete"
  }

  main "$@"
)
