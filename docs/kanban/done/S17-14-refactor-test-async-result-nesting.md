# Refactor deep async-Result nesting in driver tests using combinators

## Sequence: S17-14

## Tier: Optional

## Former ID: S17-15

## Epic

[E17 — True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)

## Summary

Every `asyncGroup` in `driver.test.ks` that does filesystem setup (mkdirAll, writeText) uses
deeply nested `match (await ...)` chains — up to five levels deep. The nesting makes it hard to
read what the test actually asserts and obscures which setup step failed when a test does fail.

The fix has two parts:

1. Add an `andThenAsync` combinator to `kestrel:data/result` that async-flat-maps a
   `Task<Result<T, E>>` — the missing piece needed to pipeline `Task<Result>` operations
   with `|>`.
2. Add a `mapErrorAsync` combinator (also to `kestrel:data/result`) that transforms the error
   inside a `Task<Result>` without awaiting it — used to label each setup step so the error
   branch carries the name of the failing step.
3. Refactor all matching deep-nesting occurrences in `driver.test.ks` (and any other test
   files in `stdlib/`) to the two-level form: a flat `|>` pipeline for setup, followed by a
   single `match` that runs the assertions on `Ok` or fails with the labelled error message.

## Current State

`stdlib/kestrel/tools/compiler/driver.test.ks` contains at least 10 `asyncGroup` blocks where
filesystem setup is expressed as 3–5 nested `match (await ...)` expressions. The error arms all
call `isTrue(sg, "...", False)` but lose context about which step failed because the match arms
are anonymous.

No `andThenAsync` or `mapErrorAsync` combinator exists in the stdlib yet.

## Relationship to other stories

- Depends on S17-01 through S17-14 (those stories introduced the test file being refactored).
- Pure quality / maintainability story; no behaviour change.

## Goals

- Add `andThenAsync` and `mapErrorAsync` to `kestrel:data/result`.
- Eliminate all instances of 3+-level `match (await ...)` nesting in stdlib test files that
  match the setup-then-assert pattern.
- After refactor: every failing setup step surfaces its label as the test failure message
  rather than a generic `False`.

## Acceptance Criteria

- [x] `kestrel:data/result` exports `andThenAsync` and `mapErrorAsync`.
- [x] All `asyncGroup` blocks in `driver.test.ks` that previously used 3+ levels of nested
  `match (await ...)` for filesystem setup are refactored to the flat `|>` pipeline form with
  a single `match` at the end.
- [x] Any other stdlib test files with the same pattern are also refactored.
- [x] `result.test.ks` includes tests for both new combinators.
- [x] All existing tests continue to pass: `./kestrel test` and `cd compiler && npm test`.
- [x] No behaviour change to any test's assertion logic — only the setup structure changes.

## Spec References

- `docs/specs/02-stdlib.md` — `kestrel:data/result` module public API.

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib — `stdlib/kestrel/data/result.ks` | Add two new exported async functions: `andThenAsync` and `mapErrorAsync`. No existing functions changed. Pure additive; rollback risk: none. |
| Stdlib — `stdlib/kestrel/data/result.test.ks` | Add a new test group `andThenAsync mapErrorAsync` covering the two new combinators. |
| Stdlib — `stdlib/kestrel/tools/compiler/driver.test.ks` | Refactor every `asyncGroup` that uses 3+-level `match (await …)` nesting for filesystem setup into the flat `|>` pipeline form. A single shared `label` helper is defined at file top. No assertion logic changes. |
| Docs/Specs — `docs/specs/02-stdlib.md` | Add `andThenAsync` and `mapErrorAsync` rows to the `kestrel:data/result` table. |
| Compiler / JVM codegen / JVM runtime | No changes. The new functions are pure Kestrel `async fun` definitions; no new opcodes or intrinsics required. |
| Risk: type inference | `andThenAsync` returns `Task<Result<U, E>>` and is itself an `async fun`. The Kestrel type checker must correctly infer the return type. Verified by running `./kestrel test` after implementation. |
| Risk: `Task.map` import | `mapErrorAsync` delegates to `Task.map` from `kestrel:sys/task`. Must add this import to `result.ks`. |

## Tasks

- [x] In `stdlib/kestrel/data/result.ks`: add `import * as Task from "kestrel:sys/task"` and implement `andThenAsync` and `mapErrorAsync` exports.
- [x] In `stdlib/kestrel/data/result.test.ks`: add import of `andThenAsync` and `mapErrorAsync` and a test group exercising both.
- [x] In `stdlib/kestrel/tools/compiler/driver.test.ks`: define `label` helper at file top; refactor all `asyncGroup` blocks with 3+-level `match (await …)` filesystem setup to the flat `|>` pipeline pattern.
- [x] Update `docs/specs/02-stdlib.md` — add `andThenAsync` and `mapErrorAsync` rows to the `kestrel:data/result` table.
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/data/result.test.ks` | `andThenAsync Ok` — async-flat-maps a `Task<Result<T,E>>` when inner is `Ok`; result is `Ok(newValue)` |
| Kestrel harness | `stdlib/kestrel/data/result.test.ks` | `andThenAsync Err propagation` — `Err` is propagated unchanged without calling `f` |
| Kestrel harness | `stdlib/kestrel/data/result.test.ks` | `mapErrorAsync Ok` — `Ok` is propagated unchanged |
| Kestrel harness | `stdlib/kestrel/data/result.test.ks` | `mapErrorAsync Err` — maps the error value inside `Task<Result<T,E>>` |

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md` — add `andThenAsync` and `mapErrorAsync` rows to the `kestrel:data/result` table.

## Risks / Notes

- `andThenAsync` is an async function; the Kestrel type checker must correctly infer
  `Task<Result<U, E>>` as its return type — verify this compiles cleanly.
- `mapErrorAsync` delegates to `Task.map` (from `kestrel:sys/task`) — ensure the import is
  present in `result.ks`.
## Build notes

- 2026-04-27: Started implementation.
- 2026-04-27: Refactored all 21 asyncGroups in driver.test.ks. Mid-test writes (stale KTI, cascade, depHashes) kept as nested match since they're not setup chains. `label` helper is a plain `fun` (not `async`), since `mapErrorAsync` already returns `Task`. Test helpers for result.test.ks use named `async fun` declarations (Kestrel doesn't support IIFE async lambda syntax). Pre-existing 2 depHashes failures confirmed not caused by this story.

- The canonical two-level form is:
  ```kestrel
  fun label<T>(lbl: String, task: Task<Result<T, Fs.FsError>>): Task<Result<T, String>> =
    Res.mapErrorAsync(task, (_) => lbl)

  val setup =
    label("mkdirAll src failed",  Fs.mkdirAll(srcDir))
    |> Res.andThenAsync((_) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
    |> Res.andThenAsync((_) => label("writeText failed",    Fs.writeText(srcPath, src)))

  match (await setup) {
    Err(msg) => isTrue(sg, msg, False)
    Ok(())   => { /* assertions */ }
  }
  ```
- A shared `label` helper (or equivalent inline `mapErrorAsync` call) should be defined once
  at the top of each test file that uses it, not duplicated per group.
