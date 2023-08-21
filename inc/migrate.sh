#!/bin/bash

migrate() (

  # Local filename to echo the documentation.
  local filename="migrate.sh"
  # get the current directory name of this file
  local current_dir=$(dirname "${BASH_SOURCE[0]}")
  local root_dir=$(pwd)
  local migration_config_file="$__dir/.migration";

  # Runs the command.
  function main() {
    # try to run the subcommand passed as the second argument and that function exists
    if [[ -n "$1" ]] && type -t "$1" | grep -q 'function'; then
      # attach any remaining arguments to the function
      "$1" "${@:2}"
    else
      # if no subcommand is passed, run the documentation function
      _echo_documentation "$filename"
    fi
  }

  # @function load
  # @description Loads the configuration file from migration_profiles.
  function load() {
    # check if the migration_profiles directory exists and if there are any files in it
    if [[ ! -d "$__dir/migration_profiles" ]] || [[ ! -n "$(ls -A "$__dir/migration_profiles")" ]]; then
      echo "No migration profiles found, please create one first."
      exit 1
    fi

    # get the migration profile from the user and list them in a select
    local migration_profiles
    migration_profiles=$(ls "$__dir/migration_profiles")
    echo "Please select a migration profile:"
    select migration_profile in $migration_profiles; do
      # check if the migration profile exists
      if [[ -f "$__dir/migration_profiles/$migration_profile" ]]; then
        # load the migration profile
        cp "$__dir/migration_profiles/$migration_profile" $migration_config_file
        # run the migration
        run
        break
      else
        echo "The migration profile does not exist, please try again."
      fi
    done

  }

  # @function start
  # @description Start a new migration from one server to another. Currently only supports from any VPS (needs ssh, rsync and wp cli) to siteground.
  function start() {
    # check if the $migration_config_file file exists
    if [[ -f $migration_config_file ]]; then
      source "$migration_config_file";
      echo "A migration is already in progress (from $ssh_hostname to $ssh_hostname_destination), do you want to continue?"
      select yn in "Yes" "No" "View migration file" "Start new migration"; do
        case $yn in
        Yes) break ;;
        No) exit ;;
        "View migration file")
          cat $migration_config_file
          ;;
        "Start new migration")
          rm $migration_config_file
          break
          ;;
        esac
      done
    fi

    # run the migration
    run
  }

  function run() {
  # if the $migration_config_file file does not exist, ask for the credentials
  if [[ ! -f "$migration_config_file" ]]; then
    # ask the SSH credentials for the source server
    read -p "Enter the SSH username for the source server: " ssh_username
    read -p "Enter the SSH hostname for the source server: " ssh_hostname
    read -p "Enter the SSH port for the source server, leave empty for default (22): " ssh_port
    ssh_port=${ssh_port:-22}
    read -p "Enter the SSH path for the source server, leave empty for savvii default (wordpress/current): " ssh_path
    ssh_path=${ssh_path:-wordpress/current}
    # do a ssh-copy-id to check if the credentials are correct
    ssh-copy-id -p "$ssh_port" "$ssh_username@$ssh_hostname"
    if [[ $? -ne 0 ]]; then
      echo "SSH credentials for the source server are incorrect, please try again."
      exit 1
    fi

    # create an $migration_config_file file with all the credentials
    echo "ssh_username=$ssh_username" >$migration_config_file
    echo "ssh_hostname=$ssh_hostname" >>$migration_config_file
    echo "ssh_port=$ssh_port" >>$migration_config_file
    echo "ssh_path=$ssh_path" >>$migration_config_file

    # ask the SSH credentials for the destination server
    read -p "Enter the domain of the destination server (excluding https://, leave empty for no change): " ssh_domain_destination
    read -p "Enter the SSH username for the destination server: " ssh_username_destination
    read -p "Enter the SSH hostname for the destination server: " ssh_hostname_destination
    ssh_hostname_destination=${ssh_hostname_destination:-c124849.sgvps.net}
    read -p "Enter the SSH port for the destination server, leave empty for siteground default (18765): " ssh_port_destination
    ssh_port_destination=${ssh_port_destination:-18765}
    # the default path for siteground is www/$ssh_domain_destination/public_html, where $ssh_domain_destination is excluding http(s)://
    ssh_dir_destination_default="www/$ssh_domain_destination/public_html"

    read -p "Enter the SSH path for the destination server, leave empty for siteground default ($ssh_dir_destination_default): " ssh_path_destination
    ssh_path_destination=${ssh_path_destination:-"$ssh_dir_destination_default"}
    # do a ssh-copy-id to check if the credentials are correct
    ssh-copy-id -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination"
    if [[ $? -ne 0 ]]; then
      echo "SSH credentials for the destination server are incorrect, please try again."
      rm $migration_config_file
      exit 1
    fi

    # create an $migration_config_file file with all the credentials
    echo "ssh_domain_destination=$ssh_domain_destination" >>$migration_config_file
    echo "ssh_username_destination=$ssh_username_destination" >>$migration_config_file
    echo "ssh_hostname_destination=$ssh_hostname_destination" >>$migration_config_file
    echo "ssh_port_destination=$ssh_port_destination" >>$migration_config_file
    echo "ssh_path_destination=$ssh_path_destination" >>$migration_config_file
  else
    # if the $migration_config_file file exists, read the credentials from it
    source $migration_config_file
  fi

  # check if the destination server is has a pub key in the .ssh directory
  ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "ls .ssh/id_ed25519.pub" >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    echo "The destination server does not have a public key in the .ssh directory, we'll add it first."
    # create a new key pair on the destination server, command ssh-keygen -t ed25519 -b 4096 -C "$ssh_username_destination@$ssh_hostname_destination"
    ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "ssh-keygen -t ed25519 -b 4096 -C \"$ssh_username_destination@$ssh_hostname_destination\""
  fi

  # check if the public key of the destination server is added to the source server
  ssh -p "$ssh_port" "$ssh_username@$ssh_hostname" "grep -q \"$(ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "cat .ssh/id_ed25519.pub")\" .ssh/authorized_keys" >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    echo "The public key of the destination server is not added to the source server, we'll add it first."
    # add the public key of the destination server to the source server
    ssh -p "$ssh_port" "$ssh_username@$ssh_hostname" "echo \"$(ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "cat .ssh/id_ed25519.pub")\" >> .ssh/authorized_keys"
  fi

  # ask to save the $migration_config_file file to a profile, check if $migration_profile_name is set
  if [[ -z "$migration_profile_name" ]]; then
    read -p "Do you want to save the migration profile? (y/n) " -n 1 -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo ""
      echo "Saving the migration profile..."
      read -p "Enter a name for the migration profile: " migration_profile_name
      echo "migration_profile_name=$migration_profile_name" >>$migration_config_file
      # create the migration_profiles directory if it does not exist
      mkdir -p migration_profiles
      cp $migration_config_file "$__dir/migration_profiles/$migration_profile_name"
      echo "migration_saved=true" >>"$__dir/migration_profiles/$migration_profile_name"
    fi
  fi

  # on the source server, create a new database dump wp db export (directory is set in the $migration_config_file file)
  echo ""
  echo "Creating a new database dump on the source server..."

  # check if the wp cli is available on the source server
  wp_cli="wp"
  wp_cli_version=$(ssh -p "$ssh_port" "$ssh_username@$ssh_hostname" "wp --version")
  # if the wp cli version should contain WP-CLI
  if [[ $wp_cli_version != *"WP-CLI"* ]]; then
    # try with /opt/plesk/php/8.2/bin/php  /usr/local/bin/wp
    echo "WP CLI is not available on the source server, trying with /opt/plesk/php/8.2/bin/php  /usr/local/bin/wp"
    wp_cli="/opt/plesk/php/8.2/bin/php  /usr/local/bin/wp"
    wp_cli_version=$(ssh -p "$ssh_port" "$ssh_username@$ssh_hostname" "$wp_cli --version")
    if [[ $wp_cli_version != *"WP-CLI"* ]]; then
      echo "WP CLI is not available on the source server, so we cannot start the migration."
      exit 1
    fi
  fi
  echo "WP CLI is available on the source server, version $wp_cli_version"

  # run the wp db export command on the source server
  # check if --skip-database-export is set
  echo "Running the wp db export command on the source server..."
  ssh -p "$ssh_port" "$ssh_username@$ssh_hostname" "$wp_cli db export migration_export.sql --path=$ssh_path --default-character-set=utf8mb4"
  # copy the database dump to the destination server
  echo "Copying the database dump to the destination server..."
  # run the scp command from the destination server, because the source server does not have a public key for the destination server
  ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "scp -o StrictHostKeyChecking=no  -P $ssh_port $ssh_username@$ssh_hostname:migration_export.sql ./migration_export.sql"
  # on the destination server, create a new backup of the database
  echo "Creating a new backup of the database on the destination server..."
  ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp db export migration_backup.sql --path=$ssh_path_destination"
  # do a wp db reset on the destination server
  echo "Resetting the database on the destination server..."
  ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp db reset --yes --path=\"$ssh_path_destination\""
  # on the destination server, import the database dump wp db import (directory is set in the $migration_config_file file)
  echo "Importing the database dump on the destination server..."
  ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp db import ~/migration_export.sql --path=$ssh_path_destination"
  # delete the database dump on the destination server
  echo "Deleting the database dump on the destination server..."
  ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "rm migration_export.sql"
  # on the destination server, set wp config set table_prefix wp_
  echo "Setting the table prefix on the destination server..."
  # get the table prefix from the source server
  source_table_prefix=$(ssh -p "$ssh_port" "$ssh_username@$ssh_hostname" "wp config get table_prefix --path=$ssh_path")
  ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp config set table_prefix $source_table_prefix --path=$ssh_path_destination"
  # Sync alle thema's bestanden en dergelijke naar nieuwe server
  echo "Syncing the wp-content themes and plugins directories to the destination server..."
  # run this command on the destination server, because the destination server has the private key
  ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "rsync -e \"ssh -p $ssh_port\" -av --stats $ssh_username@$ssh_hostname:$ssh_path/wp-content/{themes,plugins,languages} \"./$ssh_path_destination/wp-content\""
  # on the destination server, search and replace the old domain with the new domain, if the domain is not empty
  is_multisite="0"
  if [[ -n $ssh_domain_destination ]]; then
    # get the primary domain from the source server
    ssh_domain=$(ssh -p "$ssh_port" "$ssh_username@$ssh_hostname" "$wp_cli option get siteurl --path=$ssh_path")
    # remove http:// or https://
    old_domain=$(echo "$ssh_domain" | sed 's/http[s]*:\/\///g')
    new_domain=$(echo "$ssh_domain_destination" | sed 's/\//\\\//g')
    echo "Replacing the domain ($ssh_domain) on the destination server to $ssh_domain_destination..."
    ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp search-replace $ssh_domain https://$ssh_domain_destination --path=$ssh_path_destination --all-tables"
    # do another search and replace for wp_blogs if this is a multisite on the destination server
    is_multisite=$(ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp config get MULTISITE --path=$ssh_path_destination")
    if [[ $is_multisite == "1" ]]; then
      echo "Replacing the domain ($ssh_domain) on the destination server to $ssh_domain_destination in the wp_blogs table..."
      ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp search-replace $old_domain $new_domain --url=$old_domain --path=$ssh_path_destination wp_blogs"
    fi
  fi

  # lastly, sync the uploads directory
  echo "Syncing the wp-content uploads directory to the destination server..."
  # copy the bash script to the destination server and run it from there in the background so we can continue
  scp -o StrictHostKeyChecking=no -P $ssh_port_destination "$current_dir/../templates/sync_uploads.sh.tpl" "$ssh_username_destination@$ssh_hostname_destination:sync_uploads.sh"
  # run the bash script on the destination server # Usage: ./sync-uploads.sh [source] [source_port] [source_directory] [destination_directory]
  echo "Starting the sync uploads script on the destination server... To view the status, run wt migrate sync-status"
  ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "bash sync_uploads.sh $ssh_username $ssh_hostname $ssh_port "$ssh_path/wp-content/uploads" "$ssh_path_destination/wp-content" &" &

  # on the destination server, check if there are any new constants in the wp-config.php file
  echo "Checking if there are any missing constants in the wp-config.php file on the destination server..."
  # get all defines from the wp-config.migrated.php file on the destination server
  ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp config list --format=csv --path=$ssh_path_destination" >wp-config.migrated.csv
  # get all defines from the wp-config.php file on the source server
  ssh -p "$ssh_port" "$ssh_username@$ssh_hostname" "wp config list --format=csv --path=$ssh_path" >wp-config.csv
  # loop through the defines in the wp-config.php file on the source server
  ssh_domain=$(ssh -p "$ssh_port" "$ssh_username@$ssh_hostname" "$wp_cli option get siteurl --path=$ssh_path")

  while IFS=, read -r key value; do
    # check if the key is not empty
    if [[ -n $key ]]; then
      # check if the key is not in the wp-config.migrated.php file on the destination server
      if ! grep -q "$key" wp-config.migrated.csv; then
        # clean value, remove ,constant
        value=$(echo "$value" | sed 's/,constant//g')
        # check if the value is not empty and we have a domain
        if [[ -n $value ]] && [[ -n $ssh_domain_destination ]]; then
          # replace the domain with the new domain
          value=$(echo "$value" | sed "s/$old_domain/$new_domain/g")
        fi
        # add the key to the wp-config.migrated.php file on the destination server when value is not empty
        echo "Adding the $key constant with value $value to the wp-config.php file on the destination server..."
        ssh -n -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp config set '$key' '$value' --type=constant --path=$ssh_path_destination"
      fi
    fi
  done <wp-config.csv
  # remove the wp-config.csv and wp-config.migrated.csv files
  rm wp-config.csv
  rm wp-config.migrated.csv

  # on the destination server, check if display_errors = 0 in the wp-config file
  # check for define( 'WP_DEBUG', false );
  # replace with define( 'WP_DEBUG', false );ini_set('display_errors', '0');
  echo "Checking for display_errors = 0 in the wp-config.php file on the destination server..."
  # check if ini_set('display_errors', '0'); is already in the wp-config.php file on the destination server
  display_errors=$(ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "grep -o 'ini_set('display_errors', '0');' $ssh_path_destination/wp-config.php")
  if [[ -z $display_errors ]]; then
    # check if define( 'WP_DEBUG', false ); is in the wp-config.php file on the destination server
    wp_debug=$(ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "grep -o 'define( 'WP_DEBUG', false );' $ssh_path_destination/wp-config.php")
    if [[ -n $wp_debug ]]; then
      # replace define( 'WP_DEBUG', false ); with define( 'WP_DEBUG', false );ini_set('display_errors', '0');
      echo "Replacing define( 'WP_DEBUG', false ); with define( 'WP_DEBUG', false );ini_set('display_errors', '0'); in the wp-config.php file on the destination server..."
      ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "sed -i '' 's/define( 'WP_DEBUG', false );/define( 'WP_DEBUG', false );ini_set('display_errors', '0');/g' $ssh_path_destination/wp-config.php"
    fi
  fi

  # check if the 'warpdrive' plugin is active on the destination server, if so deactivate it
  echo "Checking if the 'warpdrive' plugin is active on the destination server..."
  warpdrive_active=$(ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp plugin status warpdrive --path=$ssh_path_destination | grep -o 'Status: Active' | sed -e 's/^[ \t]*//'")
  if [[ $warpdrive_active == "Status: Active" ]]; then
    echo "Deleting the 'warpdrive' plugin on the destination server..."
    ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp plugin delete warpdrive --path=$ssh_path_destination"
  fi

  # loop through inactive plugins on the destination server and ask if they should be deleted, ignored or activated
  # get the list of inactive plugins on the destination server
  inactive_plugins=$(ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp plugin list --status=inactive --field=name --path=$ssh_path_destination")
  # loop through the inactive plugins
  for inactive_plugin in $inactive_plugins; do
    echo ""
    # ask what to do with the inactive plugin
    read -p "The plugin $inactive_plugin is inactive on the destination server. Do you want to delete, ignore, activate or activate network it? (d/i/a/n) " -n 1 -r
    if [[ $REPLY =~ ^[Dd]$ ]]; then
      # delete the inactive plugin
      echo ""
      echo "Deleting the inactive plugin $inactive_plugin on the destination server..."
      ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp plugin delete $inactive_plugin --path=$ssh_path_destination"
    elif [[ $REPLY =~ ^[Aa]$ ]]; then
      # activate the inactive plugin
      echo ""
      echo "Activating the inactive plugin $inactive_plugin on the destination server..."
      ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp plugin activate $inactive_plugin --path=$ssh_path_destination"
      # if the plugin is sg-cachepress run some extra commands
      if [[ $inactive_plugin == "sg-cachepress" ]]; then
        # wp sg optimize webp enable
        echo "Enabling the webp optimization on the destination server..."
        ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp sg optimize webp enable --path=$ssh_path_destination"
        # wp sg optimize dynamic-cache enable
        echo "Enabling the dynamic cache on the destination server..."
        ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp sg optimize dynamic-cache enable --path=$ssh_path_destination"
        # wp sg optimize file-cache enable
        echo "Enabling the file cache on the destination server..."
        ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp sg optimize file-cache enable --path=$ssh_path_destination"
        # wp sg memcached enable
        echo "Enabling the memcached on the destination server..."
        ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp sg memcached enable --path=$ssh_path_destination"
      fi
    elif [[ $REPLY =~ ^[Nn]$ ]]; then
      # activate the inactive plugin network wide
      echo ""
      echo "Activating the inactive plugin $inactive_plugin network wide on the destination server..."
      ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp plugin activate $inactive_plugin --network --path=$ssh_path_destination"
    else
      # do nothing
      echo ""
    fi
  done

  # on the destination server, clear cache
  echo "Clearing the cache on the destination server..."
  ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp cache flush --path=$ssh_path_destination"
  # flush rewrite rules
  echo "Flushing the rewrite rules on the destination server..."
  ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "wp rewrite flush --path=$ssh_path_destination"

  # ask to delete the migration_config_file file
  if [[ -f "$migration_config_file" ]]; then
    read -p "Done! Do you want to delete the active migration so you can start a new one next time? (y/n) " -n 1 -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Clearing..."
      rm $migration_config_file
    fi
  fi
}

  # @function sync-status
  # @description Show the status of the sync uploads script
  function sync-status() {
    # check if the migration_config_file file exists
    if [[ ! -f "$migration_config_file" ]]; then
      echo "No active migration found. Please run wt migrate start first or choose a saved profile."
      # list all the saved profiles from migration_profiles, and ask which one to use with a select
      migration_profiles=$(ls "$__dir/migration_profiles")
      echo "Saved profiles:"
      select migration_profile in $migration_profiles; do
        if [[ -n $migration_profile ]]; then
          # get the variables from the migration_profile file
          source "$__dir/migration_profiles/$migration_profile"
          break;
        else
          exit 1
        fi
      done
    else
      # get the variables from the migration_config_file file
      source "$migration_config_file"
    fi


    # check if the sync_uploads.sh file exists on the destination server
    if [[ ! $(ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "ls sync_uploads.sh") ]]; then
      echo "No sync uploads script found on the destination server. Please run wt migrate start first."
      exit 1;
    fi

    # check if the .sync_running file exists on the destination server
    if [[ ! $(ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "ls .sync_running") ]]; then
      # get the newest log file from the destination server which starts with .sync_running_
      ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "ls -t sync-uploads-* | head -1 | xargs cat"
      echo "The sync uploads script is not running on the destination server, this is a log of the latest sync (if there is one)."
      exit 1;
    else
      # tail -f the .sync_running file
      echo "The sync uploads script is running on the destination server, here is a log of the latest sync."
      ssh -p "$ssh_port_destination" "$ssh_username_destination@$ssh_hostname_destination" "tail -f sync-uploads.log"
    fi
  }

  main "$@"
)
