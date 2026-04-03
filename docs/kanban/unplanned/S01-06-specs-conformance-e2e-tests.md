# Spec Updates, Conformance, and E2E Tests

## Sequence: S01-06
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none — split from original S01-01)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)
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
- **Foundation for Epic E02**: HTTP/networking stories assume specs and async behavior are documented.

## Goals

1. **Spec accuracy**: Every spec that mentions async, Task, await, or async I/O reflects the Project Loom implementation.
2. **Conformance coverage**: Runtime conformance tests verify real task suspension, concurrent completion, and Result error handling.
3. **E2E scenarios**: At least one positive E2E scenario demonstrates concurrent async file I/O with order-independent assertions.
4. **Negative E2E**: At least one negative scenario verifies that `await` outside an async context is a compile error.
5. **Regression safety**: All existing test suites remain green with the updated specs and new tests.
6. **No completion-order dependence**: All async tests assert outcomes independent of which task completes first.

## Acceptance Criteria

- [ ] `docs/specs/01-language.md` §5 updated: describes Project Loom virtual threads, `KTask` runtime representation, `await` blocking semantics on virtual threads.
- [ ] `docs/specs/02-stdlib.md` updated: `readText` signature is `Task<Result<String, FsError>>`, error ADT documented.
- [ ] `docs/specs/06-typesystem.md` updated: `Task<T>`, `Result<A, E>` composition documented for async surfaces.
- [ ] `docs/specs/09-tools.md` updated: `--exit-wait` / `--exit-no-wait` documented under `kestrel run`.
- [ ] `tests/conformance/runtime/valid/async_await.ks` updated or extended: tests real `await` that blocks, concurrent tasks, and Result unwrapping.
- [ ] New conformance test(s) for `Task<Result<T, E>>` type checking and pattern matching.
- [ ] `tests/e2e/scenarios/positive/` includes a scenario with concurrent async file reads, assertions on aggregated outcomes only.
- [ ] `tests/e2e/scenarios/negative/` includes a scenario for `await` outside async context (compile error).
- [ ] No test asserts completion order of independent async tasks.
- [ ] All suites pass: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`, `./scripts/run-e2e.sh`.

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
