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

# Cancel superseded runs on the same PR / branch so a fast follow-up push
# doesn't double up on runners. Set at the *caller* level — reusable workflows
# run as part of the caller's run, so this is the authoritative place to
# control cancellation.
concurrency:
  group: ci-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

jobs:
  ci:
    uses: tsok-org/.github/.github/workflows/nx-ci.yml@v1
    with:
      lint: true
      test: true
      build: true
    secrets:
      nx_cloud_access_token: ${{ secrets.NX_CLOUD_ACCESS_TOKEN }}
```

> **Versioning.** Prefer pinning reusable workflows to a released tag
> (`@v1`, `@v1.2.3`) rather than `@main`. `@main` tracks the tip of this
> repo and an accidental breakage propagates instantly to all consumers.
> Composite actions inside reusable workflows (e.g. `environment-setup`)
> still use floating refs today — that is an explicit trade-off so the
> `v1` contract protects the *outer* workflow surface, which is what
> consumers actually depend on.

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
    uses: tsok-org/.github/.github/workflows/nx-cd.yml@v1
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

Universal environment setup driven by `.environment.yml`. The action
validates the config against [`schema.json`][env-schema] (draft-07), parses
it with [`parse-config.sh`][env-parser], then conditionally runs the
per-component setup steps.

For the full `.environment.yml` reference, see
[Configuration › `.environment.yml`](#environmentyml).

```yaml
- name: Setup Environment
  uses: tsok-org/.github/actions/environment-setup@v1
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

`skip` / `only` accept: `node`, `python`, `rust`, `go`, `c`, `terraform`,
`docker`, `services`, `system_packages`.

#### Supported Components

- **node** — Node.js via `setup-node` with pnpm/npm/yarn detection
- **python** — Python + pip / poetry / uv
- **rust** — cache, diagnostics, coverage, build knobs (toolchain comes from `rust-toolchain.toml`)
- **go** — Go via `actions/setup-go@v5`
- **c** — gcc/clang + optional cmake/pkg-config (Linux only)
- **terraform** — Terraform CLI with optional Terragrunt and TFLint
- **docker** — Docker Buildx with registry authentication
- **services** — Container services (Postgres, Redis, NATS, MySQL, Mongo, …)
- **system_packages** — Arbitrary apt packages (Linux only)

[env-schema]: actions/environment-setup/schema.json
[env-parser]: actions/environment-setup/scripts/parse-config.sh

---

### setup-node

Intelligent Node.js setup with automatic package manager detection.

