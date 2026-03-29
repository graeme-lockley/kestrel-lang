# E2E tests

`./scripts/run-e2e.sh` runs **two** scenario directories:

- **Negative** (`tests/e2e/scenarios/negative/*.ks`): each file must **fail** — either the compiler rejects it, or the VM exits non-zero. Some scenarios use companion modules under `negative/_fixtures/` (not picked up as top-level scenarios; only `*.ks` directly in `negative/` are run). Optional first-line marker `// E2E_EXPECT_STACK_TRACE` requests extra stderr checks for uncaught-exception-style diagnostics (see `scripts/run-e2e.sh`).
- **Positive** (`tests/e2e/scenarios/positive/*.ks`): must compile, run with exit code 0, and match sibling `*.expected` stdout goldens.

Negative scenarios are indexed in `scenarios/negative/README.md`. Broader language coverage lives in `tests/unit/*.test.ks` (via `./scripts/kestrel test`) and under `tests/conformance/`.

Run E2E from the repo root: `./scripts/run-e2e.sh`. The same script is invoked by `./scripts/test-all.sh` after compiler and VM tests.
