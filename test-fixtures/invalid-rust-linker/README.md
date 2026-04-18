# Fixture: invalid-rust-linker

**EXPECTED TO FAIL VALIDATION.**

`rust.linker` is a string enum that only accepts `"lld"` or `"mold"`. `"gold"`
is the old GNU gold linker and is not supported by the action. The schema
rejects it.

If this fixture passes validation, the enum constraint on `rust.linker` is not
being enforced — which would let consumers ship configs the action silently
ignores (see the `Unknown rust.linker` warning path in action.yml).
