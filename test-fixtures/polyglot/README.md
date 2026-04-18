# Fixture: polyglot

**Expected:** schema validation passes; `setup_rust`, `setup_go`, `setup_c`,
`setup_node` all `true`.

Exercises the Go + C additions from the PR A refactor (the 270-line bash parser
extraction) alongside Rust and Node. This is the fixture that catches regressions
in the newer parser branches.

- `go.version: "1.22"` with `cache: true` — explicit version, setup-go cache on.
- `c.toolchain: gcc` with cmake + pkg_config + an extra library (`libpq-dev`) —
  exercises `c_packages` derivation logic.
- `node.install: false` — parser honors the flag (should emit
  `node_install=false`).
- `rust.coverage: false` — explicitly disabled, guards against default drift.
