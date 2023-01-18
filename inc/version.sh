#!/bin/bash

function _run_update_checker() {
  # Check if there are updates available from git and ask if we should pull them
  if [ -d ".git" ]; then
    # echo date minus 12 hours, don't use -d option because it's not available on mac
    last_update=$(date -u -r .git/FETCH_HEAD +%s)
    now=$(date -u +%s)
    diff=$(($now - $last_update))

    # Don't check if we checked in the last 12 hours
    if [ ! -f ".last_git_check" ] || [ $diff -gt 43200 ]; then
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
