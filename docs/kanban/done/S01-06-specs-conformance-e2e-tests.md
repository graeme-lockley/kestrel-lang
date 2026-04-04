# Spec Updates, Conformance, and E2E Tests

## Sequence: S01-06
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none — split from original S01-01)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/done/E01-async-runtime-foundation.md)
- Companion stories: S01-01, S01-02, S01-03, S01-04, S01-05, S01-07, S01-08, S01-09

## Summary

Final story in the async foundation epic. Update all relevant specs to reflect the Project Loom-based async model, add conformance tests exercising real suspension and concurrent tasks, and add E2E scenarios that verify end-to-end async behavior. This story ensures the implementation from S01-01 through S01-05 is fully documented, tested, and regression-safe.

## Current State

After S01-01 through S01-05:
- KTask runtime class exists, backed by `CompletableFuture`.
- Virtual thread executor dispatches async function bodies.
- File I/O runs on virtual threads with `Result<T, FsError>` error handling.
- CLI `--exit-wait` / `--exit-no-wait` flags control process lifetime.
- Individual story tests pass, but comprehensive conformance and cross-cutting E2E coverage is incomplete.
- Specs may still describe the old synchronous placeholder behavior.

## Relationship to other stories

- **Depends on S01-01 through S01-05**: All implementation stories must be complete.
- **Final story in Epic E01**: Completing this story means the epic can move to done.
- **Foundation for Epic E03**: HTTP/networking stories assume specs and async behavior are documented.

## Goals

1. **Spec accuracy**: Every spec that mentions async, Task, await, or async I/O reflects the Project Loom implementation.
2. **Conformance coverage**: Runtime conformance tests verify real task suspension, concurrent completion, and Result error handling.
3. **E2E scenarios**: At least one positive E2E scenario demonstrates concurrent async file I/O with order-independent assertions.
4. **Negative E2E**: At least one negative scenario verifies that `await` outside an async context is a compile error.
5. **Regression safety**: All existing test suites remain green with the updated specs and new tests.
6. **No completion-order dependence**: All async tests assert outcomes independent of which task completes first.

## Acceptance Criteria

