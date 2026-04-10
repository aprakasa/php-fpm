# Contributing

## Development

### Prerequisites

- Docker with Buildx support
- Git

### Local Build

```bash
docker build --build-arg PHP_VERSION=8.5 -t php-fpm:local .
```

### Testing

```bash
# Run smoke test
docker run --rm php-fpm:local php -m
docker run --rm php-fpm:local which wp

# Run with docker compose
cp .env.example .env
# Edit .env with your passwords
docker compose up -d
```

### Linting

- **ShellCheck** for `entrypoint.sh`
- **Hadolint** for `Dockerfile`

Both run automatically in CI. Install locally:

```bash
# macOS
brew install shellcheck hadolint

# Linux
apt install shellcheck
pip install hadolint
```

## Pull Requests

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Ensure CI passes (lint + build + smoke test)
5. Open a pull request

## Commit Convention

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description

feat(docker): add new PHP extension
fix(entrypoint): handle missing database gracefully
ci: update GitHub Actions versions
docs: update environment variable table
refactor(dockerfile): optimize layer caching
```

**Types:** `feat`, `fix`, `docs`, `refactor`, `ci`, `build`, `chore`

**Scopes:** `docker`, `entrypoint`, `ci`, `config`, or omit for general changes.

## Release

Tags matching `v*` trigger CI builds that produce versioned images:

```
v1.2.0 -> ghcr.io/aprakasa/php-fpm:v1.2.0-8.5
       -> ghcr.io/aprakasa/php-fpm:v1.2-8.5
```

Update `CHANGELOG.md` before tagging a release.
