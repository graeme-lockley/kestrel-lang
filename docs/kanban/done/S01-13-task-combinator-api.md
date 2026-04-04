# Task Combinator API (`all`, `race`, `map`)

## Sequence: S01-13
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)

## Summary

The only concurrency pattern currently available in Kestrel is "start tasks before any `await`, then await sequentially". There is no typed API for fan-out over a dynamic collection, racing tasks, or transforming a task's value without awaiting it. This story adds `Task.all`, `Task.race`, and `Task.map` combinators to the stdlib and JVM runtime, enabling idiomatic structured concurrency patterns.

## Current State

- `KTask` exposes only `get()` (blocking await).
- No stdlib module provides task combinators.
- Parallel fan-out over a `List<Task<T>>` requires manually iterating with `await` in a loop — sequential, not concurrent.
- The type `Task<T>` is first-class, but cannot be composed without explicit `await`.

## Relationship to other stories

- Depends on S01-01 (KTask runtime class).
- S01-17 (cancellation) is a natural follow-on — `race` should cancel the losers.
- E03 (HTTP/networking) will benefit directly from `Task.all` for parallel HTTP requests.

## Goals

1. **`Task.map`** — transform the result of a task without blocking: `Task.map(t, f)` returns a new `Task<B>` that applies `f` when `t` completes. No virtual thread needed (pure transform on the `CompletableFuture`).
2. **`Task.all`** — wait for all tasks in a `List<Task<T>>` to complete and collect results into `Task<List<T>>`. Fails fast if any task fails.
3. **`Task.race`** — return the result of the first task in a `List<Task<T>>` to complete. Remaining tasks continue running (or are cancelled if S01-17 is done).
4. Stdlib module `kestrel:task` (or additions to a suitable existing module) exposes these combinators.
5. The type checker and codegen support `Task` as a parameterised type argument to these functions.

## Acceptance Criteria

- `Task.map(t, f)` compiles, returns a `Task<B>`, and the mapped value is correct when awaited.
- `Task.all(tasks)` collects all results; if any task fails the outer task fails.
- `Task.race(tasks)` returns the first-completing value.
- At least one conformance or unit test exercises each combinator.
- `cd compiler && npm test` and `./scripts/kestrel test` pass.

## Spec References

- `docs/specs/01-language.md` §5 (async semantics) — add combinator descriptions.
- `docs/specs/02-stdlib.md` — add `kestrel:task` module section.

## Risks / Notes

- `Task.all` and `Task.race` accept `List<Task<T>>` — this requires the type checker to handle polymorphic list iteration over a parameterised type. Verify that the existing generic machinery handles `List<Task<T>>` without extra work.
- `Task.race` semantics when the list is empty need a defined behaviour (e.g. reject with an error or return `Task<Option<T>>`).
- Cancellation of losing tasks in `race` is deferred to S01-17; document this in the spec.

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime `KTask.java` | Add `taskMap(Object, Object): KTask`, `taskAll(Object): KTask`, `taskRace(Object): KTask` static methods |
| Type checker `check.ts` | Register `__task_map`, `__task_all`, `__task_race` polymorphic intrinsics |
| JVM codegen `codegen.ts` | Emit `INVOKESTATIC KTask.taskMap/taskAll/taskRace` for each new intrinsic |
| Module resolver `resolve.ts` | Add `'kestrel:task'` to `STDLIB_NAMES` |
| Stdlib `task.ks` | New file: `map`, `all`, `race` wrappers over the three intrinsics |
| Tests | Conformance runtime test + Kestrel unit test |
| Spec | `docs/specs/01-language.md` §5, `docs/specs/02-stdlib.md` |

## Tasks

- [x] In `runtime/jvm/src/kestrel/runtime/KTask.java`: add `taskMap(Object taskObj, Object fn): KTask`, `taskAll(Object listObj): KTask`, `taskRace(Object listObj): KTask` static methods
- [x] In `compiler/src/typecheck/check.ts`: register `__task_map` (forall A B. (Task<A>, A->B) -> Task<B>), `__task_all` (forall T. List<Task<T>> -> Task<List<T>>), `__task_race` (forall T. List<Task<T>> -> Task<T>) intrinsics
- [x] In `compiler/src/jvm-codegen/codegen.ts`: add codegen for `__task_map` (2 args → `KTask.taskMap`), `__task_all` (1 arg → `KTask.taskAll`), `__task_race` (1 arg → `KTask.taskRace`)
- [x] In `compiler/src/resolve.ts`: add `'kestrel:task'` to `STDLIB_NAMES`
- [x] Create `stdlib/kestrel/task.ks` with exported `map`, `all`, `race` functions
- [x] Add conformance runtime test `tests/conformance/runtime/valid/task_combinators.ks`
- [x] Run `cd runtime/jvm && bash build.sh`
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`
- [x] Run `./scripts/run-e2e.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance runtime | `tests/conformance/runtime/valid/task_combinators.ks` | `map` transforms result, `all` collects list, `race` returns first |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` §5 — add combinator descriptions
- [x] `docs/specs/02-stdlib.md` — add `kestrel:task` module section

## Build notes

- 2026-03-07: `KTask.java` methods placed on the `KTask` class itself (not `KRuntime`) because `future` is private and same-class access is cleaner. Codegen uses `K_TASK` constant (already defined as `'kestrel/runtime/KTask'`).
- 2026-03-07: `KCons` constructor requires `KList tail` not `Object`; fixed by using `KList list` typed variable in `taskAll`.
- 2026-03-07: `Task.completed()` is not a Kestrel-visible function (internal to JVM runtime); conformance test uses a small `async fun mkInt` to produce tasks.
- 2026-03-07: Tests verified: `npm test` 231/231, `./scripts/kestrel test` 1011/1011, `./scripts/run-e2e.sh` 10/10.
