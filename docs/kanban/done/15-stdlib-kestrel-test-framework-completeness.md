# Stdlib kestrel:test Framework Completeness

## Sequence: 15
## Tier: 4 — Stdlib and test harness
## Former ID: 110

## Summary

**Done.** `stdlib/kestrel/test.ks` now exports `neq`, `isTrue`, `isFalse`, `gt`/`lt`/`gte`/`lte` (total order on `Int` only; `Float` explicitly out of scope in `02-stdlib.md`), richer failure lines (kind labels via text + `__format_one`), and `throws` using the agreed thunk type **`(Unit) -> Unit`** with the harness invoking `thunk(())`. The language does **not** accept `() -> T` in type position today, so a literal zero-parameter **function type** is not expressible; `(Unit) -> Unit` is the supported equivalent.

Colocated **`stdlib/kestrel/test.test.ks`** exercises pass and failure paths (including isolated `counts` for intentional failures), nested `group` aggregation, `summaryOnly`, `runProcess` on **`tests/fixtures/kestrel_test_printsummary_exit1.ks`** for `printSummary` → `exit(1)`, and dual-runtime coverage via `kestrel test-both`. Skip / `xfail` helpers remain future work (not in acceptance criteria).

## Current State

- See **Summary** and **`docs/specs/02-stdlib.md`** (kestrel:test).

## Tasks

- [x] Extend `stdlib/kestrel/test.ks` (assertions, failure text, `throws`)
- [x] Add `stdlib/kestrel/test.test.ks` + `tests/fixtures/kestrel_test_printsummary_exit1.ks`
- [x] Update `02-stdlib.md`, `08-tests.md`, `09-tools.md`, `guide.md`
- [x] Run `./scripts/kestrel test`, `npm test` (compiler), `zig build test` (vm), `./scripts/run-e2e.sh`, `kestrel test-both` on touched stdlib test

## Acceptance Criteria

### API and behaviour

- [x] Add `neq(suite, desc, actual, notExpected)` — assert values are not equal (same generic discipline as `eq`).
- [x] Add `isTrue(suite, desc, value)` and `isFalse(suite, desc, value)` — boolean assertions.
- [x] Add `gt`, `lt`, `gte`, `lte` — **total order on `Int`** (signatures and edge cases documented in `02-stdlib.md`; if `Float` support is in scope, document it explicitly there).
- [x] Improve failure messages: failure lines must disambiguate values meaningfully (e.g. explicit kind/type labels or unambiguous formatting) when `actual` and `expected` differ; document the exact format in specs (see Documentation below).
- [x] **`throws(suite, desc, fn)`** — only if a zero-argument `() -> Unit` (or agreed thunk type) is supported in the test harness and documented; otherwise defer and record the blocker in this story’s summary or a follow-up kanban item (do not leave a vague “consider” in the done criteria).

### Documentation (all must be updated to match shipping behaviour)

- [x] **`docs/specs/02-stdlib.md`** — Add a **kestrel:test** section: normative descriptions and signatures for `Suite`, `group`, `eq`, `printSummary`, and every new export (including pass/fail semantics, interaction with `summaryOnly`, and that `printSummary` drives process exit).
- [x] **`docs/specs/08-tests.md` §2.7** — Mention the `kestrel:test` module and the colocated suite `stdlib/kestrel/test.test.ks` (or the chosen path) alongside existing `stdlib/kestrel/*.test.ks` bullets; align wording with whatever new assertions exist.
- [x] **`docs/specs/09-tools.md` §2.4–2.5** — Refresh if user-visible harness output, summary parsing assumptions, or `test-both` comparison text changes (today these reference `printSummary` and [`stdlib/kestrel/test.ks`](../../../stdlib/kestrel/test.ks)).
- [x] **`docs/guide.md` — Testing** — Update examples and prose so users see the full recommended surface (`eq` plus new helpers, grouping, failure output expectations).

### Unit tests (exhaustive coverage requirement)

- [x] Add **`stdlib/kestrel/test.test.ks`** next to `stdlib/kestrel/test.ks` (same pattern as other stdlib modules). It must be picked up by default discovery (`./scripts/kestrel test` with no args).
- [x] **Pass paths:** For every exported assertion helper, include cases that **must pass** — including boundary values for ordering (`gt`/`lt`/`gte`/`lte` at ties and adjacent integers), boolean true/false, and `neq`/`eq` pairs that distinguish common confusions (e.g. `0` vs `False` cannot share a test if types forbid it; use values allowed by the type system).
- [x] **Failure semantics:** Where behaviour is observable without terminating the whole repo suite, assert it directly. For behaviour that ends in non-zero exit (e.g. `printSummary` after failures), verify using a **deterministic** strategy documented in the test file — e.g. a small **fixture** under `tests/fixtures/` run via `kestrel:process` `runProcess` (same pattern as `scripts/run_tests.ks`), and/or **E2E / golden** scenarios under `tests/e2e/` if that is the project’s chosen place for stdout/exit assertions. The story is not complete with “only happy-path” tests.
- [x] **`group`:** At least one nested `group` test that proves pass/fail counts aggregate correctly into the shared `Suite` counts (and, if practical, one case with `summaryOnly` consistent with existing harness `--summary` usage).
- [x] **Dual runtime:** New or updated coverage must pass **`./scripts/kestrel test`** on the default target and must not regress **`kestrel test-both`** expectations for the touched files (JVM path must remain valid for any code exercised from `test.ks`).

### Verification gates

- [x] `./scripts/kestrel test` (full discovery) passes.
- [x] `cd compiler && npm test` and `cd vm && zig build test` pass if any compiler or VM change was required for formatting, primitives, or codegen.

## Spec References

- [02-stdlib.md](../../specs/02-stdlib.md) — Stdlib contract (must gain **kestrel:test**)
- [08-tests.md](../../specs/08-tests.md) §2.7 — Stdlib / unit harness layout and `stdlib/kestrel/*.test.ks` coverage (not §3.5: that section is **golden / high-level coverage goals**, not the `kestrel:test` API)
- [09-tools.md](../../specs/09-tools.md) §2.4–2.5 — `kestrel test` / `test-both` and harness output
- [guide.md](../../guide.md) — User-facing testing guide
