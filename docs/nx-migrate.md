# NX Workspace Migration Workflow

> **Automated Nx dependency updates with intelligent version selection and zero-configuration pull request creation.**

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Setup Guide](#setup-guide)
- [Configuration Reference](#configuration-reference)
- [Version Selection Strategies](#version-selection-strategies)
- [Usage Examples](#usage-examples)
- [Customization Guide](#customization-guide)
- [Safety & Validation](#safety--validation)
- [Troubleshooting](#troubleshooting)
- [Production Readiness](#production-readiness)

---

## Overview

The **NX Migration Workflow** (`nx-migrate.yml`) is a production-ready reusable GitHub Actions workflow that automates Nx workspace dependency updates. It intelligently selects versions, runs migrations, and creates pull requests with comprehensive change summaries.

### What It Does

1. ✅ Detects if your Nx workspace needs updates
2. 🔄 Runs `nx migrate` to update all `@nx/*` packages
3. 📦 Installs dependencies and applies automated migrations
4. 🚀 Creates a pull request with detailed change information
5. 🤖 Optionally enables auto-merge (with branch protection)
6. 🧹 Handles existing outdated PRs (closes and replaces)

### Key Features

- **Flexible Version Selection**: Explicit versions, channel-based (stable/rc/beta), or major/minor targeting
- **Dual Authentication**: GitHub App (recommended) or pre-generated tokens
- **Smart PR Management**: Closes outdated PRs when newer versions are available
- **Safety First**: Input validation, version checks, prevents downgrades
- **Production-Ready**: Comprehensive error handling, detailed logging, staged rollout tested

### Architecture

```
┌─────────────────┐
│  Caller Workflow │  (e.g., nx.yml)
│  (Your Repo)     │
└────────┬─────────┘
         │ calls
         ▼
┌─────────────────────────────────────────┐
│  nx-migrate.yml (Reusable Workflow)     │
│  ┌───────────────────────────────────┐  │
│  │ 1. Authenticate (App or Token)    │  │
│  │ 2. Validate Inputs                │  │
│  │ 3. Check Current vs Latest        │  │
│  │ 4. Handle Existing PRs            │  │
│  │ 5. Run nx migrate <version>       │  │
│  │ 6. Apply migrations               │  │
│  │ 7. Create/Update PR               │  │
│  │ 8. Enable auto-merge (optional)   │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

---

## Quick Start

### Prerequisites

- Nx workspace with `@nx/workspace` or `@nx/devkit` in `package.json`
- GitHub repository with Actions enabled
- **One of the following for authentication:**
  - GitHub App (recommended) with repo permissions
  - Personal Access Token (PAT) or `GITHUB_TOKEN`

### Minimal Setup

**Step 1**: Create `.github/workflows/nx-update.yml` in your repository:

```yaml
name: NX Auto-Update

on:
  workflow_dispatch:  # Manual trigger
  schedule:
    - cron: "0 6 * * *"  # Daily at 6 AM UTC

permissions:
  contents: write
  pull-requests: write

jobs:
  migrate:
    uses: tsok-org/.github/.github/workflows/nx-migrate.yml@main
    with:
      base_branch: main
      github_app_id: ${{ vars.GITHUB_APP_ID }}
    secrets:
      github_app_private_key: ${{ secrets.GITHUB_APP_PRIVATE_KEY }}
```

**Step 2**: Configure authentication (see [Setup Guide](#setup-guide))

**Step 3**: Run the workflow manually or wait for scheduled execution

---

## Setup Guide

### Authentication Methods

The workflow supports **two authentication methods** with different trade-offs:

| Method | Pros | Cons | Use Case |
|--------|------|------|----------|
| **GitHub App** | ✅ Short-lived tokens (1h)<br>✅ Can bypass branch protection<br>✅ Better audit trail<br>✅ Auto-merge friendly | ⚠️ Requires app creation | Production deployments, organizations |
| **Token** | ✅ No setup required (GITHUB_TOKEN)<br>✅ Simple configuration | ⚠️ Cannot bypass protection<br>⚠️ Auto-merge limited | Simple repos, testing |

### GitHub App Setup (Recommended)

#### Step 1: Create GitHub App

1. Navigate to **GitHub Settings** → **Developer settings** → **GitHub Apps** → **New GitHub App**

2. **Configure basic info:**
   - **Name**: `nx-migration-bot` (or your preferred name)
   - **Homepage URL**: Your organization/repo URL
   - **Webhook**: Uncheck "Active" (not needed)

3. **Set repository permissions:**
   ```
   Contents: Read and write          (required - clone & push)
   Pull requests: Read and write     (required - create PRs)
   Metadata: Read                    (automatic - always included)
   Members: Read                     (optional - better git attribution)
   ```

4. **Where can this app be installed?**
   - Select "Only on this account" or "Any account" based on your needs

5. Click **Create GitHub App**

#### Step 2: Generate Private Key

1. In your newly created GitHub App settings, scroll to **Private keys**
2. Click **Generate a private key**
3. Save the downloaded `.pem` file securely

#### Step 3: Install App

1. Go to **Install App** (left sidebar)
2. Click **Install** next to your organization/account
3. Select repositories:
   - **All repositories** (for org-wide use), OR
   - **Only select repositories** (choose specific repos)
4. Click **Install**

#### Step 4: Configure Repository Secrets/Variables

**Add Variable** (Settings → Secrets and variables → Actions → Variables):

```
Name:  GITHUB_APP_ID
Value: <your-app-id>  # Found on app settings page
```

**Add Secret** (Settings → Secrets and variables → Actions → Secrets):

```
Name:  GITHUB_APP_PRIVATE_KEY
Value: <paste-entire-pem-file-contents>
```

**Example `.pem` format:**
```
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA...
... (multiple lines) ...
-----END RSA PRIVATE KEY-----
```

⚠️ **Important**: Paste the ENTIRE file contents including `-----BEGIN RSA PRIVATE KEY-----` and `-----END RSA PRIVATE KEY-----`

### Using GITHUB_TOKEN

**Step 1**: Ensure workflow has correct permissions

```yaml
permissions:
  contents: write        # Required to push branches
  pull-requests: write   # Required to create PRs

jobs:
  migrate:
    uses: tsok-org/.github/.github/workflows/nx-migrate.yml@main
    with:
      base_branch: main
    secrets:
      github_token: ${{ secrets.GITHUB_TOKEN }}  # Automatically provided
```

**Limitations:**
- Cannot bypass branch protection rules
- Auto-merge may not work if branch protection requires reviews
- Limited to repository scope

---

## Configuration Reference

See the [workflow file](nx-migrate.yml) for complete input/secret/output definitions.

### Key Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `version` | - | Explicit Nx version (e.g., `21.0.0`) |
| `channel` | `stable` | Release channel: `stable`, `rc`, or `beta` |
| `major_version` | - | Target major version (e.g., `21`) |
| `minor_version` | - | Target minor version (e.g., `0`) |
| `branch_name_template` | `update-nx-{version}` | Branch name with `{version}` placeholder |
| `pr_title_template` | `build: 📦 update Nx to {version}` | PR title with `{version}` and `{version_type}` placeholders |
| `pr_auto_merge` | `true` | Enable auto-merge (requires branch protection) |

---

## Version Selection Strategies

### 1. Explicit Version

```yaml
with:
  version: "21.0.0"  # Exact version
```

### 2. Channel-Based (Recommended)

```yaml
with:
  channel: "stable"  # stable, rc, or beta
```

### 3. Major/Minor Targeting

```yaml
with:
  channel: "stable"
  major_version: "21"    # Stay in v21.x.x
  minor_version: "0"     # Stay in v21.0.x
```

---

## Usage Examples

### Example 1: Basic Setup

```yaml
name: NX Auto-Update

on:
  schedule:
    - cron: "0 6 * * *"

permissions:
  contents: write
  pull-requests: write

jobs:
  migrate:
    uses: tsok-org/.github/.github/workflows/nx-migrate.yml@main
    with:
      github_app_id: ${{ vars.GITHUB_APP_ID }}
    secrets:
      github_app_private_key: ${{ secrets.GITHUB_APP_PRIVATE_KEY }}
```

### Example 2: Advanced Configuration

```yaml
jobs:
  migrate:
    uses: tsok-org/.github/.github/workflows/nx-migrate.yml@main
    with:
      github_app_id: ${{ vars.GITHUB_APP_ID }}
      channel: "stable"
      major_version: "21"
      branch_name_template: "chore/nx-{version}"
      pr_title_template: "chore(deps): upgrade Nx to {version}"
      pr_labels: "dependencies,automated,nx-migration"
      pr_auto_merge: true
    secrets:
      github_app_private_key: ${{ secrets.GITHUB_APP_PRIVATE_KEY }}
```

---

## Customization Guide

### Branch Naming

Use `{version}` placeholder:

```yaml
branch_name_template: "chore/nx-upgrade-{version}"
# Result: chore/nx-upgrade-21.0.0
```

### PR Titles

Use `{version}` and `{version_type}` placeholders:

```yaml
pr_title_template: "chore: upgrade Nx to {version} ({version_type})"
# Result: chore: upgrade Nx to 21.0.0-beta.5 (beta)
```

### PR Labels

Comma-separated labels:

```yaml
pr_labels: "dependencies,automated,high-priority"
```

---

## Safety & Validation

### Input Validation

- ✅ Semver format validation (`X.Y.Z` or `X.Y.Z-prerelease`)
- ✅ Numeric validation for major/minor versions
- ✅ Template placeholder validation
- ✅ Nx workspace detection

### Safety Checks

- 🛡️ Prevents major version downgrades
- 🛡️ Skips if already on target version
- 🛡️ Handles existing PRs (closes outdated)
- 🛡️ Validates version exists in npm registry

---

## Troubleshooting

### Common Issues

#### "No GitHub token available"

**Solution**: Provide authentication:

```yaml
# Option 1: GitHub App
with:
  github_app_id: ${{ vars.GITHUB_APP_ID }}
secrets:
  github_app_private_key: ${{ secrets.GITHUB_APP_PRIVATE_KEY }}

# Option 2: Token
secrets:
  github_token: ${{ secrets.GITHUB_TOKEN }}
```

#### Auto-merge not working

**Causes:**
1. Branch protection not configured
2. Using `GITHUB_TOKEN` (limited permissions)
3. Required status checks not passing

**Solutions:**
1. Configure branch protection rules
2. Use GitHub App authentication
3. Ensure CI checks pass

#### "Invalid version format"

Remove `v` prefix:

```yaml
# ❌ Wrong
version: "v21.0.0"

# ✅ Correct
version: "21.0.0"
```

---

## Production Readiness

### Pre-Deployment Checklist

- [ ] Authentication configured (GitHub App or token)
- [ ] Secrets stored securely in repository settings
- [ ] Branch protection rules configured (for auto-merge)
- [ ] Status checks defined in branch protection
- [ ] Labels created (if using custom labels)
- [ ] Tested in non-critical repository first

### Monitoring

**Key Metrics:**
- Workflow execution success rate
- Migration success rate  
- Auto-merge rate
- Average execution time

**Recommended Alerts:**
- Workflow failures (immediate)
- Migration failures (immediate)
- Auto-merge failures (daily digest)

### Security Best Practices

✅ **Do:**
- Store secrets in repository/organization secrets
- Use GitHub App authentication for production
- Rotate private keys annually
- Use least-privilege permissions

❌ **Don't:**
- Commit secrets to repository
- Share private keys via insecure channels
- Grant excessive permissions
- Disable branch protection for convenience

---

## Support

**Resources:**
- [Nx Documentation](https://nx.dev)
- [GitHub Actions Documentation](https://docs.github.com/actions)
- [GitHub Apps Documentation](https://docs.github.com/apps)

**Contact:**
- Owner: The Source of Knowledge Team
- Issues: [GitHub Issues](../../issues)

---

## License

MIT License
