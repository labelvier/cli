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
  # @description Deploy the cron job to a server, this will upload the run_cron_jobs.sh.tpl file to the server, set the DISABLE_WP_CRON constant to true and offer to add the cron job through SiteGround. Argument is the SSH host to deploy to.
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
      echo -e "${__green}${__bold}Success!${__reset} The cron runner is on the server."

      # The site's domain is the folder name: /home/customer/www/<domain>/public_html.
      local domain
      domain=$(echo "$WP_PATH" | sed -n 's#^/home/customer/www/\([^/]*\)/public_html$#\1#p')
      if ! _add_siteground_cron "$domain"; then
        echo -e "${__bold}Add the following cronjob to the server:${__reset}"
        echo -e "${__blue}$cron_schedule $cron_command${__reset}"
      fi
    fi
  }

  local cron_schedule="*/5 * * * *"
  local cron_command="/bin/bash /home/customer/run_cron_jobs.sh"

  # Offers to add the runner's cron job through `labelvier siteground site:cron`.
  # Returns 0 when the job is on the site (added now or already there), 1 when
  # it was not added: declined, no terminal, unknown domain or a failed call.
  # Override the siteground command with CRON_SITEGROUND (tests).
  function _add_siteground_cron() {
    local domain="$1" sg="${CRON_SITEGROUND:-siteground}" jobs
    # The domain goes to the SiteGround API: only plain host names.
    [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || return 1

    _confirm "Add this cron job to $domain through SiteGround now?" || return 1

    if ! jobs=$($sg site:cron "$domain" --json); then
      echo -e "${__red}✗${__reset} Could not read the cron jobs of $domain. Logged in? Check: labelvier siteground session:status"
      return 1
    fi
    if grep -qF "$cron_command" <<< "$jobs"; then
      echo -e "${__green}✓${__reset} $domain already runs $cron_command, nothing added."
      return 0
    fi
    if ! $sg site:cron "$domain" --add "$cron_command" --at "$cron_schedule"; then
      echo -e "${__red}✗${__reset} Adding the cron job to $domain failed."
      return 1
    fi
  }

  main "$@"
)
