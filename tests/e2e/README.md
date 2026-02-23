# E2E tests

E2E runs **negative tests only**: scenarios that must **fail** (at compile time or at runtime).

- **Negative scenarios**: `scenarios/negative/*.ks` — see `scenarios/negative/README.md`.
- **Positive behaviour** (compile + run successfully) is covered by **Kestrel unit tests** in `tests/unit/*.test.ks`, run via `./scripts/kestrel test`. Those unit tests are full compile-and-execute tests with assertions; only failure cases remain in E2E.

Run E2E: `./scripts/run-e2e.sh`
