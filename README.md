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

### Setup

After installing, run:

```sh
labelvier setup
```

It checks the tools the CLI needs (Homebrew, git, jq, nvm and Node.js, Docker,
Composer), offers to install what is missing (nvm via `brew install nvm`, which
also adds the nvm lines to your `~/.zshrc`), sets up clickable update
notifications (`terminal-notifier`) and then offers to check and install the
AI setup (`labelvier ai update`). Nothing is installed without your yes. Run
`labelvier setup tools` to only check the tools.

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

### GitOps (Laravel on SiteGround)

`labelvier gitops setup` walks you through GitOps for a Laravel project: every PR
merged into the base branch is merged into `staging` and deployed with Deployer
by GitHub Actions. Run it from the project:

```sh
labelvier gitops setup     # wizard: project files, server, deploy key, public_html symlink, GitHub secrets, first deploy
labelvier gitops tests     # run the local tests in GitHub Actions too: before each deploy and/or on every opened or updated PR
labelvier gitops status    # what is in place, whether the workflows are live on origin, and the state of the tests
```

The app `.env` stays on the server (`shared/.env`) and is never sent to GitHub;
GitHub only gets the deploy key and the SSH target. An existing `public_html`
directory is moved aside (or deleted after typing the domain), never silently.

### SiteGround

`labelvier siteground` creates and configures SiteGround sites through the
same API as my.siteground.com. It is a Node CLI in `node/siteground`; the
first run installs its dependencies.

```sh
labelvier siteground login        # browser opens, log in incl. 2FA
labelvier siteground create-site  # asks for domain, plan, app and extras
labelvier siteground              # all commands
```

The session and generated passwords are stored in
`~/.config/labelvier/siteground` (override with `SG_STATE_DIR`).

`labelvier siteground setup` stores your email and password, and optionally
the TOTP secret (base32 from the authenticator setup), in
`~/.config/labelvier/siteground/.env` (chmod 600). After that `login` fills
the form in by itself; without the secret you still type the 2FA code. Without
setup, `login` just opens the browser for you. A reCAPTCHA or a missing value
is left for you in the browser window. `logout` removes the session and browser
profile; `logout --forget` also the stored credentials.
