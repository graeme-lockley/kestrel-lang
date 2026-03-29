# Negative E2E Test Suite

## Sequence: 51
## Tier: 5 — Test coverage and quality
## Former ID: 18

## Summary

The E2E test infrastructure (`scripts/run-e2e.sh`) supports negative tests but the `tests/e2e/scenarios/negative/` directory has very few actual test files. Negative tests verify that programs with errors (syntax, type, runtime) fail as expected.

## Current State

- `run-e2e.sh` iterates over `tests/e2e/scenarios/negative/*.ks`, compiling each and verifying that either compilation or execution fails.
- The `negative/` directory may contain only a `README.md` and one scenario; expand with many more.
- Conformance tests (`tests/conformance/typecheck/invalid/`) cover type errors at the compiler level.
- Gaps: runtime errors (uncaught exceptions, stack overflow), compile errors at the full pipeline, multi-module resolution failures.

## Relationship to other stories

- **Done [15](../done/15-overflow-and-division-by-zero-exception-tests.md)** — `tests/unit/overflow_divzero.test.ks` is the canonical overflow/div-by-zero behaviour; the E2E **division-by-zero** scenario should stay consistent with that (uncaught `DivideByZero` at full compile+VM pipeline).
- **Adjacent [52](52-conformance-test-coverage-expansion.md)** (planned) — conformance expands parse/typecheck/runtime corpora under `tests/conformance/`; this story is **integration/E2E** via `run-e2e.sh`, not a substitute for conformance files.
- **None** blocking: no compiler or VM feature work is required unless a listed scenario is currently impossible (then narrow acceptance or file a follow-up).

## Goals

1. Provide a **minimal but representative** set of negative E2E scenarios so regressions in the full CLI → compiler → `.kbc` → VM path show up in `./scripts/run-e2e.sh` and thus `./scripts/test-all.sh`.
2. Keep each scenario **self-documenting** (header comment stating expected failure phase and kind).
3. Ensure the runner output is **unambiguous per scenario** (identifiable test name on pass; clear failure message on break).

## Acceptance Criteria

- [ ] **Compile failure tests** (at least 5):
  - Syntax error (malformed expression)
  - Type error (argument type mismatch)
  - Unknown import (module not found)
  - Non-exhaustive match
  - Duplicate export name
- [ ] **Runtime failure tests** (at least 5):
  - Uncaught exception (no try/catch)
  - Explicit `exit(1)`
  - Division by zero (coordinate with sequence **15** overflow/divzero unit tests)
  - Stack overflow (deeply recursive function)
  - Pattern match on unexpected ADT constructor (if possible)
- [ ] Each test file has a clear comment explaining what error is expected.
- [ ] `run-e2e.sh` reports pass/fail per test with the test name.
- [ ] All negative tests pass in `scripts/test-all.sh`.

## Spec References

- 08-tests §3.5 (Coverage goals: errors -- golden or conformance tests for expected compile and runtime errors)

## Risks / Notes

- **`uncaught_exception.ks` special-case:** `run-e2e.sh` applies extra stderr assertions only when `basename` is `uncaught_exception`. Adding more “uncaught exception” scenarios either reuses that filename (awkward) or requires **generalizing** the script (e.g. optional marker in a comment, or stderr checks for all runtime-fail cases). Plan: prefer one dedicated file for the stack-trace shape vs generic uncaught errors, and extend the harness if we split scenarios.
- **Stack overflow:** Depth must fail reliably without impractical CI runtime; prefer a small recursion depth that still overflows the VM **call** stack (not TCO’d). If the VM or limits change, adjust depth or document the assumption in the scenario comment.
- **Duplicate export / unknown import:** Exact diagnostics are not golden-tested here—only **compile failure**. If the compiler error message changes, E2E should still pass.
- **ADT “unexpected constructor”:** If the language cannot express this as a runtime failure in a single file, document deferral in **Build notes** and replace with the closest supported case (e.g. `is` / narrowing runtime failure) per team agreement.

## Impact analysis

| Area | Impact |
|------|--------|
| **Scripts** | `scripts/run-e2e.sh` — possibly extend stderr/name reporting or generalize post-run checks beyond `uncaught_exception`. |
| **Tests** | New `.ks` files under `tests/e2e/scenarios/negative/`; optional README tweaks. |
| **Compiler / VM** | None unless a scenario reveals a missing language feature (then stop and split a language story). |
| **CI / `test-all.sh`** | No change expected beyond more scenarios consumed by existing `run-e2e.sh` invocation. |
| **Risk** | Flaky stack-overflow depth across machines; mitigate with fixed conservative depth. Rollback: delete or skip a scenario file. |

## Tasks

- [ ] Inventory `tests/e2e/scenarios/negative/*.ks` and map each to acceptance buckets (compile vs runtime); adjust or rename `uncaught_exception.ks` so acceptance rows are clearly satisfied (e.g. separate **uncaught throw** vs **divide by zero** if both are required).
- [ ] Add **five compile-failure** scenarios (minimal `.ks` each): syntax error; type mismatch; import of non-existent module path; non-exhaustive `match`; duplicate export name (two exports with the same identifier). Top-of-file comment: expected phase = compile.
- [ ] Add or complete **five runtime-failure** scenarios: uncaught exception (not necessarily div-by-zero); `exit(1)` (builtin `exit`, see typecheck env); division by zero uncaught; deep non-tail recursion for stack overflow; ADT/pattern case that fails at runtime if expressible—otherwise document substitute and get acceptance alignment.
- [ ] Update `scripts/run-e2e.sh` so **every** negative scenario prints a **consistent pass line** including the scenario basename (and optionally `FAIL` + name on error paths already printed). Remove or generalize the hard-coded `uncaught_exception` stderr check if multiple files need the same assertion (or keep one canonical stack-trace file only).
- [ ] Run `./scripts/run-e2e.sh` and `./scripts/test-all.sh` locally; fix ordering or timeouts if stack test is slow.
- [ ] Refresh `tests/e2e/scenarios/negative/README.md` with a short table or list pointing to each scenario and its category.

## Tests to add

| Layer | What to add | Proves |
|-------|-------------|--------|
| **E2E** | 9+ new or adjusted `tests/e2e/scenarios/negative/*.ks` (plus existing) | Full pipeline rejects invalid programs or VM exits non-zero as documented in file comments. |
| **Integration** | None required beyond `run-e2e.sh` unless harness logic grows—then optional small bash test or manual checklist in story **Build notes**. | Harness stays deterministic. |
| **Unit / conformance** | No duplicate of `tests/conformance/typecheck/invalid/`—those remain the home for message-level type errors; E2E only supplements end-to-end. | Clear separation of concerns. |

## Documentation and specs to update

- [ ] `docs/specs/08-tests.md` — §2.x or §3.5: mention `tests/e2e/scenarios/negative/` and that `run-e2e.sh` exercises compile+runtime failure scenarios (keep aligned with §3.5 coverage goals).
- [ ] `tests/e2e/scenarios/negative/README.md` — scenario index and conventions (comments, compile vs runtime).

## Notes

- Builtin `exit` is wired in the compiler (`check.ts` / codegen); no import needed for `exit(1)` in a standalone E2E script—verify once when adding that file.
- Positive E2E under `tests/e2e/scenarios/positive/` is out of scope for this story.
