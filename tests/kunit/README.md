# kunit — Kestrel-compiler unit tests

This tier is the self-hosted counterpart of `tests/unit/`.

**Status: currently inactive.**
It will be populated once `kestrel:dev/test` can be compiled by the self-hosted compiler.
Until then, keep this directory empty.

Tests placed here are `.test.ks` files using the `kestrel:dev/test` harness.
They are discovered and run by `./scripts/test-kestrel.sh`.

## Baseline (S17-50, 2026-04-28)

- Files: 0
- Baseline probe: `./kestrel-self test --summary tests/unit/adts.test.ks`
- Blocker observed: probe failed while compiling stdlib dependencies
	(`stdlib/kestrel/data/dict.ks`), so no `tests/unit/*.test.ks` files were promoted yet.
