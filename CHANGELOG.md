# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.5] - 2026-09-11

### Fixed
- `.gitignore` starts with `.*`, which swallowed `.github` as well. The release workflow added in 1.0.4 therefore never made it into the repository and no release was published for that tag. This is the first version whose tag actually carries the workflow.

## [1.0.4] - 2026-09-11

### Added
- A GitHub Release is now published for every tag. The notes come straight out of this changelog, so they cannot drift from it, and they carry the install line for that exact release.
- `scripts/install.sh` takes a version, either as an argument (`| bash -s -- 1.0.3`) or through `LABELVIER_CLI_REF`. Without one it follows `master` as before, and running it again on a pinned install moves you back to `master`.

### Fixed
- The update check no longer trips over an install that is pinned to a release. Such an install has no upstream branch, so every `rev-parse` against `@{u}` failed and the CLI asked about an update it could not perform. It now compares against the newest tag and offers to check that one out.

## [1.0.3] - 2026-09-09

### Added
- `ai claude install` now offers to install Homebrew itself (via the official install script) when it's missing, then falls through to the normal `brew install <thing>` prompt for `jq`, `rtk` and the Claude Code CLI.

## [1.0.2] - 2026-09-09

### Changed
- `scripts/install.sh` now drops into a fresh login shell after updating `$PATH`, so `labelvier`/`l4` works immediately without restarting the terminal or running `source ~/.zshrc`. Skipped in CI or piped/non-interactive installs, or when `LABELVIER_NO_EXEC` is set.

## [1.0.1] - 2026-09-09

### Added
- Braille-art logo banner (brand red) shown on the install script and the CLI's bare usage screen, with "Label Vier CLI" centered underneath.
- `labelvier ai claude install`/`uninstall` and `ai check` now also manage the caveman Claude Code plugin.

### Changed
- Rewrote the CLI's usage tagline to reflect its actual scope beyond WordPress scaffolding.

## [1.0.0] - 2026-09-09

