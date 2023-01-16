#!/bin/bash

function _run_update_checker() {
  # Check if there are updates available from git and ask if we should pull them
  if [ -d ".git" ]; then
    # Don't check if we checked in the last 12 hours
    if [ ! -f ".last_git_check" ] || [ $(date -d "-12 hours" +%s) -gt $(date -r ".last_git_check" +%s) ]; then
      _check_and_ask_for_update
      touch .last_git_check
    fi
  fi
}

function _check_and_ask_for_update() {
  # Check if there are updates available from git and ask if we should pull them
  if [ -d ".git" ]; then
    # Don't check if we checked in the last 12 hours
    git fetch
    if [ $(git rev-parse HEAD) != $(git rev-parse @{u}) ]; then
      echo "There are updates available from git. Do you want to pull them? (y/n)"
      read -r answer
      if [ "$answer" = "y" ]; then
        git pull
      fi
    fi
  fi
}
