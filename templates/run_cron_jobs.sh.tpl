#!/bin/bash

# Run all cron jobs and action scheduler actions
# get the wp path (/home/customer/www/(.*)/public_html). Any folder in www will do
# find the folder in www and pick the first one found
WP_PATH=$(find /home/customer/www/*/public_html -maxdepth 0 | grep -E 'public_html$' | head -n 1)

# check if we have a multisite
MULTISITE=$(wp site list --field=url --path=$WP_PATH | wc -l)
if [ $MULTISITE -gt 1 ]; then
  # get the list of sites
  SITES=$(wp site list --field=url --path=$WP_PATH)
  for SITE in $SITES; do
    # run the cron events
    echo "Running cron events for $SITE"
    wp cron event run --url="$SITE" --path=$WP_PATH --due-now
    echo "Running action scheduler for $SITE"
    wp action-scheduler clean --url="$SITE" --path=$WP_PATH
    wp action-scheduler run --url="$SITE" --path=$WP_PATH
  done
else
  # run the cron events
  echo "Running cron events for $WP_PATH"
  wp cron event run --path=$WP_PATH --due-now
  echo "Running action scheduler for $WP_PATH"
  wp action-scheduler clean --path=$WP_PATH
  wp action-scheduler run --path=$WP_PATH
fi
