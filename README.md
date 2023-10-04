# README #

The WP Takeoff CLI is a command line interface for the WP Takeoff starterkit. It allows you to install the starterkit and manage your WordPress projects, do releases and more.

## Install the wp-takeoff CLI

### Run the following command to clone the repository:


`git clone git@bitbucket.org:labelvier/wp-takeoff-cli.git`

This will clone the repository to a new directory named `wp-takeoff-cli` in the current directory.

Note: If you don't have set up SSH keys for your Bitbucket account, you can use HTTPS instead of SSH to clone the repository. To do this, replace the SSH URL in the `git clone` command with the HTTPS URL.


`git clone https://bitbucket.org/labelvier/wp-takeoff-cli.git`

### Install the core for the current repository by running the following command:

`./wp-takeoff core install`

After the installation you get the option to choose which $PATH variable you want to set and choose the correct option.

From now on you can globally use the `wp-takeoff` command. Hint, if you want to set and alias run the following command:

`wp-takeoff core alias`

### Documentation

Running `wp-takeoff` will give you a list of all available commands.

Running any command without any arguments will give you a list of all available options for that command. For example, running `wp-takeoff core` will give you a list of all available options for the core command.

### Install the WordPress starterkit

Run this from the folder where all your projects are located.

`wp-takeoff starterkit install`

