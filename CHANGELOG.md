# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-09

### Added
- Moved to a new public repository, `labelvier/cli`, continuing the full history of the old `WP-Takeoff-CLI` repo.
- `labelvier` is the new canonical command name, with `l4` as a shorthand alias. `wp-takeoff` still works (it's now a symlink to the same script) but prints a deprecation notice pointing at `labelvier`/`l4`.
- `scripts/install.sh` — a non-interactive curl-installable script (`curl -fsSL .../install.sh | bash`) that clones the CLI to `~/.labelvier` and adds it to your `$PATH`.

### Changed
- `core install`/`core alias` now install to `~/.labelvier` and alias to `labelvier` instead of `~/.wp-takeoff`/`wp-takeoff`.
- README rewritten for the new repo, command names and install method.

## [0.28.0] - 2026-09-08

### Added
- `wp-takeoff ai claude` command, replacing `ai toon`: `check`/`install`/`uninstall` roll out the global `~/.claude` config (`CLAUDE.md`, `labelvier/WORDPRESS.md`, `labelvier/ANGULAR.md`) from tpl templates alongside the toon hook.

### Changed
- `uninstall` now removes the config files together with the toon hook, after a confirmation prompt listing everything that will be deleted.

## [0.27.0] - 2026-09-04

### Added
- `wp-takeoff ai toon` command to install a Claude Code hook that pipes `basecamp` CLI output through the TOON formatter.
