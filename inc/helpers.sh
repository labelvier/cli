#!/bin/bash

function _needs_active_wptakeoff_project() {
  # Check if we are in the right directory
  if [ ! -f "./wp-content/themes/labelvier/src/main.scss" ]; then
    echo "You are not in the right directory. Please run this command from the root of your theme."
    exit 1
  fi
}


function _check_for_updates() {
  # Check if there are updates available from git and ask if we should pull them
  if [ -d ".git" ]; then
    # Don't check if we checked in the last 12 hours
    if [ ! -f ".last_git_check" ] || [ $(date -d "-12 hours" +%s) -gt $(date -r ".last_git_check" +%s) ]; then
      git fetch
      if [ $(git rev-parse HEAD) != $(git rev-parse @{u}) ]; then
        echo "There are updates available from git. Do you want to pull them? (y/n)"
        read -r answer
        if [ "$answer" = "y" ]; then
          git pull
        fi
      fi
      touch .last_git_check
    fi
  fi
}