### Added
- Moved to a new public repository, `labelvier/cli`, continuing the full history of the old `WP-Takeoff-CLI` repo.
- `labelvier` is the new canonical command name, with `l4` as a shorthand alias. `wp-takeoff` still works (it's now a symlink to the same script) but prints a deprecation notice pointing at `labelvier`/`l4`.
- `scripts/install.sh` — a non-interactive curl-installable script (`curl -fsSL .../install.sh | bash`) that clones the CLI to `~/.labelvier` and adds it to your `$PATH`.

### Changed
- `core install`/`core alias` now install to `~/.labelvier` and alias to `labelvier` instead of `~/.wp-takeoff`/`wp-takeoff`.
- README rewritten for the new repo, command names and install method.

## [0.29.0] - 2026-09-09

### Added
- Report unknown commands instead of silently showing docs
- Show fix command in ai check failures
- Install and check for rtk in Claude Code setup
- Add basecamp subcommand and consolidate status into ai check

### Changed
- Move CLAUDE.md content to labelvier/GLOBAL.md, never template CLAUDE.md (script changes)
- Move CLAUDE.md content to labelvier/GLOBAL.md, never template CLAUDE.md
- Move example.sh.tpl to templates/, allow non-interactive generate
- Share a _dispatch helper with --help support across commands
- Trim @description one-liners, document the convention

### Fixed
- Rename claude's install/uninstall so ai install can't reach them
- Actually wire rtk into Claude Code, not just install the binary

## [0.28.0] - 2026-09-08

### Added
- `wp-takeoff ai claude` command, replacing `ai toon`: `check`/`install`/`uninstall` roll out the global `~/.claude` config (`CLAUDE.md`, `labelvier/WORDPRESS.md`, `labelvier/ANGULAR.md`) from tpl templates alongside the toon hook.

### Changed
- `uninstall` now removes the config files together with the toon hook, after a confirmation prompt listing everything that will be deleted.

## [0.27.0] - 2026-09-04

### Added
- `wp-takeoff ai toon` command to install a Claude Code hook that pipes `basecamp` CLI output through the TOON formatter.

## [0.26.0] - 2026-08-18

### Added
- Add production deployment tracking with deploy live and deploy log (#4)
- Add cleanup subcommand

### Fixed
- Change 'bij' to 'by' to be in the same locale as the other comments
- Remove --yes flag from cleanup

## [0.25.0] - 2026-06-19

### Fixed
- Custom version argument ignored when no version file is found in wt release start

## [0.24.2] - 2026-06-19

### Fixed
- Issue where the wp cli wasnt found on the src server

## [0.24.1] - 2026-06-19

### Fixed
- Wrong ssh command in wt migrate

## [0.24.0] - 2026-06-16

### Added
- Add SSH alias management script

### Changed
- Allow any version for dev dependencies

### Fixed
- Better handling of release command (#3)

## [0.23.0] - 2026-05-20

### Added
- Add option for WooCommerce starter kit

## [0.22.2] - 2026-05-12

_Version bump only._

## [0.22.1] - 2026-05-06

### Fixed
- Update merge conflict message with push instruction

## [0.22.0] - 2026-05-05

### Added
- Add autocompletion setup for WordPress in Zed editor

### Changed
- Remove backticks from commit message

## [0.21.3] - 2026-05-04

### Fixed
- Return to original branch after staging deploy

## [0.21.2] - 2026-05-04

### Fixed
- Add flag to skip deploy-staging script check

## [0.21.1] - 2026-05-04

### Added
- Feature: Improved deploy staging command (#1)

## [0.21.0] - 2026-04-29

### Changed
- Merged in feature/github-update (pull request #3)

## [0.20.1] - 2026-02-20

### Added
- Add optional uploads folder migration or fallback

### Changed
- Changed repo to github

## [0.20.0] - 2026-01-13

### Added
- Skip files already in WebP format during conversion
- Add background mode for WebP conversion

### Changed
- Rename backup option and set default to no backup

### Fixed
- Improve branch checks and add error handling
- Make uploaded script executable with chmod +x

## [0.19.0] - 2025-12-23

### Added
- Add convert-to-webp image conversion command

## [0.18.0] - 2025-10-27

### Changed
- Merged in feature/vps-storage (pull request #1)

## [0.17.6] - 2025-07-22

### Changed
- Update deploy function description

### Fixed
- Add action-scheduler clean before running tasks

## [0.17.5] - 2025-07-09

### Fixed
- Improve project folder detection logic

## [0.17.4] - 2025-07-04

### Fixed
- Remove unnecessary PHP_BIN export in script

## [0.17.3] - 2025-06-27

### Fixed
- Rename cron script file and update instructions

## [0.17.2] - 2025-06-27

### Fixed
- Update PHP version to 8.2 in script

## [0.17.1] - 2025-05-20

### Changed
- Improve grep pattern for DEV_THEME_PATH
- Remove whitespace from master branch variable

## [0.17.0] - 2025-05-19

### Added
- Add checks for master and develop branches

## [0.16.0] - 2025-04-08

### Added
- Add SSH config host options for servers

## [0.15.0] - 2025-04-01

### Added
- Push to the current branch instead of master

### Changed
- Remove woocommerce installation prompt

## [0.14.3] - 2025-03-26

### Added
- Change commit message in release command to convential commits

## [0.14.2] - 2024-10-25

### Changed
- Make file path relative in release script

## [0.14.1] - 2024-10-16

### Fixed
- Fix syntax error in cron.sh script

## [0.14.0] - 2024-10-14

### Added
- Add check for empty WP_PATH in cron.sh
- Add cron job script and related deployment function

## [0.13.2] - 2024-09-24

### Fixed
- Fix typo in starterkit install function for adding WooCommerce

## [0.13.1] - 2024-09-23

### Changed
- Update deploy staging script to pull before merge

## [0.13.0] - 2024-07-19

### Changed
- Starterkit - new command update (updates dependencies and latest starter kit engine)

## [0.12.2] - 2024-04-17

### Changed
- Release - also search in style.css if style.scss is not present

## [0.12.1] - 2024-01-17

### Changed
- Remove debug exit-statement

## [0.12.0] - 2024-01-16

### Changed
- Core - colors in the CLI

## [0.11.3] - 2024-01-16

### Changed
- Migration - move wp command to a seperate variable

### Fixed
- Migrate - fix for checking display_errors = 0

## [0.11.2] - 2024-01-15

### Changed
- Migrate - bugfixes for checking for display_errors = 0

## [0.11.1] - 2023-10-23

### Changed
- Wt migrate - removed verbose output for scp
- Migration use --allow-root for wp commands

## [0.11.0] - 2023-10-04

### Added
- Added a README Added user reset after migrating local to staging

## [0.10.0] - 2023-09-28

### Added
- New command: wp-takeoff migrate staging

## [0.9.2] - 2023-09-28

### Changed
- Small htaccess and todo's for migrate

## [0.9.1] - 2023-09-18

### Changed
- Migrate - move save profile above generating ssh certificates

## [0.9.0] - 2023-09-12

### Changed
- Display_errors check fix
- Display errors = 0 (WiP)
- Multisite htaccess rewrites
- Migrate multisite htaccess rewrite (WiP)
- MIGRATION: delete wordpress-starter plugin from siteground after migration

### Fixed
- Fix debug check with display errors
- Fix sed for display_errors
- Typo fix to display_errors in wp-config

## [0.8.0] - 2023-08-21

### Added
- Feature: migration tool (migrate WordPress between 2 sites)

## [0.7.0] - 2023-06-02

### Added
- New command: wp-takeoff core generate (Generate a new command collection for wp-takeoff)

## [0.6.4] - 2023-05-12

### Fixed
- Fixed custom version release

## [0.6.3] - 2023-05-12

### Added
- Added help text to woocommerce import

## [0.6.2] - 2023-05-02

### Changed
- Show git commits after update

### Fixed
- Fix to add hardcoded version in release command, plus extra documentation

## [0.6.1] - 2023-04-25

### Changed
- Better merge-features

## [0.6.0] - 2023-04-25

### Changed
- Merge feature branches feature

## [0.5.1] - 2023-04-21

### Fixed
- Fix release cancel documentation

## [0.5.0] - 2023-04-19

### Changed
- Allow an alias to be used instead of the wp-takeoff command

## [0.4.1] - 2023-04-14

### Added
- Add checks for staging deploy to make sure the staging branch is pushed

### Changed
- Deploy - merge current branch always to staging when deploying

## [0.4.0] - 2023-03-31

### Changed
- Release: Cancel release and move commit message to release branch instead of develop

## [0.3.0] - 2023-03-29

### Added
- New deploy command which merges all feature branches in a staging branch and runs the npm run deploy-staging command after that

## [0.2.0] - 2023-03-15

### Added
- Add function `wp-takeoff starterkit fix-permissions` to fix permissions for docker container

### Changed
- Commit bump directly in seperate commit

## [0.1.1] - 2023-03-07

### Changed
- Better comments for starterkit install

## [0.1.0] - 2023-02-21

### Added
- Added support for semver release with or without additional parts (dash or space, like 1.0.0-rc1 or 1.0.0 (timestamp)

### Changed
- Release command

## [0.0.3] - 2023-02-17

### Changed
- Allow spaces in versions for release command

## [0.0.2] - 2023-02-13

### Fixed
- Fix sed for ubuntu (starterkit install)

## [0.0.1] - 2023-02-13

### Added
- Added better installation script for shell inclusion

### Changed
- Package.json support
- TODO's for Woocommerce
- Skip _flag_is_present return bool
- Ask for woocommerce support in starterkit install
- Better helpers for --flag checks
- Moved code to start function
- Version start checker
- Install function in core
- Better core update checker
- Ask for remote and don't rename folder is theme is called labelvier
- Refactor functions to include documentation, and every subfile also uses a main function now and a wrapper
- WiP subfiles with documentation
- Move update checker to seperate file
- Check for updates function
- Renamed to wp-takeoff-cli and added installer script and helper function for woocommerce scripts
- Initial commit
- First attempt for a WP Takeoff CLI (wp-pilot)

### Fixed
- Fixed woocommerce functions and helper
- Fix core updater
- Fix dynamic documentation for subfiles
- Fix rename in style.scss and _variables.scss
