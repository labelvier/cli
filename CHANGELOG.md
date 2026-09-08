# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.28.0] - 2026-09-08

### Added
- `wp-takeoff ai claude` command, replacing `ai toon`: `check`/`install`/`uninstall` roll out the global `~/.claude` config (`CLAUDE.md`, `labelvier/WORDPRESS.md`, `labelvier/ANGULAR.md`) from tpl templates alongside the toon hook.

### Changed
- `uninstall` now removes the config files together with the toon hook, after a confirmation prompt listing everything that will be deleted.

## [0.27.0] - 2026-09-04

### Added
- `wp-takeoff ai toon` command to install a Claude Code hook that pipes `basecamp` CLI output through the TOON formatter.
