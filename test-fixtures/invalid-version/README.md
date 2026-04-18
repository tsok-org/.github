# Fixture: invalid-version

**EXPECTED TO FAIL VALIDATION.**

`version: "2"` is not in the schema's enum (only `"1"` is allowed). If this
fixture *passes* schema validation, the validator is not actually enforcing the
schema — the whole pre-merge guarantee is hollow.

This fixture exists to prove the self-test actually catches invalid input rather
than rubber-stamping everything. Do not "fix" it by bumping the schema.
