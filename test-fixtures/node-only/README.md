# Fixture: node-only

**Expected:** schema validation passes; only `setup_node=true` is emitted, everything
else `setup_*=false`.

Exercises the "single-language" path: a repo that only needs Node.js/pnpm and no
other runtimes, tools, or services. Guards against regressions where the parser
accidentally turns on unrelated components when sections are absent.
