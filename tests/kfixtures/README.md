# kfixtures — shared Kestrel helpers for kunit tests

This directory holds `.ks` helper modules imported by tests in `tests/kunit/`.
It is the self-hosted counterpart of `tests/fixtures/`.

Place shared definitions here when multiple kunit tests need the same helpers.
Do not place test entry points here — those belong in `tests/kunit/`.