```yaml
- name: Setup Node.js
  uses: tsok-org/.github/actions/setup-node@v1
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
  uses: tsok-org/.github/actions/setup-terraform@v1
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
  uses: tsok-org/.github/actions/setup-docker@v1
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
    uses: tsok-org/.github/.github/workflows/nx-ci.yml@v1
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
| `working_directory` | Working directory (nested workspaces) | `.` |
| `lint` | Run lint task | `true` |
| `test` | Run test task | `true` |
| `build` | Run build task | `true` |
| `e2e` | Run e2e task | `false` |
| `custom_tasks` | Extra comma-separated Nx tasks (e.g. `typecheck,format:check`) | - |
| `parallel` | Parallel task count | `3` |
| `affected_only` | Only affected projects | `true` |
| `exclude_projects` | Projects to exclude (glob OK) | - |
| `coverage` | Enable coverage | `false` |
| `coverage_reporter` | Reporter (codecov/coveralls/none) | `none` |
| `distribute_on` | Nx Cloud distribution (e.g. `3 linux-medium-js`) | - |
| `stop_agents_after` | Task to stop distributed agents after | `build` |
| `nx_cloud_enabled` | Enable Nx Cloud remote cache | `true` |
| `ref` | Git ref to checkout (branch/tag/SHA). Empty = triggering ref. | - |
| `runs_on` | Runner label | `ubuntu-latest` |
| `timeout_minutes` | Job timeout | `30` |
| `verbose` | Verbose diagnostics (Nx + cargo + backtraces) | `false` |
| `github_app_id` | GitHub App ID (optional) | - |

The `ref` input is useful for scheduled/`workflow_dispatch` callers that
need to test a specific branch rather than the default branch the cron
fires from; it mirrors the `ref` input on `nx-cd.yml`.

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
    uses: tsok-org/.github/.github/workflows/nx-cd.yml@v1
    with:
      preid: beta           # alpha, beta, rc, or empty for stable
      dist_tag: beta        # npm dist-tag
      publish_docker: true
      docker_registry: ghcr.io
      docker_platforms: linux/amd64,linux/arm64
      github_prerelease: true
      github_app_id: ${{ vars.GITHUB_APP_ID }}
    secrets:
      npm_token: ${{ secrets.NPM_TOKEN }}
      github_app_private_key: ${{ secrets.GITHUB_APP_PRIVATE_KEY }}
      docker_username: ${{ github.actor }}
      docker_password: ${{ secrets.GITHUB_TOKEN }}
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
| `environment_only` | Only setup these components | - |
| `working_directory` | Working directory for the release | `.` |
| `preid` | Pre-release identifier (alpha/beta/rc/…) | - |
| `dist_tag` | npm dist-tag | `latest` |
| `github_prerelease` | Mark GitHub release as pre-release | `false` |
| `publish_docker` | Build/push Docker images | `false` |
| `docker_registry` | Docker registry | `ghcr.io` |
| `docker_platforms` | Build platforms (comma-separated) | `linux/amd64` |
| `dry_run` | Dry run mode | `false` |
| `first_release` | Skip changelog comparison on first release | `false` |
| `verbose` | Verbose `nx release` output | `false` |
| `ref` | Git ref to checkout (empty = triggering ref) | - |
| `git_user_name` | Commit author name (fallback when no App) | `github-actions[bot]` |
| `git_user_email` | Commit author email (fallback when no App) | `github-actions[bot]@users.noreply.github.com` |
| `runs_on` | Runner label | `ubuntu-latest` |
| `timeout_minutes` | Job timeout | `30` |
| `github_app_id` | GitHub App ID (input, not secret — App ID is not sensitive) | - |

#### Secrets

| Secret | Description |
|--------|-------------|
| `github_app_private_key` | GitHub App private key (PEM) |
| `npm_token` | npm auth token (for `nx release publish`) |
| `docker_username` | Docker registry username |
| `docker_password` | Docker registry password/token |
| `nx_cloud_access_token` | Nx Cloud remote cache |

#### Outputs

| Output | Description |
|--------|-------------|
| `released` | Whether any projects were released |
| `version` | The version that was released |

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
    uses: tsok-org/.github/.github/workflows/nx-migrate.yml@v1
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
    uses: tsok-org/.github/.github/workflows/dependabot-auto-merge.yml@v1
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
    uses: tsok-org/.github/.github/workflows/gitleaks.yml@v1
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
    uses: tsok-org/.github/.github/workflows/pr-validate.yml@v1
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

Declarative environment configuration consumed by
[`actions/environment-setup`](#environment-setup). The authoritative type
spec is [`actions/environment-setup/schema.json`][env-schema] (draft-07);
this section is the field-by-field reference.

#### Polyglot by design

`.environment.yml` is intended to grow. Today it has first-class support
for **Rust**, **Node/TypeScript**, **Python**, **Go**, and **C/C++**, plus
**Terraform**, **Docker**, service containers, and ad-hoc apt packages via
`system_packages`. Adding a new language means extending
[`schema.json`][env-schema] + [`parse-config.sh`][env-parser] +
[`action.yml`][env-action] — the caller's `uses: …/environment-setup@v1`
shape stays the same.

[env-action]: actions/environment-setup/action.yml

#### Top-level fields

| Field | Type | Purpose |
|---|---|---|
| `version` | string, **required** | Schema version. Only `"1"` today. |
| `node` | bool \| `{ version, package_manager, install, cache, frozen_lockfile }` | Node.js + pnpm/npm/yarn |
| `python` | bool \| string \| `{ version, package_manager }` | Python + pip/poetry/uv |
| `rust` | `{ cache, diagnostics, coverage, build_jobs, linker }` | Rust cache + CI knobs (toolchain comes from `rust-toolchain.toml`) |
| `go` | bool \| string \| `{ version, version_file, cache, modules }` | Go toolchain via `actions/setup-go` |
| `c` | `{ toolchain, cmake, pkg_config, packages[] }` | C/C++ toolchain (gcc \| clang) + apt packages |
| `terraform` | bool \| string \| `{ version }` | Terraform CLI |
| `terragrunt` | bool \| string \| `{ version }` | Terragrunt alongside Terraform |
| `tflint` | bool \| `{ version }` | TFLint |
| `docker` | bool \| `{ buildx, platforms, registry }` | Docker + buildx |
| `services` | object | Service containers (postgres, redis, …) |
| `system_packages` | string[] | Additional apt packages on Linux |

Every field is optional except `version`.

#### Minimal example

```yaml
# .environment.yml
version: "1"

node:
  version: .node-version   # or "20", "lts/*", "20.11.0"
  package_manager: pnpm
  install: true
  cache: true
  frozen_lockfile: true
