#!/bin/bash

# Run all cron jobs and action scheduler actions
# first set the PHP version
export PHP_BIN=php82
# get the wp path (/home/customer/www/(.*)/public_html). Any folder in www will do
# find the folder in www
WP_PATH=$(find /home/customer/www/*/public_html -maxdepth 0)
# check if we have a multisite
MULTISITE=$(wp site list --field=url --path=$WP_PATH | wc -l)
if [ $MULTISITE -gt 1 ]; then
  # get the list of sites
  SITES=$(wp site list --field=url --path=$WP_PATH)
  for SITE in $SITES; do
    # run the cron events
    echo "Running cron events for $SITE"
    wp action-scheduler run --url="$SITE" --path=$WP_PATH
    wp cron event run --url="$SITE" --path=$WP_PATH --due-now
  done
else
  # run the cron events
  echo "Running cron events for $WP_PATH"
  wp action-scheduler run --path=$WP_PATH
  wp cron event run --path=$WP_PATH --due-now
fi
