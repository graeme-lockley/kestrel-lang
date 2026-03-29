# Negative E2E Test Suite

## Sequence: 51
## Tier: 5 — Test coverage and quality
## Former ID: 18

## Summary

The E2E test infrastructure (`scripts/run-e2e.sh`) supports negative tests but the `tests/e2e/scenarios/negative/` directory has very few actual test files. Negative tests verify that programs with errors (syntax, type, runtime) fail as expected.

## Current State

- **Done:** Ten top-level negative scenarios under `tests/e2e/scenarios/negative/` (five compile-fail, five runtime-fail) plus `_fixtures/` for the duplicate-export barrel; see `tests/e2e/scenarios/negative/README.md`.
- **`run-e2e.sh`:** stderr contract is driven by `// E2E_EXPECT_STACK_TRACE` in source (replaces basename `uncaught_exception`); failure lines use `E2E negative <name>:`.
- Conformance remains the home for precise `// EXPECT:` diagnostics; negative E2E covers full **emit → `.kbc` → Zig VM**.
- **Scope:** Negative E2E path is still **VM-only** (no JVM).

## Relationship to other stories

- **Done [15](../done/15-overflow-and-division-by-zero-exception-tests.md)** — `runtime_divide_by_zero.ks` stays aligned with uncaught `DivideByZero` at full pipeline.
- **Done [50](../done/50-stdlib-stack-trace-implementation.md)** — `uncaught_throw.ks` and `runtime_catch_no_match_rethrow.ks` use `E2E_EXPECT_STACK_TRACE` for stderr regression.
- **Adjacent [52](../planned/52-conformance-test-coverage-expansion.md)** (planned) — conformance expansion is separate from this E2E suite.

## Goals

1. Provide a **minimal but representative** set of negative E2E scenarios so regressions in the **compiler emit → `.kbc` → Zig VM** path show up in `./scripts/run-e2e.sh` and thus `./scripts/test-all.sh`.
2. Keep each scenario **self-documenting** (header comment stating expected failure phase and kind).
3. Ensure the runner output is **unambiguous per scenario** (identifiable test name on pass; clear failure message on break).

## Acceptance Criteria

- [x] **Compile failure tests** (at least 5 distinct `.ks` files):
  - Syntax error (malformed expression)
  - Type error (argument type mismatch)
  - Unknown import (module not found / unresolvable path — wording per compiler)
  - Non-exhaustive match
  - Duplicate export name
- [x] **Runtime failure tests** (at least 5 distinct `.ks` files):
  - Uncaught exception — `uncaught_throw.ks` (`throw(42)`); harness generalized via `E2E_EXPECT_STACK_TRACE`; division by zero in `runtime_divide_by_zero.ks`.
  - Explicit `exit(1)` (`runtime_exit_one.ks`)
  - Division by zero (`runtime_divide_by_zero.ks`)
  - Stack overflow (`runtime_stack_overflow.ks` — non-tail recursion, VM call-frame limit)
  - Pattern match / ADT bucket — **substitute:** `runtime_catch_no_match_rethrow.ks` (catch arm mismatch → rethrow per 01 §4), documented in file and build notes
- [x] Each test file has a clear comment explaining what error is expected (compile vs runtime).
- [x] `run-e2e.sh` reports pass/fail per negative scenario with the scenario basename on success paths (`  <name>.ks OK (...)`).
- [x] All negative tests pass when run via `./scripts/run-e2e.sh` and as part of `./scripts/test-all.sh`.
- [x] **Documentation:** Every item listed under **Documentation and specs to update** is done.

## Spec References

- 08-tests §2 (categories), §3.2 (layout), §3.5 (Coverage goals: errors — golden or conformance tests for expected compile and runtime errors)
- 09-tools §4 (relation to 08-tests / `run-e2e.sh`)

## Risks / Notes

- Historical note: `uncaught_exception.ks` was split into `uncaught_throw.ks` + `runtime_divide_by_zero.ks`; harness uses comment marker, not basename.
- **Stack overflow:** `runtime_stack_overflow.ks` uses `boom(10000)` with `boom(n - 1) + 1` against reference VM **8192** call frames; adjust if limits change.
- **JVM:** Negative E2E does not execute the JVM.

## Impact analysis

| Area | Impact |
|------|--------|
| **Scripts** | `scripts/run-e2e.sh` — `E2E_EXPECT_STACK_TRACE`, `E2E negative` failure prefix. |
| **Tests** | `.ks` under `tests/e2e/scenarios/negative/` and `_fixtures/`; E2E READMEs. |
| **Compiler / VM** | None. |
| **CI / `test-all.sh`** | Unchanged invocation; more scenarios. |
| **Docs / specs** | `docs/specs/08-tests.md`, `09-tools.md`, `AGENTS.md`, E2E READMEs. |

## Tasks

- [x] Inventory `tests/e2e/scenarios/negative/*.ks` and map each to acceptance buckets (compile vs runtime); split former `uncaught_exception.ks` into uncaught throw vs divide-by-zero.
- [x] Add **five compile-failure** scenarios (minimal `.ks` each): syntax error; type mismatch; import of non-existent module path; non-exhaustive `match`; duplicate export name. Top-of-file comment: expected phase = compile.
- [x] Add or complete **five runtime-failure** scenarios: uncaught exception path; `exit(1)`; division by zero uncaught; deep non-tail recursion for stack overflow; catch no-match rethrow as ADT/pattern substitute.
- [x] Update `scripts/run-e2e.sh` (pass lines, `E2E negative` on failure, generalized stderr check).
- [x] Run `./scripts/run-e2e.sh` and `./scripts/test-all.sh` locally; fix ordering or timeouts if stack test is slow.
- [x] Refresh `tests/e2e/scenarios/negative/README.md` with a short table or list pointing to each scenario and its category.
- [x] Update `tests/e2e/README.md` so it matches `run-e2e.sh` (**negative + positive** scenario directories and how to run).
- [x] Apply all **Documentation and specs to update** items.

