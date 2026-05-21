# Reusable workflows — design + the `@v5` language-agnostic shape

The reusable workflows in `tsok-org/.github` follow one architectural rule:

> **The reusable workflows are language-agnostic.** They orchestrate Nx and
> standard CI primitives (checkout, set-shas, install, run, summarise) and
> nothing more. Anything language-specific (toolchain config, target-dir
> scoping, language-specific cache strategies, tool installs) lives in a
> dedicated **composite action**, gated behind an opt-in input.

Adding a new language (Go, Python, C, Java, …) means adding a new composite
action — **never** editing the reusable workflows themselves.

---

## Architecture at a glance

```
┌──────────────────────────────────────────────────────────────────────────┐
│  WORKFLOWS  (language-agnostic)                                          │
│  ────────────────────────────                                            │
│  nx-affected-plan.yml@v5  affected graph → matrix + gates                │
│  nx-ci.yml@v5             single-target Nx execution                     │
│  nx-cd.yml@v4             release orchestration (Phase 7 → v5)           │
│  dependabot-auto-merge.yml, gitleaks.yml, …                              │
└──────────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ language_packs: "rust"   ─┐
                                  │                          opt-in
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  COMPOSITE ACTIONS  (language-specific extras, opt-in)                   │
│  ─────────────────────────────────────────────────                       │
│  actions/nx-workspace-setup  Nx workspace install (auto, mandatory)      │
│  actions/nx-rust-setup       Rust CI extras (CARGO_TARGET_DIR, …)        │
│  (future)                                                                │
│    actions/nx-go-setup       Go CI extras                                │
│    actions/nx-python-setup   Python CI extras                            │
│    actions/nx-c-setup        C/C++ CI extras                             │
│    actions/nx-java-setup     Java CI extras                              │
│                                                                          │
│  HOST-MODE LEGACY                                                        │
│  actions/environment-setup   Kitchen-sink declarative setup (.env.yml)   │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Container mode vs host mode

The reusable workflows support both. The distinction matters because
language packs **only run in container mode** — host mode delegates to the
legacy `environment-setup` composite (which is itself declarative via
`.environment.yml`).

| Mode | When | What sets up the toolchain |
|---|---|---|
| Container (`container_image` set) | The job runs inside a pre-built OCI image that bakes the toolchains. | The image. The `nx-workspace-setup` composite runs `pnpm install`; language packs add their CI-glue extras. |
| Host (`container_image` empty) | Legacy v1/v2 caller path. | `actions/environment-setup` reads `.environment.yml` and installs everything on the host runner. Language packs are silently skipped. |

We strongly recommend **container mode** for new repos. It's faster
(no per-job apt/install), more reproducible (the image is the contract),
and the language-pack architecture only makes sense there.

---

## Language packs

A language pack is a composite action at `actions/nx-<lang>-setup/action.yml`
that runs **before** the Nx target step. It is invoked when a caller passes
`language_packs: "<lang>[,...]"` to `nx-ci.yml@v5` (or future `nx-cd.yml@v5`).

### What a pack does

Each pack handles its language's CI-glue extras — the things that aren't
"install the toolchain" (the image's job) but also aren't "run Nx" (the
workflow's job). Examples per language:

| Language | Pack responsibilities |
|---|---|
| Rust (`rust`) | Validate cargo env enums; per-shard `CARGO_TARGET_DIR`; cache gating; `cargo-nextest` install if absent |
| Go (future, `go`) | `GOPATH` per shard; `GOCACHE`; module cache; `gotestsum` install |
| Python (future, `python`) | venv setup; pip cache; coverage tool install |
| C/C++ (future, `c`) | `cmake` configure step; ccache / sccache; per-shard build dir |
| Java (future, `java`) | gradle cache; per-shard build dir; `gradle wrapper` validation |

### What a pack does NOT do

- Install the language toolchain (rustup/go/python/javac/…). That's the
  container image's job.
- Run any Nx command. That's the workflow's job.
- Mutate `nx.json` or any source files.

### Adding a new language pack

1. Create `actions/nx-<lang>-setup/action.yml` (use `actions/nx-rust-setup`
   as a template).
2. Implement the steps that handle your language's CI-glue.
3. Add a new step in `.github/workflows/nx-ci.yml` (and `nx-cd.yml`) that
   conditionally invokes your composite:
   ```yaml
   - name: <Lang> language pack
     if: inputs.container_image != '' && contains(format(',{0},', inputs.language_packs), ',<lang>,')
     uses: tsok-org/.github/actions/nx-<lang>-setup@main
     with:
       # pack-specific inputs
   ```
4. Document the pack in this file's "Composite actions" section below.
5. Bump the workflow's tag (typically a minor — `@v5.1`) when you cut a
   release that includes the new pack.

The reusable workflows already accept `language_packs` as a CSV. The new
pack name becomes a valid token in that CSV.

---

## Composite actions reference

### `actions/nx-workspace-setup` — mandatory in container mode

Bootstraps the Nx workspace by detecting the package manager from the
lockfile and running its `--frozen-lockfile` install. Required even for
pure-Rust workspaces because Nx itself is a Node package.

Inputs:
- `working_directory` (default `.`)
- `frozen_lockfile` (default `true`)

Outputs:
- `manager` — detected package manager
- `exec` — invocation prefix (e.g. `pnpm`)

### `actions/nx-rust-setup` — Rust language pack

Container-mode CI-glue for Rust workspaces. Runs after `nx-workspace-setup`.

Inputs:
- `target` — Nx target name (for `CARGO_TARGET_DIR` scoping)
- `shard` / `shards_total` — shard index for per-shard target dir
- `container_image` — passed through for the cache gating decision
- `install_nextest` (default `true`) — install `cargo-nextest` if absent
- `nextest_version` (default `^0.9`)

Behaviour:
1. Validate `CARGO_TERM_VERBOSE`, `CARGO_TERM_COLOR`, `RUST_BACKTRACE`
   against allowed enums.
2. If `shards_total > 1`, set `CARGO_TARGET_DIR=/tmp/cargo-target-<target>-<shard>`.
3. On GitHub-hosted runners only, enable `Swatinem/rust-cache` for the
   cargo registry + target tree.
4. Install `cargo-nextest` if absent and `install_nextest` is `true`.

---

## Workflow reference

### `nx-affected-plan.yml@v5`

Computes the affected project set, splits it into per-target shards, and
emits a matrix the caller fans out across runners. Language-agnostic.

#### New in v5: `gates`

Lets the plan emit a JSON map of boolean gates derived from the affected
project set. Avoids needing a separate "detect affected" job to evaluate
"does this PR touch X?" conditions.

```yaml
plan:
  uses: tsok-org/.github/.github/workflows/nx-affected-plan.yml@v5
  with:
    targets: "test,integration"
    test_shards: 3
    integration_shards: 3
    gates: "has_sql=mcpg-plugin-backend-sql;has_cluster=mcpg-plugin-cluster-*"

