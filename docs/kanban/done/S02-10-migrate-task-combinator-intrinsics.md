# Migrate `task.ks` Task Combinator Intrinsics to `extern fun`

## Sequence: S02-10
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/done/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01, S02-02, S02-03, S02-04, S02-05, S02-06, S02-07, S02-08, S02-09, S02-11, S02-12, S02-13

## Summary

Replace the four task combinator intrinsics in `stdlib/kestrel/task.ks` — `__task_map`, `__task_all`, `__task_race`, and `__task_cancel` — with `extern fun` declarations bound to the `KTask` static methods. All four involve `Task<T>` types in their signatures, making them a comprehensive test of async extern fun and parametric extern fun support.

## Current State

**Four intrinsics in `task.ks`:**
- `__task_map(task: Task<A>, f: A -> B): Task<B>` → `KTask.taskMap(Object,Object): KTask`
- `__task_all(tasks: List<Task<T>>): Task<List<T>>` → `KTask.taskAll(Object): KTask`
- `__task_race(tasks: List<Task<T>>): Task<T>` → `KTask.taskRace(Object): KTask`
- `__task_cancel(t: Task<T>): Unit` → `KTask.cancel(Object): void`

**Current `task.ks`:**
```kestrel
export fun map<A, B>(task: Task<A>, f: A -> B): Task<B>   = __task_map(task, f)
export fun all<T>(tasks: List<Task<T>>): Task<List<T>>     = __task_all(tasks)
export fun race<T>(tasks: List<Task<T>>): Task<T>          = __task_race(tasks)
export fun cancel<T>(t: Task<T>): Unit                     = __task_cancel(t)
```

**`codegen.ts`** (lines ~1795–1815): four dispatch blocks. `__task_cancel` calls `KTask.cancel()` which returns void and requires pushing `KUnit`.
**`check.ts`**: four `env.set` bindings with parametric types using fresh type variables.

**JVM targets**: `KTask.taskMap`, `KTask.taskAll`, `KTask.taskRace`, `KTask.cancel` — all static methods on the `KTask` class in `runtime/jvm/src/kestrel/runtime/KTask.java`.

## Relationship to other stories

- **Depends on S02-02**: requires non-parametric extern fun for the dispatch infrastructure.
- **Depends on S02-03**: `map<A, B>`, `all<T>`, `race<T>`, `cancel<T>` are all parametric — they require parametric extern fun support.
- **Also requires async extern fun**: `map`, `all`, `race` all return `Task<T>`. Same blocker as S02-08 and S02-09.
- **Independent of S02-04 through S02-09** (other migration stories).

## Goals

1. Replace each wrapper in `task.ks` with a parametric `extern fun`:
   ```kestrel
   export extern fun map<A, B>(task: Task<A>, f: A -> B): Task<B> =
     jvm("kestrel.runtime.KTask#taskMap(java.lang.Object,java.lang.Object)")

   export extern fun all<T>(tasks: List<Task<T>>): Task<List<T>> =
     jvm("kestrel.runtime.KTask#taskAll(java.lang.Object)")

   export extern fun race<T>(tasks: List<Task<T>>): Task<T> =
     jvm("kestrel.runtime.KTask#taskRace(java.lang.Object)")

   export extern fun cancel<T>(t: Task<T>): Unit =
     jvm("kestrel.runtime.KTask#cancel(java.lang.Object)")
   ```
2. Remove the four `if (name === '__task_*') { ... }` blocks from `codegen.ts`.
3. Remove the four `env.set('__task_*', ...)` bindings from `check.ts`.
4. Grep for remaining `__task_map`, `__task_all`, `__task_race`, `__task_cancel` usage; fix any found.

## Acceptance Criteria

- [x] `stdlib/kestrel/task.ks` contains no `__task_map`, `__task_all`, `__task_race`, or `__task_cancel` calls.
- [x] Four `extern fun` declarations exist in `task.ks`.
- [x] `codegen.ts` has no dispatch blocks for these four intrinsics.
- [x] `check.ts` has no `env.set` bindings for these four intrinsics.
- [x] `stdlib/kestrel/task.test.ks` passes.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/02-stdlib.md` — `kestrel:task` module: no API change.

## Risks / Notes

- **`__task_cancel` returns `void`**: `KTask.cancel()` returns void. The current codegen emits `INVOKESTATIC KTask.cancel(Object)V` then `GETSTATIC KUnit.INSTANCE`. The `extern fun` must declare `Unit` as return type and the codegen must handle the void-returning method → push KUnit pattern (same as `print` in S02-07).
- **Type parameter variance**: `task_all` has a tricky type: `List<Task<T>> → Task<List<T>>`. The parametric extern fun must declare `<T>` and use it in both the parameter and return types. The typecheck should unify correctly, but the JVM codegen just calls the method — the type parameter is purely for Kestrel-side type safety, invisible at runtime.
- **`cancel` type parameter `T` is unused in the body**: `cancel<T>(t: Task<T>): Unit` — the type parameter `T` appears only to satisfy the call site type. Parametric extern funs with unconstrained type parameters that are only used in input positions (not output) should be fine with HM inference. But confirm that the typecheck does not generalize `cancel` in a way that prevents correct call-site type checking.
- **KTask vs. KRuntime**: task combinators are on `KTask`, not `KRuntime`. The existing codegen already uses `K_TASK` constant for this. The extern fun `jvm("...")` descriptor must reference `kestrel.runtime.KTask`, not `kestrel.runtime.KRuntime`.

## Impact Analysis

- `stdlib/kestrel/task.ks`: replace 4 wrapper funs with `export extern fun` declarations.
- `compiler/src/typecheck/check.ts`: remove 4 `env.set` blocks (and associated fresh vars).
- `compiler/src/jvm-codegen/codegen.ts`: remove 4 intrinsic dispatch blocks.

## Tasks

- [x] Replace 4 intrinsic wrapper funs with `extern fun` declarations in `task.ks`
- [x] Remove 4 `env.set` bindings from `check.ts` (and 4 associated `freshVar()` calls)
- [x] Remove 4 intrinsic dispatch blocks from `codegen.ts`
- [x] Verify `emitExternReturnAsObject` handles `Unit`/void return for `cancel`
- [x] Verify no remaining `__task_*` intrinsic refs in compiler/stdlib

## Tests to add

- No new test files needed — `task.test.ks` exercises the API; existing tests cover behaviour.

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md`: update `kestrel:task` implementation notes to reference new `extern fun` names.

## Build notes

- 2025-07-14: All four task intrinsics replaced cleanly. `emitExternReturnAsObject` already handles `Unit` return for `cancel` (void JVM method → push `KUnit.INSTANCE`). `all` and `race` return `Task<T>` so `externReturnDescriptorForType` returns `KTask` correctly. 257 compiler tests and 1014 Kestrel tests pass.
