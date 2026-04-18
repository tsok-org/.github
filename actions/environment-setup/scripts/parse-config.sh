#!/usr/bin/env bash
# ==============================================================================
# parse-config.sh
# ------------------------------------------------------------------------------
# Parses a .environment.yml file and emits key=value lines to $GITHUB_OUTPUT
# for the composite action to consume. Validated upstream by check-jsonschema
# against schema.json.
#
# Usage:  parse-config.sh <config-file>
# Env:    SKIP_COMPONENTS  — comma-separated list of components to skip
#         ONLY_COMPONENTS  — comma-separated allowlist (overrides SKIP)
#         DOCKER_REGISTRY  — optional override for docker.registry
#         GITHUB_OUTPUT    — set by the GitHub runner
# ==============================================================================
set -euo pipefail

CONFIG_FILE="${1:-.environment.yml}"
: "${SKIP_COMPONENTS:=}"
: "${ONLY_COMPONENTS:=}"
: "${GITHUB_OUTPUT:=/dev/stdout}"

# ------------------------------------------------------------------------------
# out: append "key=value" to $GITHUB_OUTPUT
# ------------------------------------------------------------------------------
out() {
    printf '%s\n' "$1" >>"$GITHUB_OUTPUT"
}

# ------------------------------------------------------------------------------
# should_setup: returns 0 if the named component is enabled by ONLY/SKIP lists
# ------------------------------------------------------------------------------
should_setup() {
    local component="$1"

    if [[ -n "$ONLY_COMPONENTS" ]]; then
        if printf ',%s,' "$ONLY_COMPONENTS" | grep -q ",${component},"; then
            return 0
        else
            return 1
        fi
    fi

    if [[ -n "$SKIP_COMPONENTS" ]]; then
        if printf ',%s,' "$SKIP_COMPONENTS" | grep -q ",${component},"; then
            return 1
        fi
    fi

    return 0
}

# ------------------------------------------------------------------------------
# yq_get: best-effort yq read with fallback. Never aborts under `set -e`.
# ------------------------------------------------------------------------------
yq_get() {
    local expr="$1"
    local default="${2:-}"
    local value
    value=$(yq -e "$expr" "$CONFIG_FILE" 2>/dev/null || true)
    if [[ -z "$value" || "$value" == "null" ]]; then
        printf '%s' "$default"
    else
        printf '%s' "$value"
    fi
}

# ------------------------------------------------------------------------------
# No config file: emit minimal defaults and exit.
# ------------------------------------------------------------------------------
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "⚠️ No $CONFIG_FILE found, using minimal defaults"
    out "has_config=false"

    if should_setup "node" && [[ -f "package.json" ]]; then
        out "setup_node=true"
        out "node_version=.node-version"
        out "node_package_manager=auto"
        out "node_install=true"
        out "node_cache=true"
    else
        out "setup_node=false"
    fi

    out "setup_python=false"
    out "setup_terraform=false"
    out "setup_docker=false"
    out "setup_system_packages=false"
    out "setup_rust=false"
    out "setup_go=false"
    out "setup_c=false"
    out "service_redis=false"
    out "service_nats=false"
    exit 0
fi

out "has_config=true"
echo "📖 Parsing $CONFIG_FILE..."

# ------------------------------------------------------------------------------
# Node.js
# ------------------------------------------------------------------------------
NODE_CONFIG=$(yq_get '.node // false' "false")