- [x] `docs/specs/01-language.md` §5 updated: describes Project Loom virtual threads, `KTask` runtime representation, `await` blocking semantics on virtual threads.
- [x] `docs/specs/02-stdlib.md` updated: `readText` signature is `Task<Result<String, FsError>>`, error ADT documented.
- [x] `docs/specs/06-typesystem.md` updated: `Task<T>`, `Result<A, E>` composition documented for async surfaces.
- [x] `docs/specs/09-tools.md` updated: `--exit-wait` / `--exit-no-wait` documented under `kestrel run`.
- [x] `tests/conformance/runtime/valid/async_await.ks` updated or extended: tests real `await` that blocks, concurrent tasks, and Result unwrapping.
- [x] New conformance test(s) for `Task<Result<T, E>>` type checking and pattern matching.
- [x] `tests/e2e/scenarios/positive/` includes a scenario with concurrent async file reads, assertions on aggregated outcomes only.
- [x] `tests/e2e/scenarios/negative/` includes a scenario for `await` outside async context (compile error).
- [x] No test asserts completion order of independent async tasks.
- [x] All suites pass: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`, `./scripts/run-e2e.sh`.

## Spec References

- `docs/specs/01-language.md` §5 (Async and Task model)
- `docs/specs/02-stdlib.md` (filesystem API, error types)
- `docs/specs/06-typesystem.md` (`Task`, `Result`, ADTs)
- `docs/specs/08-tests.md` (async testing expectations)
- `docs/specs/09-tools.md` (CLI flags)

## Risks / Notes

- **Spec coherence**: Multiple specs reference async behavior. A single pass through all of them is needed to ensure consistency. Do not update specs piecemeal — review them together.
- **Conformance test design**: Tests must not rely on `Thread.sleep` or timing tricks. Use file I/O (or other observable operations) and assert on final values.
- **E2E test patterns**: Positive E2E tests write `.expected` files with the expected stdout. Design the async scenario so stdout output is deterministic regardless of completion order (e.g. sort results before printing, or use a single aggregated assertion).
- **Spec removals**: Remove or footnote the old "`readFileAsync` may complete synchronously on the reference VM" escape hatch — it no longer applies with Loom.

## Impact analysis

| Area | Change |
|------|--------|
| Specs | Update async/task semantics and CLI flags in `docs/specs/01-language.md`, `docs/specs/02-stdlib.md`, `docs/specs/06-typesystem.md`, `docs/specs/08-tests.md`, and `docs/specs/09-tools.md` so all async behavior reflects the Loom + `Task<Result<...>>` model consistently. |
| Conformance runtime | Extend `tests/conformance/runtime/valid/async_await.ks` to assert both awaited task behavior and `Task<Result<T, E>>` unwrapping through pattern matching. |
| Conformance typecheck | Add a new `tests/conformance/typecheck/valid/*.ks` scenario that validates `await` typing for `Task<Result<T, E>>` and legal pattern matching over `Ok`/`Err`. |
| E2E positive | Ensure `tests/e2e/scenarios/positive/` includes a concurrent async file-read scenario with deterministic aggregated assertions only (no completion-order assumptions). |
| E2E negative | Add a negative `tests/e2e/scenarios/negative/*.ks` scenario that verifies `await` outside async context is rejected at compile time. |
| E2E docs | Update `tests/e2e/scenarios/negative/README.md` to include the new negative scenario in the canonical list. |
| Verification | Run `cd compiler && npm run build && npm test`, `./scripts/kestrel test`, and `./scripts/run-e2e.sh` to confirm no regressions. |

## Tasks

- [x] Update `docs/specs/02-stdlib.md` async sections to remove stale pre-Result wording and keep fs/process/list module contracts coherent.
- [x] Update `docs/specs/01-language.md`, `docs/specs/06-typesystem.md`, `docs/specs/08-tests.md`, and `docs/specs/09-tools.md` with any required async-model consistency fixes discovered during the pass.
- [x] Extend `tests/conformance/runtime/valid/async_await.ks` to cover awaited `Task<Result<...>>` pattern handling alongside existing await behavior.
- [x] Add a new valid typecheck conformance case under `tests/conformance/typecheck/valid/` for `Task<Result<T, E>>` await + match typing.
- [x] Add a new negative E2E scenario under `tests/e2e/scenarios/negative/` for `await` outside async context.
- [x] Update `tests/e2e/scenarios/negative/README.md` to document the new negative scenario.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.
- [x] Run `./scripts/run-e2e.sh`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance runtime | `tests/conformance/runtime/valid/async_await.ks` | Assert async `await` behavior with a `Task<Result<T, E>>` payload and deterministic result matching. |
| Conformance typecheck | `tests/conformance/typecheck/valid/async_task_result_match.ks` | Ensure `await` on `Task<Result<T, E>>` infers `Result<T, E>` and match arms typecheck. |
| E2E negative | `tests/e2e/scenarios/negative/compile_await_outside_async.ks` | Ensure `await` outside async context fails compile in the full E2E harness. |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — confirm async/await runtime semantics reference virtual-thread-backed `Task` execution and blocking `await` behavior.
- [x] `docs/specs/02-stdlib.md` — document fs/process async `Task<Result<...>>` contracts without stale pre-Result caveats.
- [x] `docs/specs/06-typesystem.md` — confirm `Task<Result<...>>` typing examples and JVM async model wording are consistent.
- [x] `docs/specs/08-tests.md` — ensure async conformance guidance includes no completion-order dependence for independent tasks.
- [x] `docs/specs/09-tools.md` — confirm `kestrel run` exit mode flags documentation remains accurate.

## Notes

- This story is documentation and test focused; no compiler/runtime behavior changes are planned unless verification exposes an inconsistency.

## Build notes

- 2026-04-03: Started implementation from `doing/` after adding full planning sections in `planned/`.
- 2026-04-03: `docs/specs/02-stdlib.md` had mixed module sections (fs/process/list plus stale legacy fs contract). Normalized to a single coherent async contract (`Task<Result<...>>`) to keep spec references internally consistent.
- 2026-04-03: Added a dedicated E2E compile-failure scenario for `await` outside async context even though conformance already covered it, because this story requires explicit E2E coverage.
- 2026-04-03: Initial `async-concurrent-read-aggregate.ks` used inline arithmetic over match expressions and triggered a JVM verifier type-shape mismatch. Rewrote to explicit `Int` temporaries (`leftLen`, `rightLen`, `leftOk`, `rightOk`) to keep assertions deterministic while avoiding backend-specific expression-shape hazards.
