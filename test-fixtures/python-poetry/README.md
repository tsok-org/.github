# Fixture: python-poetry

**Expected:** schema validation passes; `setup_python=true`,
`python_package_manager=poetry`.

Exercises the Python-with-Poetry path. Poetry is a second-class package_manager
behind `pip`, so it's an easy target for regressions when the parser defaults
drift.