if [[ "$NODE_CONFIG" != "false" ]] && should_setup "node"; then
    out "setup_node=true"

    if [[ "$NODE_CONFIG" == "true" ]]; then
        out "node_version_explicit="
        out "node_version_file=.node-version"
        NODE_VERSION=".node-version"
    else
        NODE_VERSION=$(yq_get '.node.version // ".node-version"' ".node-version")
        if [[ "$NODE_VERSION" == .* || "$NODE_VERSION" == */* ]]; then
            out "node_version_explicit="
            out "node_version_file=$NODE_VERSION"
        else
            out "node_version_explicit=$NODE_VERSION"
            out "node_version_file="
        fi
    fi

    # yq-go's `//` alternative triggers on null OR false, so
    # `.node.install // true` silently flips a user's explicit `false` to
    # `true`. Drop the `//` and let yq_get's bash-side fallback handle the
    # truly-missing case via null detection. Same pattern for all booleans.
    INSTALL=$(yq_get '.node.install' "true")
    out "node_install=$INSTALL"

    FROZEN=$(yq_get '.node.frozen_lockfile' "true")
    out "node_frozen_lockfile=$FROZEN"

    echo "  ✓ Node.js: version=$NODE_VERSION"
else
    out "setup_node=false"
fi

# ------------------------------------------------------------------------------
# Python
# ------------------------------------------------------------------------------
PYTHON_CONFIG=$(yq_get '.python // false' "false")

if [[ "$PYTHON_CONFIG" != "false" ]] && should_setup "python"; then
    out "setup_python=true"

    if [[ "$PYTHON_CONFIG" == "true" ]]; then
        out "python_version=3.12"
        out "python_package_manager=pip"
    elif [[ "$PYTHON_CONFIG" =~ ^[0-9] ]]; then
        out "python_version=$PYTHON_CONFIG"
        out "python_package_manager=pip"
    else
        PY_VERSION=$(yq_get '.python.version // "3.12"' "3.12")
        out "python_version=$PY_VERSION"
        PY_PKG_MGR=$(yq_get '.python.package_manager // "pip"' "pip")
        out "python_package_manager=$PY_PKG_MGR"
    fi

    PY_SUMMARY=$(yq_get '.python.version // .python // "3.12"' "3.12")
    echo "  ✓ Python: version=$PY_SUMMARY"
else
    out "setup_python=false"
fi

# ------------------------------------------------------------------------------
# Terraform / Terragrunt / TFLint
# ------------------------------------------------------------------------------
TF_CONFIG=$(yq_get '.terraform // false' "false")

if [[ "$TF_CONFIG" != "false" ]] && should_setup "terraform"; then
    out "setup_terraform=true"

    if [[ "$TF_CONFIG" == "true" ]]; then
        out "terraform_version=latest"
    elif [[ "$TF_CONFIG" =~ ^[0-9] ]]; then
        out "terraform_version=$TF_CONFIG"
    else
        TF_VERSION=$(yq_get '.terraform.version // "latest"' "latest")
        out "terraform_version=$TF_VERSION"
    fi

    TG_CONFIG=$(yq_get '.terragrunt // false' "false")
    if [[ "$TG_CONFIG" != "false" ]]; then
        if [[ "$TG_CONFIG" == "true" ]]; then
            out "terragrunt_version=latest"
        elif [[ "$TG_CONFIG" =~ ^[0-9] ]]; then
            out "terragrunt_version=$TG_CONFIG"
        else
            TG_VERSION=$(yq_get '.terragrunt.version // "latest"' "latest")
            out "terragrunt_version=$TG_VERSION"
        fi
    else
        out "terragrunt_version="
    fi

    TFLINT_CONFIG=$(yq_get '.tflint // false' "false")
    if [[ "$TFLINT_CONFIG" != "false" ]]; then
        out "tflint_enabled=true"
    else
        out "tflint_enabled=false"
    fi

    echo "  ✓ Terraform configured"
else
    out "setup_terraform=false"
fi

# ------------------------------------------------------------------------------
# Docker
# ------------------------------------------------------------------------------
DOCKER_CONFIG=$(yq_get '.docker // false' "false")

if [[ "$DOCKER_CONFIG" != "false" ]] && should_setup "docker"; then
    out "setup_docker=true"

    BUILDX=$(yq_get '.docker.buildx' "true")
    out "docker_buildx=$BUILDX"

    PLATFORMS=$(yq_get '.docker.platforms // ["linux/amd64"] | join(",")' "linux/amd64")
    out "docker_platforms=$PLATFORMS"

    # DOCKER_REGISTRY env var takes precedence over config.
    REGISTRY_CFG=$(yq_get '.docker.registry // ""' "")
    REGISTRY="${DOCKER_REGISTRY:-$REGISTRY_CFG}"
    out "docker_registry=$REGISTRY"

    echo "  ✓ Docker: buildx=$BUILDX, platforms=$PLATFORMS"
else
    out "setup_docker=false"
fi

# ------------------------------------------------------------------------------
# System packages (apt on Linux)
# ------------------------------------------------------------------------------
SYSTEM_PACKAGES=$(yq_get '.system_packages // [] | join(" ")' "")
if [[ -n "$SYSTEM_PACKAGES" ]] && should_setup "system_packages"; then
    out "setup_system_packages=true"
    out "system_packages=$SYSTEM_PACKAGES"
    echo "  ✓ System packages: $SYSTEM_PACKAGES"
else
    out "setup_system_packages=false"
fi

# ------------------------------------------------------------------------------
# Rust (toolchain from rust-toolchain.toml; this wires caching + knobs)
# ------------------------------------------------------------------------------
RUST_CONFIG=$(yq_get '.rust // false' "false")
if [[ "$RUST_CONFIG" != "false" ]] && should_setup "rust"; then
    out "setup_rust=true"
    RUST_CACHE=$(yq_get '.rust.cache' "true")
    RUST_DIAG=$(yq_get '.rust.diagnostics' "false")
    RUST_JOBS=$(yq_get '.rust.build_jobs // ""' "")
    RUST_LINKER=$(yq_get '.rust.linker // ""' "")
    RUST_COVERAGE=$(yq_get '.rust.coverage' "false")
    RUST_SCCACHE=$(yq_get '.rust.sccache' "false")
    out "rust_cache=$RUST_CACHE"
    out "rust_diagnostics=$RUST_DIAG"
    out "rust_build_jobs=$RUST_JOBS"
    out "rust_linker=$RUST_LINKER"
    out "rust_coverage=$RUST_COVERAGE"
    out "rust_sccache=$RUST_SCCACHE"
    echo "  ✓ Rust: cache=$RUST_CACHE, diagnostics=$RUST_DIAG, build_jobs=${RUST_JOBS:-auto}, linker=${RUST_LINKER:-default}, coverage=$RUST_COVERAGE, sccache=$RUST_SCCACHE"
else
    out "setup_rust=false"
fi

# ------------------------------------------------------------------------------
# Go (actions/setup-go@v5 under the hood)
# ------------------------------------------------------------------------------
GO_CONFIG=$(yq_get '.go // false' "false")
if [[ "$GO_CONFIG" != "false" ]] && should_setup "go"; then
    out "setup_go=true"

    if [[ "$GO_CONFIG" == "true" ]]; then
        out "go_version="
        out "go_version_file="
        out "go_cache=true"
        out "go_modules=true"
    elif [[ "$GO_CONFIG" =~ ^[0-9] ]]; then
        # Bare version string like "1.22" or "1.22.3"
        out "go_version=$GO_CONFIG"
        out "go_version_file="
        out "go_cache=true"
        out "go_modules=true"
    else
        GO_VERSION=$(yq_get '.go.version // ""' "")
        GO_VERSION_FILE=$(yq_get '.go.version_file // ""' "")
        # Treat leading "." or "/" in version as a file reference (parity with node).
        if [[ -z "$GO_VERSION_FILE" && ( "$GO_VERSION" == .* || "$GO_VERSION" == */* ) ]]; then
            GO_VERSION_FILE="$GO_VERSION"
            GO_VERSION=""
        fi
        out "go_version=$GO_VERSION"
        out "go_version_file=$GO_VERSION_FILE"
        GO_CACHE=$(yq_get '.go.cache' "true")
        GO_MODULES=$(yq_get '.go.modules' "true")
        out "go_cache=$GO_CACHE"
        out "go_modules=$GO_MODULES"
    fi

    echo "  ✓ Go configured"
