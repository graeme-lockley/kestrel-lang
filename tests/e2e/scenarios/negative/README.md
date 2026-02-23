# E2E negative tests

Only **negative** scenarios belong here: tests that must **fail** (at compile time or at runtime).

- **Compile failure**: put a `.ks` file that is invalid (e.g. type error, syntax error). The runner expects compilation to fail; if it compiles, the test fails.
- **Runtime failure**: put a `.ks` file that compiles but exits non-zero (e.g. throws, or calls `exit(1)`). The runner runs it and expects a non-zero exit code.

Positive behaviour (programs that compile and run successfully) is covered by **Kestrel unit tests** in `tests/unit/*.test.ks`, which run via `./scripts/kestrel test` and exercise compilation and execution with assertions.
