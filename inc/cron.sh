#!/bin/bash

cron() (

  # Local filename to echo the documentation.
  local filename="cron.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")

  # Runs the command.
  function main() {
    _dispatch "$filename" "$@"
  }

  # @function deploy
  # @description Deploy the cron job to a server, this will upload the run_cron_jobs.sh.tpl file to the server and set the DISABLE_WP_CRON constant to true. Argument is the SSH host to deploy to.
  function deploy() {
    # Check if we have a second argument
    if [ $# -eq 0 ]; then
      echo "Please provide a ssh host to deploy to."
      exit 1
    else
      SSH=$1
      # try to login to $1 and travel to the project folder
      # find the project folder
      WP_PATH=$(ssh $SSH "find /home/customer/www/*/public_html -maxdepth 0 | grep -E 'public_html$' | head -n 1")
      if [[ -z "$WP_PATH" ]]; then
        echo "No project folder found. Exiting."
        exit 1
      fi
      ssh $SSH "cd $WP_PATH && wp config set DISABLE_WP_CRON true --raw"
      # upload the run_cron_jobs.sh.tpl file to the server
      scp $current_dir/../templates/run_cron_jobs.sh.tpl $SSH:/home/customer/run_cron_jobs.sh
      # add chmod +x to the uploaded file
      ssh $SSH "chmod +x /home/customer/run_cron_jobs.sh"
      # echo information that you now need to add the following cronjob to the server
      echo -e "${__green}${__bold}Success!${__reset} ${__bold}Add the following cronjob to the server:${__reset}"
      echo -e "${__blue}*/5 * * * * /bin/bash /home/customer/run_cron_jobs.sh${__reset}"
    fi
  }

  main "$@"
)