```

#### `version`

```yaml
version: "1"
```

Required. Pinned to `"1"` today; bumped on breaking schema changes.

#### `node`

```yaml
node:
  version: .node-version   # explicit ("20") or file reference (".node-version")
  package_manager: pnpm    # pnpm | npm | yarn
  install: true            # run pkg-mgr install step; default true
  cache: true              # built-in setup-node cache; default true
  frozen_lockfile: true    # fail on lockfile drift; default true
```

Shorthand: `node: true` enables with defaults.

#### `python`

```yaml
python:
  version: "3.12"
  package_manager: uv      # pip | poetry | uv
```

Shorthands: `python: true` (→ 3.12 + pip), `python: "3.11"`.

#### `rust`

```yaml
rust:
  cache: true              # Swatinem/rust-cache for target/
  diagnostics: true        # rustup show, cargo env, connectivity smoke test
  coverage: true           # installs cargo-llvm-cov (Linux only)
  build_jobs: 1            # pin CARGO_BUILD_JOBS (serial link for small runners)
  linker: mold             # lld | mold — alternative linkers
```

Toolchain selection lives in `rust-toolchain.toml` at the repo root;
rustup auto-installs on first `cargo` invocation. This block only covers
caching, diagnostics, and build knobs.

When `rust` is enabled, the action also validates `CARGO_TERM_VERBOSE`,
`CARGO_TERM_COLOR`, and `RUST_BACKTRACE` env vars emitted by the calling
workflow — empty strings fail fast instead of confusing cargo downstream.

#### `go`

```yaml
go:
  version: "1.22"          # or "1.22.3"
  version_file: go.mod     # or ".go-version"
  cache: true              # module + build cache; default true
  modules: true            # GO111MODULE; default true
```

Shorthands: `go: true` (latest), `go: "1.22"`, `go: { version_file: go.mod }`.
Installed via `actions/setup-go@v5`.

#### `c`

```yaml
c:
  toolchain: clang         # gcc | clang
  cmake: true
  pkg_config: true
  packages:                # additive to top-level system_packages
    - libssl-dev
    - libcurl4-openssl-dev
```

Linux only. `gcc` installs `build-essential`; `clang` installs `clang`
and `lld`. Use this (rather than raw `system_packages`) to express
**what toolchain you want** — the action derives the apt package set.

#### `terraform` / `terragrunt` / `tflint`

```yaml
terraform: "1.12.2"        # or true (latest), or { version: "..." }
terragrunt: "0.68.0"       # only installed when terraform is enabled
tflint: true               # or { version: "0.50.0" }
```

#### `docker`

```yaml
docker:
  buildx: true
  platforms:
    - linux/amd64
    - linux/arm64
  registry: ghcr.io        # overridden by DOCKER_REGISTRY env if set
```

Credentials come from the calling workflow's env block
(`DOCKER_USERNAME`, `DOCKER_PASSWORD`), not the config file.

#### `services`

```yaml
services:
  postgres:
    image: postgres:16-alpine   # optional — sensible default per service name
    port: 5432
    env:
      POSTGRES_USER: test
  redis:
    image: redis:7-alpine
    port: 6379
```

Keys are user-chosen names. Auth env (`POSTGRES_USER`, `POSTGRES_PASSWORD`,
`POSTGRES_DB`, `REDIS_PASSWORD`, `MYSQL_*`) comes from the calling
workflow's env and overrides values in the config.

Recognised service defaults: `postgres`, `redis`, `nats`, `mysql`, `mongo`.
Unknown names default to `<name>:latest`.

#### `system_packages`

```yaml
system_packages:
  - libssl-dev
  - pkg-config
```

Installed via `apt-get install` on Linux runners; warned-and-skipped on
macOS/Windows. Typical use: C/C++ headers for Rust `*-sys` crates. For
structured intent (toolchain + cmake/pkg-config), prefer `c:`.

#### Schema validation

`.environment.yml` is validated against
[`schema.json`][env-schema] (JSON Schema draft-07) by
[`check-jsonschema`](https://github.com/python-jsonschema/check-jsonschema)
on every run, **before** the parser runs. Misconfigured files fail fast
with a field-level error rather than mysterious parser drift.

On failure the step surfaces:

```
::error::.environment.yml failed schema validation.
─── .environment.yml ─────────────────────────────────────
  version: "1"
  rust:
    linker: gold        # <-- invalid: enum [lld, mold]
─── schema: .../schema.json ──────────────────────────────
  (see errors above for the specific field)
```

No config file? The step exits cleanly — the parser has its own default
path and a repo without `.environment.yml` is a valid no-op.

For the authoritative type spec, including every field's type,
constraints, and description, read [`schema.json`][env-schema] directly.

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
