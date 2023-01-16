#!/bin/bash

function _needs_active_wptakeoff_project() {
  # Check if we are in the right directory
  if [ ! -f "./wp-content/themes/labelvier/src/main.scss" ]; then
    echo "You are not in the right directory. Please run this command from the root of your theme."
    exit 1
  fi
}
