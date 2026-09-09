<img src="assets/logo.svg" width="300" height="100" alt="Label Vier">

# Label Vier CLI

The Label Vier CLI (`labelvier`, shorthand `l4`) is a command line interface
for the Label Vier WordPress Starter Kit. It helps you install the starter
kit, manage your WordPress projects, run releases, and more.

> `wp-takeoff` was the old name for this tool. It still works — it's a
> symlink to the same script — but prints a deprecation notice pointing at
> `labelvier`/`l4`. New scripts and aliases should use `labelvier` or `l4`.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/labelvier/cli/master/scripts/install.sh | bash
```

This clones the CLI to `~/.labelvier`, adds it to your `$PATH`, and drops you
into a fresh shell so `labelvier`/`l4` works right away — no manual restart
needed.

Prefer to do it by hand? Clone the repo yourself and run `core install`
from inside it:

```sh
git clone git@github.com:labelvier/cli.git
cd cli
./labelvier core install
```

Want an even shorter alias (e.g. `wt`)? Run:

```sh
labelvier core alias
```

### Documentation

Running `labelvier` (or `l4`) with no arguments lists all available
commands. Running any command without arguments lists all available
subcommands for it — e.g. `labelvier core` lists everything under `core`.

### Install the WordPress starter kit

Run this from the folder where all your projects live:

```sh
labelvier starterkit install
```
