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
needed. It follows `master`, so you always get the newest release and the
update checker keeps offering new ones.

### Pinning a release

Every release has its own install line, listed in the release notes:

```sh
curl -fsSL https://raw.githubusercontent.com/labelvier/cli/1.0.3/scripts/install.sh | bash -s -- 1.0.3
```

The ref in the URL only picks which installer you download; the version
argument is what decides which version ends up in `~/.labelvier`. Passing both
keeps the two in step. `LABELVIER_CLI_REF=1.0.3` does the same thing as the
argument.

A pinned install sits on a detached HEAD. The update checker notices that and
compares against the newest tag instead of the branch, so it still tells you
when a new release is out. Running the plain install line again moves you back
to `master`.

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
