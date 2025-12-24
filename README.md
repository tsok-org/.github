# tsok-org/.github

Organization-wide reusable GitHub Actions workflows and composite actions for tsok-org repositories.

## 📋 Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Composite Actions](#composite-actions)
  - [environment-setup](#environment-setup)
  - [setup-node](#setup-node)
  - [setup-terraform](#setup-terraform)
  - [setup-docker](#setup-docker)
- [Reusable Workflows](#reusable-workflows)
  - [nx-ci.yml](#nx-ciyml)
  - [nx-cd.yml](#nx-cdyml)
  - [nx-migrate.yml](#nx-migrateyml)
  - [dependabot-auto-merge.yml](#dependabot-auto-mergeyml)
  - [gitleaks.yml](#gitleaksyml)
  - [pr-validate.yml](#pr-validateyml)
- [Configuration](#configuration)
  - [.environment.yml](#environmentyml)
  - [Authentication](#authentication)

---

## Overview

This repository provides a centralized collection of:

- **Composite Actions** - Reusable action building blocks for common setup tasks
- **Reusable Workflows** - Complete CI/CD workflows that can be called from any repository

### Key Features

- 🔧 **Declarative Configuration** - Define your environment in `.environment.yml`
- 🔐 **GitHub App Authentication** - Bypass branch protection with short-lived tokens
- 📦 **Package Manager Auto-Detection** - Works with npm, pnpm, yarn, and bun
- ☁️ **Nx Cloud Integration** - Distributed caching and task execution
- 🐳 **Docker Multi-Platform** - Build for multiple architectures
- 🔍 **Security Scanning** - Built-in secret detection with Gitleaks

---

## Quick Start

### 1. Create `.environment.yml` in your repository

```yaml
# .environment.yml
node:
  version: .node-version  # or "20", "lts/*"
  install: true
  cache: true

docker:
  buildx: true
  platforms:
    - linux/amd64
    - linux/arm64
```

### 2. Create CI workflow

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
    branches: [main, develop]

permissions:
  contents: read
  checks: write

jobs:
  ci:
    uses: tsok-org/.github/.github/workflows/nx-ci.yml@main
    with:
      lint: true
      test: true
      build: true
    secrets:
      nx_cloud_access_token: ${{ secrets.NX_CLOUD_ACCESS_TOKEN }}
```

### 3. Create CD workflow

```yaml
# .github/workflows/cd.yml
name: Release

on:
  push:
    branches: [main]

permissions:
  contents: write
  packages: write

jobs:
  release:
    uses: tsok-org/.github/.github/workflows/nx-cd.yml@main
    with:
      publish_npm: true
      create_release: true
    secrets:
      npm_token: ${{ secrets.NPM_TOKEN }}
      github_app_id: ${{ vars.GITHUB_APP_ID }}
      github_app_private_key: ${{ secrets.GITHUB_APP_PRIVATE_KEY }}
```

---

## Composite Actions

### environment-setup

Universal environment setup from `.environment.yml` configuration.

```yaml
- name: Setup Environment
  uses: tsok-org/.github/actions/environment-setup@main
  with:
    github_app_id: ${{ vars.APP_ID }}
    github_app_private_key: ${{ secrets.APP_PRIVATE_KEY }}
```

#### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `config` | Path to environment configuration file | `.environment.yml` |
| `working_directory` | Working directory for setup | `.` |
| `github_app_id` | GitHub App ID for authentication | - |
| `github_app_private_key` | GitHub App private key (PEM) | - |
| `github_token` | Fallback GitHub token | `${{ github.token }}` |
| `skip` | Components to skip (comma-separated) | - |
| `only` | Only setup these components | - |

#### Supported Components

- **node** - Node.js with package manager auto-detection
- **python** - Python with pip/poetry/uv support
- **terraform** - Terraform CLI with optional Terragrunt and TFLint
- **docker** - Docker Buildx with registry authentication
- **services** - Container services (Postgres, Redis, etc.)

---

### setup-node

Intelligent Node.js setup with automatic package manager detection.

```yaml
- name: Setup Node.js
  uses: tsok-org/.github/actions/setup-node@main
  with:
    node_version: "20"
    install_dependencies: true
    frozen_lockfile: true
```

#### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `node_version` | Node.js version | - |
| `node_version_file` | File to read version from | `.node-version` |
| `install_dependencies` | Install deps after setup | `true` |
| `frozen_lockfile` | Use frozen lockfile mode | `true` |
| `working_directory` | Working directory | `.` |

#### Outputs

| Output | Description |
|--------|-------------|
| `package_manager` | Detected package manager (npm/pnpm/yarn/bun) |
| `node_version` | Installed Node.js version |
| `exec` | Command to execute packages (e.g., `pnpm exec`) |
| `dlx` | Command to run packages (e.g., `pnpm dlx`) |

#### Package Manager Detection

| Lockfile | Package Manager | Install Command |
|----------|-----------------|-----------------|
| `pnpm-lock.yaml` | pnpm | `pnpm install --frozen-lockfile` |
| `yarn.lock` | yarn | `yarn install --frozen-lockfile` |
| `bun.lockb` | bun | `bun install --frozen-lockfile` |
| `package-lock.json` | npm | `npm ci` |

---

### setup-terraform

Setup Terraform CLI with optional Terragrunt and TFLint.

```yaml
- name: Setup Terraform
  uses: tsok-org/.github/actions/setup-terraform@main
  with:
    terraform_version: "1.12.2"
    terragrunt_version: "0.68.0"
    tflint_version: "0.50.0"
```

#### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `terraform_version` | Terraform version | `latest` |
| `terraform_wrapper` | Install wrapper script | `true` |
| `terragrunt_version` | Terragrunt version (empty to skip) | - |
| `tflint_version` | TFLint version (empty to skip) | - |
| `cli_config_credentials_hostname` | TFC/TFE hostname | - |
| `cli_config_credentials_token` | TFC/TFE token | - |

---

### setup-docker

Setup Docker with Buildx, QEMU, and registry authentication.

```yaml
- name: Setup Docker
  uses: tsok-org/.github/actions/setup-docker@main
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
    setup_qemu: true
    platforms: linux/amd64,linux/arm64
```

#### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `registry` | Container registry URL | - |
| `username` | Registry username | - |
| `password` | Registry password/token | - |
| `setup_buildx` | Setup Docker Buildx | `true` |
| `setup_qemu` | Setup QEMU for multi-arch | `false` |
| `platforms` | QEMU platforms | `linux/amd64,linux/arm64` |
| `driver` | Buildx driver | `docker-container` |

---

## Reusable Workflows

### nx-ci.yml

Continuous Integration workflow for Nx monorepos.

```yaml
jobs:
  ci:
    uses: tsok-org/.github/.github/workflows/nx-ci.yml@main
    with:
      lint: true
      test: true
      build: true
      e2e: false
      parallel: 3
      affected_only: true
      coverage: true
      coverage_reporter: codecov
    secrets:
      nx_cloud_access_token: ${{ secrets.NX_CLOUD_ACCESS_TOKEN }}
      codecov_token: ${{ secrets.CODECOV_TOKEN }}
```

#### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `environment_config` | Path to .environment.yml | `.environment.yml` |
| `environment_skip` | Components to skip | `docker,terraform,services` |
| `environment_only` | Only setup these components | - |
| `lint` | Run lint task | `true` |
| `test` | Run test task | `true` |
| `build` | Run build task | `true` |
| `e2e` | Run e2e task | `false` |
| `parallel` | Parallel task count | `3` |
| `affected_only` | Only affected projects | `true` |
| `exclude_projects` | Projects to exclude | - |
| `coverage` | Enable coverage | `false` |
| `coverage_reporter` | Reporter (codecov/coveralls) | `none` |
| `distribute_on` | Nx Cloud distribution | - |
| `runs_on` | Runner label | `ubuntu-latest` |
| `timeout_minutes` | Job timeout | `30` |

#### Outputs

| Output | Description |
|--------|-------------|
| `lint_result` | Lint task result |
| `test_result` | Test task result |
| `build_result` | Build task result |
| `affected_projects` | List of affected projects |

---

### nx-cd.yml

Continuous Delivery workflow with versioning and publishing.

```yaml
jobs:
  release:
    uses: tsok-org/.github/.github/workflows/nx-cd.yml@main
    with:
      preid: beta           # alpha, beta, rc, or empty for stable
      dist_tag: beta        # npm dist-tag
      publish_npm: true
      publish_docker: true
      docker_registry: ghcr.io
      create_release: true
      github_prerelease: true
    secrets:
      npm_token: ${{ secrets.NPM_TOKEN }}
      github_app_id: ${{ vars.GITHUB_APP_ID }}
      github_app_private_key: ${{ secrets.GITHUB_APP_PRIVATE_KEY }}
```

#### Versioning Strategy

| Branch | preid | npm Tag | Example |
|--------|-------|---------|---------|
| develop | alpha | alpha | 1.2.3-alpha.0 |
| next | beta | beta | 1.2.3-beta.0 |
| main | rc | next | 1.2.3-rc.0 |
| manual | - | latest | 1.2.3 |

#### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `environment_config` | Path to .environment.yml | `.environment.yml` |
| `environment_skip` | Components to skip | `terraform,services` |
| `preid` | Pre-release identifier | - |
| `dry_run` | Dry run mode | `false` |
| `specifier` | Version specifier | - |
| `publish_npm` | Publish to npm | `false` |
| `dist_tag` | npm dist-tag | `latest` |
| `publish_docker` | Build/push Docker images | `false` |
| `docker_registry` | Docker registry | `ghcr.io` |
| `docker_platforms` | Build platforms | `linux/amd64` |
| `create_release` | Create GitHub release | `true` |
| `github_prerelease` | Mark as pre-release | `false` |

#### Outputs

| Output | Description |
|--------|-------------|
| `version` | Released version |
| `tag` | Git tag |
| `published_packages` | JSON array of packages |

---

### nx-migrate.yml

Automated Nx workspace migration with PR creation.

```yaml
name: Nx Update
on:
  schedule:
    - cron: "0 6 * * *"  # Daily at 6 AM UTC
  workflow_dispatch:

jobs:
  migrate:
    uses: tsok-org/.github/.github/workflows/nx-migrate.yml@main
    with:
      channel: stable       # stable, rc, beta, canary
      major_version: "22"   # Lock to major version
      pr_auto_merge: true
    secrets:
      github_app_id: ${{ vars.GITHUB_APP_ID }}
      github_app_private_key: ${{ secrets.GITHUB_APP_PRIVATE_KEY }}
```

#### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `version` | Explicit Nx version | - |
| `channel` | Release channel | `stable` |
| `major_version` | Lock to major version | - |
| `minor_version` | Lock to minor version | - |
| `branch_name_template` | Branch name template | `update-nx-{version}` |
| `pr_title_template` | PR title template | `build: 📦 update Nx to {version}` |
| `pr_auto_merge` | Enable auto-merge | `true` |
| `dry_run` | Preview mode | `false` |
| `close_existing_prs` | Close old migration PRs | `true` |

#### Outputs

| Output | Description |
|--------|-------------|
| `migration_version` | Target Nx version |
| `current_version` | Current Nx version |
| `pr_number` | Created PR number |
| `pr_url` | Created PR URL |
| `package_manager` | Detected package manager |

---

### dependabot-auto-merge.yml

Auto-merge Dependabot PRs by update level.

```yaml
name: Dependabot Auto-Merge
on:
  pull_request:

permissions:
  contents: write
  pull-requests: write

jobs:
  auto-merge:
    uses: tsok-org/.github/.github/workflows/dependabot-auto-merge.yml@main
    with:
      merge_level: minor      # patch, minor, major
      merge_method: squash
      ecosystems: npm,docker  # Optional filter
    secrets:
      github_token: ${{ secrets.GITHUB_TOKEN }}
```

#### Merge Levels

| Level | Auto-merges |
|-------|-------------|
| `patch` | Patch updates only (1.0.0 → 1.0.1) |
| `minor` | Patch + minor (1.0.0 → 1.1.0) |
| `major` | All updates (1.0.0 → 2.0.0) |

#### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `merge_level` | Maximum update level | `patch` |
| `merge_method` | Merge method (squash/merge/rebase) | `squash` |
| `ecosystems` | Filter by ecosystems | - |
| `excluded_packages` | Packages to never merge | - |
| `approve_only` | Only approve, don't merge | `false` |

---

### gitleaks.yml

Secret scanning with Gitleaks.

```yaml
name: Secret Scan
on:
  pull_request:
  push:
    branches: [main]

jobs:
  scan:
    uses: tsok-org/.github/.github/workflows/gitleaks.yml@main
    with:
      fail_on_leak: true
      upload_sarif: true  # Requires GitHub Advanced Security
    secrets:
      gitleaks_license: ${{ secrets.GITLEAKS_LICENSE }}
```

#### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `config_path` | Custom Gitleaks config | - |
| `scan_depth` | Commits to scan (0 = all) | `0` |
| `fail_on_leak` | Fail if secrets found | `true` |
| `upload_sarif` | Upload to Security tab | `false` |

---

### pr-validate.yml

PR title validation for conventional commits.

```yaml
name: PR Validation
on:
  pull_request:
    types: [opened, synchronize, reopened, edited]

jobs:
  validate:
    uses: tsok-org/.github/.github/workflows/pr-validate.yml@main
    with:
      require_scope: false
      auto_label: true
```

#### Conventional Commit Types

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation |
| `style` | Code style |
| `refactor` | Refactoring |
| `perf` | Performance |
| `test` | Tests |
| `build` | Build system |
| `ci` | CI/CD |
| `chore` | Maintenance |
| `revert` | Revert |
| `release` | Release |

#### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `validate_title` | Validate PR title | `true` |
| `require_scope` | Require scope in title | `false` |
| `wip_allowed` | Allow WIP: prefix | `true` |
| `custom_types` | Additional types | - |
| `header_max_length` | Max title length | `100` |
| `auto_label` | Add labels by type | `false` |

---

## Configuration

### .environment.yml

Declarative environment configuration file.

```yaml
# .environment.yml

# Node.js configuration
node:
  version: .node-version    # or "20", "lts/*", "20.11.0"
  package_manager: auto     # auto, npm, pnpm, yarn, bun
  install: true
  cache: true

# Python configuration
python:
  version: "3.12"
  package_manager: pip      # pip, poetry, uv

# Terraform configuration
terraform:
  version: "1.12.2"         # or "latest"

terragrunt:
  version: "0.68.0"

tflint: true                # Install TFLint

# Docker configuration
docker:
  buildx: true
  platforms:
    - linux/amd64
    - linux/arm64

# Service containers for tests
services:
  postgres:
    image: postgres:16-alpine
    port: 5432
  redis:
    image: redis:7-alpine
    port: 6379
```

### Authentication

#### GitHub App (Recommended)

GitHub Apps provide short-lived tokens that can bypass branch protection.

1. Create a GitHub App with:
   - **Repository permissions**: Contents (read/write), Pull requests (read/write)
   - **Organization permissions**: Members (read) if needed

2. Add to repository:
   - `vars.GITHUB_APP_ID` - App ID
   - `secrets.GITHUB_APP_PRIVATE_KEY` - Private key (PEM)

#### Token Authentication

Use for simpler setups without branch protection bypass:

```yaml
secrets:
  github_token: ${{ secrets.GITHUB_TOKEN }}
```

#### Credential Environment Variables

Service credentials should be passed as environment variables:

| Variable | Description |
|----------|-------------|
| `DOCKER_REGISTRY` | Registry URL |
| `DOCKER_USERNAME` | Registry username |
| `DOCKER_PASSWORD` | Registry password |
| `POSTGRES_USER` | PostgreSQL user |
| `POSTGRES_PASSWORD` | PostgreSQL password |
| `POSTGRES_DB` | Database name |
| `REDIS_PASSWORD` | Redis password |
| `NPM_TOKEN` | npm auth token |

---

## License

MIT License - see [LICENSE](LICENSE) for details.