## Tests to add

| Layer | What to add | Proves |
|-------|-------------|--------|
| **E2E (negative)** | **Ten** `.ks` files under `tests/e2e/scenarios/negative/` total: **5 compile-fail** (syntax; type mismatch; unknown/missing import; non-exhaustive `match`; duplicate export) and **5 runtime-fail** (uncaught exception; `exit(1)`; division by zero; stack overflow; ADT/runtime pattern failure **or** agreed substitute). Starting from one existing file, expect **nine new** scenarios unless an existing file is repurposed. Each file: top comment with phase + failure kind. | Compiler → `.kbc` → Zig VM rejects invalid programs or exits non-zero as documented. |
| **E2E harness** | Edits to `scripts/run-e2e.sh` (pass-line format, optional stderr rules for stack traces, generalization beyond `uncaught_exception`). | Harness stays deterministic; trace assertions still hold for designated scenario(s). |
| **Integration / CI** | Run **`./scripts/run-e2e.sh`** (full negative + positive sweep); run **`./scripts/test-all.sh`** after harness or scenario changes. | Repo gates stay green; E2E is included in `test-all.sh` after compiler + VM tests. |
| **Regression (harness)** | After script changes, verify the designated **stack-trace** scenario(s) still match stderr expectations (`Uncaught exception` and file/line pattern, or successor contract from story **50**). | Uncaught path still emits a usable trace in CI. |
| **Compiler Vitest (`compiler/test/`)** | **Not required** for scenario-only work (avoid duplicating `typecheck-conformance.test.ts` / invalid corpus). Add only if new TypeScript or shell entrypoints are introduced and the team mandates an automated caller test. | Clear separation from conformance diagnostics. |
| **`tests/unit/*.test.ks`** | **Not required** unless a shared fixture module is introduced that needs its own unit coverage. | No duplicate assertions for the same behaviour already covered in **15** / conformance. |
| **`zig build test` (VM)** | **Not required** unless VM or bytecode emission changes. | VM code unchanged for scenario-only delivery. |
| **JVM / `kestrel test --target jvm`** | **Not required** for negative E2E content; `run-e2e.sh` does not invoke JVM. Optional sanity if a scenario file is also imported elsewhere. | Documented scope boundary. |

## Documentation and specs to update

- [x] **`docs/specs/08-tests.md`** — §3.2: document actual layout `tests/e2e/scenarios/negative/` (compile or runtime failure, no golden stdout) and `tests/e2e/scenarios/positive/` (stdout vs `.expected`); §3.3 or §3.5: state that `./scripts/run-e2e.sh` runs both and that negative scenarios assert failure (compile error or non-zero VM exit), with optional stderr checks for selected uncaught-exception cases. Align §3.5 “Errors” bullet with this suite.
- [x] **`tests/e2e/scenarios/negative/README.md`** — scenario index table (file → compile vs runtime → brief intent); conventions for header comments.
- [x] **`tests/e2e/README.md`** — correct “negative only” wording: describe **both** negative and positive directories and point to `scenarios/negative/README.md`.
- [x] **`docs/specs/09-tools.md`** — §4 relation bullet (or §3): one sentence that `run-e2e.sh` runs negative scenarios under `tests/e2e/scenarios/negative/` (and positive under `positive/`) using compiler + VM — keeps cross-spec navigation accurate.
- [x] **`AGENTS.md`** — **End-to-End Tests** subsection: mention `tests/e2e/scenarios/negative/` and `positive/` and that `./scripts/test-all.sh` invokes `run-e2e.sh` (helps agents and contributors discover the layout).

## Notes

- Builtin `exit` is wired in the compiler (`check.ts` / codegen); no import needed for `exit(1)` in a standalone E2E script—verify once when adding that file.
- Positive E2E under `tests/e2e/scenarios/positive/` is **not** expanded by this story; only **document** it via README/spec updates above.
- Reference implementations for **non-exhaustive match** live under `tests/conformance/typecheck/invalid/non_exhaustive_*.ks` — E2E files should be minimal standalone programs, not copies of conformance text, unless sharing a pattern helps.

## Build notes

- 2026-03-29: Promoted from **planned** to **doing** after planned exit criteria pass: impact analysis includes docs; tasks include implementation + doc/spec + README fixes; **Tests to add** covers E2E files, harness regression, CI scripts, and explicit **not required** rows for Vitest/unit/VM/JVM; **Documentation and specs** lists 08-tests, both E2E READMEs, 09-tools, AGENTS. Story content updated for repo accuracy (`uncaught_exception.ks` = div-by-zero, `tests/e2e/README.md` stale, VM-only negative E2E).
- 2026-03-29: **Completed.** Added ten negative scenarios + `_fixtures/` for duplicate export; replaced `uncaught_exception.ks` with `uncaught_throw.ks` and `runtime_divide_by_zero.ks`; harness uses `E2E_EXPECT_STACK_TRACE` and accepts uncaught-exception, operand-stack, or call-depth stderr shapes. **ADT runtime bucket:** implemented as `runtime_catch_no_match_rethrow.ks` (catch pattern mismatch → rethrow). Updated `08-tests.md`, `09-tools.md`, `AGENTS.md`, both E2E READMEs; adjusted cross-ref in done story **50**. Verification: `./scripts/run-e2e.sh`, `cd compiler && npm run build && npm test`, `cd vm && zig build test`, `./scripts/kestrel test`, `./scripts/kestrel test --target jvm`, `./scripts/test-all.sh`.
