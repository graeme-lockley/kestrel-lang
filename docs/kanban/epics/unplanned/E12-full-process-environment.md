# Epic E12: Full Process Environment

## Status

Unplanned

## Summary

`getProcess().env` is spec'd as `List<(String, String)>` — a list of all environment variable key-value pairs — but the implementation always returns `[]` (empty list). This was explicitly deferred during E11 (S11-01) because populating the full environment map requires returning a variable-length collection from the JVM runtime, which is a more involved change than the single-variable `getEnv(String)` lookup added in E11. This epic completes the contract: `getProcess().env` returns the real process environment, and any follow-on ergonomic improvements (e.g. a `Dict<String, String>` view or a `getEnvAll()` shorthand) are included.

## Stories

1. [S12-01 — `getProcess().env` full environment map](../../unplanned/S12-01-getprocess-env-full.md)

## Dependencies

- E11 (Pure-Kestrel Test Runner) — `getEnv(String) -> Option<String>` is already in place; this epic builds on that groundwork. E11 must be done (it is).

## Epic Completion Criteria

- `getProcess().env` returns a `List<(String, String)>` containing every environment variable present when the Kestrel program was launched; the list is non-empty for any normal invocation.
- The result is consistent with `getEnv(name)`: for every `(k, v)` in `getProcess().env`, `getEnv(k)` returns `Some(v)`.
- `KRuntime` provides a new static method that converts `System.getenv()` to a Kestrel list of tuples.
- A conformance runtime test verifies that `getProcess().env` is non-empty and that a known variable (`PATH`) appears in it.
- `docs/specs/02-stdlib.md` accurately reflects the populated `env` field behaviour.
- All test suites pass: `cd compiler && npm test`, `./kestrel test`.
