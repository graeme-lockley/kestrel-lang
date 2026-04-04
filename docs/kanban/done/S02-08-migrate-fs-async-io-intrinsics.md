# Migrate `fs.ks` Async I/O Intrinsics to `extern fun`

## Sequence: S02-08
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/done/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01, S02-02, S02-03, S02-04, S02-05, S02-06, S02-07, S02-09, S02-10, S02-11, S02-12, S02-13

## Summary

Replace the three async I/O intrinsics in `stdlib/kestrel/fs.ks` — `__read_file_async`, `__list_dir`, `__write_text` — with `extern fun` declarations bound to the corresponding `KRuntime` static methods. These intrinsics are special because they return `Task<T>` rather than a plain value; the `extern fun` codegen must emit a `KTask`-returning call (using `taskDescriptor` rather than `descriptor`). This is the first migration story that exercises async extern funs.

## Current State

**Three intrinsics in `fs.ks`:**
- `__read_file_async(path: String): Task<Result<String, String>>` → `KRuntime.readFileAsync(Object): KTask`
- `__list_dir(path: String): Task<Result<List<String>, String>>` → `KRuntime.listDirAsync(Object): KTask`
- `__write_text(path: String, content: String): Task<Result<Unit, String>>` → `KRuntime.writeTextAsync(Object,Object): KTask`

**Current `fs.ks` usage (inside `async fun` with `await`):**
```kestrel
val result = await __read_file_async(path)
val result = await __list_dir(path)
val result = await __write_text(path, content)
```

**`codegen.ts`** (lines ~1745–1762): special handling — uses `taskDescriptor` not `descriptor` because the return type is `KTask`.

**`check.ts`**: three `env.set('__read_file_async', ...)`, `env.set('__list_dir', ...)`, `env.set('__write_text', ...)` bindings with `Task<Result<...>>` return types.

## Relationship to other stories

- **Depends on S02-02**: requires `extern fun` in parser/typecheck/codegen.
- **Critical gap**: S02-02 (non-parametric extern fun) must handle the async case — `extern fun` that returns `Task<T>`. The S02-02 story marks this as out of scope ("Async extern funs are out of scope for this story"). This creates a **hard blocker**: S02-08 cannot be implemented until async `extern fun` support is added, either as an extension of S02-02 or as a separate story. This dependency must be resolved before S02-08 is planned.
- **Independent of S02-04, S02-05, S02-06, S02-07, S02-09, S02-10** (other migration stories).

## Goals

1. Extend `extern fun` codegen (if not already done in S02-02) to handle `Task<T>` return types: when the declared Kestrel return type is `Task<X>`, the JVM call must use `taskDescriptor(arity)` (return type `Lkestrel/runtime/KTask;`) instead of `descriptor(arity)` (return type `Ljava/lang/Object;`).
2. Replace each intrinsic in `fs.ks` with a direct `extern fun`:
   ```kestrel
   extern fun readFileAsync(path: String): Task<Result<String, String>> =
     jvm("kestrel.runtime.KRuntime#readFileAsync(java.lang.Object)")

   extern fun listDir(path: String): Task<Result<List<String>, String>> =
     jvm("kestrel.runtime.KRuntime#listDirAsync(java.lang.Object)")

   extern fun writeText(path: String, content: String): Task<Result<Unit, String>> =
     jvm("kestrel.runtime.KRuntime#writeTextAsync(java.lang.Object,java.lang.Object)")
   ```
3. Update `fs.ks` `async fun` bodies to call the new `extern fun` names instead of `__*` intrinsics.
4. Remove the three `if (name === '__read_file_async' | '__list_dir' | '__write_text') { ... }` blocks from `codegen.ts`.
5. Remove the three `env.set` bindings from `check.ts`.

## Acceptance Criteria

- [x] `stdlib/kestrel/fs.ks` contains no `__read_file_async`, `__list_dir`, or `__write_text` calls.
- [x] Three `extern fun` declarations for async I/O exist in `fs.ks`.
- [x] `extern fun` emits `invokestatic` with `KTask`-returning descriptor (not `Object`-returning) for `Task<T>` return types.
- [x] `await` on the result of an async extern fun works correctly (the `KTask` is properly unwrapped).
- [x] `codegen.ts` has no `name === '__read_file_async'`, `name === '__list_dir'`, or `name === '__write_text'` blocks.
- [x] `check.ts` has no `env.set` bindings for these three intrinsics.
- [x] `stdlib/kestrel/fs.test.ks` passes.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/fs.ks` | Add 3 `extern fun` declarations; update 3 async fun bodies to use new names instead of `__*` intrinsics |
| `compiler/src/typecheck/check.ts` | Remove `env.set('__read_file_async', ...)`, `env.set('__list_dir', ...)`, `env.set('__write_text', ...)` |
| `compiler/src/jvm-codegen/codegen.ts` | Remove 3 `if (name === '__read_file_async'|'__list_dir'|'__write_text'...)` dispatch blocks |
| Tests | No new tests — existing `stdlib/kestrel/fs.test.ks` covers all three paths |
| Specs | `docs/specs/02-stdlib.md` — implementation note only; public API unchanged |

## Tasks

- [x] Add 3 `extern fun` declarations to `stdlib/kestrel/fs.ks` and update async fun bodies
- [x] Remove 3 `env.set` intrinsic entries from `compiler/src/typecheck/check.ts`
- [x] Remove 3 dispatch blocks from `compiler/src/jvm-codegen/codegen.ts`
- [x] Verify no stray `__read_file_async`, `__list_dir`, `__write_text` references remain
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/fs.test.ks` (existing) | Already covers readText/listDir/writeText; no new tests required |

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md` — update `kestrel:fs` section (no intrinsic references existed)

## Build notes

- 2025-06-11: Implemented. Async extern funs work without any codegen changes — `externReturnDescriptorForType` already handles `Task<T>` → `KTask`, and `asyncFunNames` propagation is already in place. All 257 compiler tests and 1014 Kestrel tests pass.


- **Async `extern fun` is the key technical challenge**: the existing codegen distinguishes sync (`descriptor`/`Ljava/lang/Object;`) from async (`taskDescriptor`/`Lkestrel/runtime/KTask;`) calls. `ExternFunDecl` must propagate this distinction. The simplest approach: if the Kestrel return type of an `extern fun` is `Task<X>`, codegen uses `taskDescriptor`. This mirrors how `async FunDecl` functions already work.
- **No `async extern fun` keyword needed**: unlike regular Kestrel `async fun`, the distinction for extern funs is entirely in the return type annotation (`Task<T>` vs. `T`). The `extern` keyword does not need an `async` modifier. This is cleaner than adding `async extern fun` syntax.
- **`await` on extern fun result**: the `await` expression in `fs.ks` already expects a `KTask` on the stack (via `KTask.get()`). As long as the extern fun codegen emits the `KTask`-returning invokestatic, the existing `await` emission continues to work unchanged.
- **Result types**: `Task<Result<List<String>, String>>` involves nested generic types. Typecheck must be able to resolve these reference types in a `extern fun` signature (all involved types are Kestrel builtins, not extern types, so this should work out of the box with S02-02/S02-03 typecheck support).
