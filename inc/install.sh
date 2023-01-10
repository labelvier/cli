#!/bin/bash

function install() {
  # Ask for the project name
  read -p "What is the name of your project (root folder)? " project_name
  # Ask which branch to use (default master)
  read -p "Which branch do you want to use? (default: master) " branch
  if [ -z "$branch" ]; then
    branch="master"
  fi

  # Ask what the theme name should be
  read -p "What should the theme name be? (default: labelvier) " theme_name
  if [ -z "$theme_name" ]; then
    theme_name="labelvier"
  fi

  # Download and install the latest version of the wp-takeoff starter kit with a depth of 1
  git clone -b $branch --single-branch --depth 1 git@bitbucket.org:labelvier/wordpress-starter-kit.git $project_name || exit 1
  cd $project_name || exit 1
  rm -rf .git

  # Rename the theme folder wp-content/themes/labelvier to the theme name
  mv wp-content/themes/labelvier wp-content/themes/$theme_name

  # in the example.env file replace the theme name for the lines which start with THEME_FOLDER_NAME DEV_THEME_PATH
  sed -i '' "s/labelvier/$theme_name/g" example.env

  # Copy the example.env file to .env
  cp example.env .env

  # Install the dependencies
  echo "Installing dependencies... (npm install)"
  npm run install || exit 1

  # Create a new git repository (don't output the output)
  git init
  git add .
  git commit -m "Initial commit" > /dev/null

  echo "Installation complete"
}
