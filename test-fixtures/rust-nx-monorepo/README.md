# Fixture: rust-nx-monorepo

**Expected:** schema validation passes, parser emits the expected `setup_*=true` outputs.

Mirrors the current `mcpg-dev/source-code` `.environment.yml`: a full Rust workspace
inside an Nx-managed monorepo, plus Node/pnpm, Docker buildx for multi-arch images,
and the `*-sys` crate build deps (`libcurl4-openssl-dev`, `libssl-dev`,
`pkg-config`) that ship as `system_packages`.

This is the **baseline fixture**. If it ever regresses, consumers break. Do not edit
it to match a change in the action — if this fixture no longer validates, the change
is a breaking change and the schema version must be bumped.