else
    out "setup_go=false"
fi

# ------------------------------------------------------------------------------
# C toolchain (structured apt-install intent)
# ------------------------------------------------------------------------------
C_CONFIG=$(yq_get '.c // false' "false")
if [[ "$C_CONFIG" != "false" ]] && should_setup "c"; then
    out "setup_c=true"

    C_TOOLCHAIN=$(yq_get '.c.toolchain // "gcc"' "gcc")
    C_CMAKE=$(yq_get '.c.cmake' "false")
    C_PKGCONFIG=$(yq_get '.c.pkg_config' "false")
    C_EXTRA_PACKAGES=$(yq_get '.c.packages // [] | join(" ")' "")

    # Build the final apt package list.
    TOOLCHAIN_PACKAGES=""
    case "$C_TOOLCHAIN" in
        gcc)   TOOLCHAIN_PACKAGES="build-essential" ;;
        clang) TOOLCHAIN_PACKAGES="clang lld" ;;
        *)     TOOLCHAIN_PACKAGES="build-essential" ;;
    esac
    if [[ "$C_CMAKE" == "true" ]]; then
        TOOLCHAIN_PACKAGES="$TOOLCHAIN_PACKAGES cmake"
    fi
    if [[ "$C_PKGCONFIG" == "true" ]]; then
        TOOLCHAIN_PACKAGES="$TOOLCHAIN_PACKAGES pkg-config"
    fi
    if [[ -n "$C_EXTRA_PACKAGES" ]]; then
        TOOLCHAIN_PACKAGES="$TOOLCHAIN_PACKAGES $C_EXTRA_PACKAGES"
    fi

    out "c_toolchain=$C_TOOLCHAIN"
    out "c_packages=$TOOLCHAIN_PACKAGES"
    echo "  ✓ C toolchain: $C_TOOLCHAIN, packages=$TOOLCHAIN_PACKAGES"
else
    out "setup_c=false"
fi

# ------------------------------------------------------------------------------
# services — external daemon binaries installed on PATH so tests can spawn
# them as subprocesses. (Previously split into a docker-container `services`
# block + a `test_binaries` block; unified here because nobody was using the
# container variant and the split confused consumers.)
# ------------------------------------------------------------------------------
SVC_REDIS=$(yq_get '.services.redis' "false")
SVC_NATS=$(yq_get '.services.nats' "false")
out "service_redis=$SVC_REDIS"
out "service_nats=$SVC_NATS"
if [[ "$SVC_REDIS" == "true" || "$SVC_NATS" == "true" ]]; then
    echo "  ✓ Services: redis=$SVC_REDIS, nats=$SVC_NATS"
fi

echo "✅ Configuration parsed successfully"
