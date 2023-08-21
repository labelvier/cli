#!/bin/bash

# Sync uploads from the source to the destination
# Usage: ./sync-uploads.sh [source] [source_port] [source_directory] [destination_directory]
source_user=$1
source_hostname=$2
source_port=$3
source_directory=$4
destination_directory=$5
#check if the lock file exists
if [ -f ./.sync_running ]; then
    echo "Sync is already running"
    exit 1
fi
# run the rsync command and write the output to a log file
touch ./.sync_running
rsync -e "ssh -p $source_port" -av --stats $source_user@$source_hostname:"$source_directory" "$destination_directory" > ./sync-uploads.log
# when finished delete the lock file, but first copy it for log purposes
cp ./sync-uploads.log ./sync-uploads-$(date +"%Y-%m-%d-%H-%M-%S").log
rm ./sync-uploads.log
rm ./.sync_running
# exit
exit 0