# Consume:
sql-matrix:
  needs: plan
  if: fromJSON(needs.plan.outputs.gates).has_sql == true
  ...
```

### `nx-ci.yml@v5`

Single-target Nx execution. Body is language-agnostic; language-specific
behaviour lives in composites invoked via `language_packs`.

#### New in v5

| Input | Purpose |
|---|---|
| `language_packs` | CSV of language packs to enable in container mode (e.g. `"rust"`, `"rust,go"`). |
| `target_configuration` | Nx target configuration suffix appended to the target name. E.g. `integration` + `pg17` → `integration:pg17`. |
| `extra_env_json` | JSON object of additional env vars to export to `GITHUB_ENV` before the target runs. Useful for per-matrix-row parameterisation. |
| `nx_powerpack_cache_mode` | Override the auto-computed `read-only`/`read-write` mode. Default empty = auto. |

#### Breaking changes v4 → v5

- The inline `Validate CI env vars (container mode)`, `Cache cargo registry
  + target (container mode)`, and `Scope CARGO_TARGET_DIR per shard` steps
  have been removed. Their behaviour moved to `actions/nx-rust-setup`. To
  preserve v4 behaviour, callers must add `language_packs: "rust"`.
- The hardcoded `pnpm install --frozen-lockfile` step has been replaced by
  `actions/nx-workspace-setup`, which auto-detects pnpm/yarn/npm/bun. No
  caller action needed unless your workspace previously relied on the
  pnpm-only behaviour.

---

## Migration guide @v4 → @v5

For Rust-based Nx workspaces (the existing v4 use case):

```diff
 pr-validate:
-  uses: tsok-org/.github/.github/workflows/nx-ci.yml@v4
+  uses: tsok-org/.github/.github/workflows/nx-ci.yml@v5
   with:
+    language_packs: "rust"
     lint: true
     build: true
     ...
```

For TypeScript-only workspaces:

```diff
 pr-validate:
-  uses: tsok-org/.github/.github/workflows/nx-ci.yml@v4
+  uses: tsok-org/.github/.github/workflows/nx-ci.yml@v5
   with:
+    # language_packs intentionally empty — nx-workspace-setup is implicit.
     lint: true
     test: true
     build: true
```

For per-DB-engine matrix callers (new pattern):

```yaml
sql-matrix:
  needs: plan
  if: fromJSON(needs.plan.outputs.gates).has_sql == true
  strategy:
    matrix:
      include:
        - { config: pg14, image: postgres:14-alpine, scheme: postgres }
        - { config: pg17, image: postgres:17-alpine, scheme: postgres }
  uses: tsok-org/.github/.github/workflows/nx-ci.yml@v5
  with:
    language_packs: "rust"
    target: integration
    target_configuration: ${{ matrix.config }}
    projects: my-sql-plugin
    extra_env_json: |
      {"POSTGRES_TEST_URL": "${{ matrix.scheme }}://u:p@postgres:5432/db"}
    container_image: ghcr.io/myorg/build-env:ci-latest
    container_options: --volume /var/run/docker.sock:/var/run/docker.sock
  # NOTE: services: blocks can't be expressed via a reusable-workflow
  # input today — DB-matrix callers that need GH `services:` containers
  # currently stay inline in the consumer workflow.
```
