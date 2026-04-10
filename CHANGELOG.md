# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `.dockerignore` to exclude unnecessary files from Docker build context
- `HEALTHCHECK` instruction to verify PHP-FPM socket availability
- Fallback salt key generation when WordPress API is unreachable
- `trap` cleanup for temporary files in entrypoint
- `docker-compose.yml` with full WordPress stack (nginx, MariaDB, Redis)
- `CONTRIBUTING.md` with development and PR guidelines
- CI lint job with ShellCheck and Hadolint
- CI smoke tests to verify PHP extensions and WP-CLI

### Fixed

- Default `PHP_VERSION` now matches the `latest` tag (8.5 instead of 8.3)
- Plugin operation failures now logged instead of silently ignored
- `find -exec chmod` now uses batched mode (`+`) instead of per-file (`\;`)
- File permissions only set on first install, not every restart

### Changed

- Improved error visibility with warning messages on plugin install failures
