# Migrate `process.ks` Process/Environment Intrinsics to `extern fun`

## Sequence: S02-09
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/unplanned/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01, S02-02, S02-03, S02-04, S02-05, S02-06, S02-07, S02-08, S02-10, S02-11, S02-12, S02-13

## Summary

Replace the four process and environment intrinsics used in `stdlib/kestrel/process.ks` — `__get_os`, `__get_args`, `__get_cwd`, and `__run_process` — with `extern fun` declarations. `__run_process` is async (returns `Task<Result<...>>`), the rest are synchronous. Remove the corresponding dispatch blocks from `codegen.ts` and bindings from `check.ts`.

## Current State

**Four intrinsics in `process.ks`:**
- `__get_os(): String` → `KRuntime.getOs(): String`
- `__get_args(): List<String>` → `KRuntime.getArgs(): KList`
- `__get_cwd(): String` → `KRuntime.getCwd(): String`
- `__run_process(program: String, args: List<String>): Task<Result<..., String>>` → `KRuntime.runProcessAsync(Object,Object): KTask`

**Note**: `__now_ms(): Int` is also a "process/time" intrinsic but lives in `basics.ks` — it is handled in S02-06, not here.

**Current `process.ks` usage:**
```kestrel
val os = __get_os();
val a = __get_args();
val c = __get_cwd();
map(__run_process(program, args), ...)
```

**`codegen.ts`** (lines ~1763–1795): four separate dispatch blocks.
**`check.ts`**: four `env.set` bindings.

## Relationship to other stories

- **Depends on S02-02**: requires non-parametric `extern fun`.
- **`__run_process` depends on async `extern fun` support**: same blocker as S02-08. Must be resolved before this story can be fully planned.
- **Independent of S02-04, S02-05, S02-06, S02-07, S02-08, S02-10** (migration stories are independent of each other).

## Goals

1. Replace each intrinsic call in `process.ks` with a `extern fun` declaration:
   ```kestrel
   extern fun getOs(): String =
     jvm("kestrel.runtime.KRuntime#getOs()")

   extern fun getArgs(): List<String> =
     jvm("kestrel.runtime.KRuntime#getArgs()")

   extern fun getCwd(): String =
     jvm("kestrel.runtime.KRuntime#getCwd()")

   extern fun runProcessAsync(program: String, args: List<String>): Task<Result<ProcessResult, String>> =
     jvm("kestrel.runtime.KRuntime#runProcessAsync(java.lang.Object,java.lang.Object)")
   ```
2. Update `process.ks` `async fun` bodies to call the new `extern fun` names.
3. Remove the four `if (name === '__get_os' | '__get_args' | '__get_cwd' | '__run_process') { ... }` blocks from `codegen.ts`.
4. Remove the four `env.set` bindings from `check.ts`.
5. Grep for any remaining `__get_os`, `__get_args`, `__get_cwd`, `__run_process` usage in the compiler and stdlib.

## Acceptance Criteria

- [ ] `stdlib/kestrel/process.ks` contains no `__get_os`, `__get_args`, `__get_cwd`, or `__run_process` calls.
- [ ] Four `extern fun` declarations exist in `process.ks`.
- [ ] `codegen.ts` has no dispatch blocks for these four intrinsics.
- [ ] `check.ts` has no `env.set` bindings for these four intrinsics.
- [ ] `stdlib/kestrel/process.test.ks` passes.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/02-stdlib.md` — `kestrel:process` module: no API change.

## Risks / Notes

- **`__get_args()` return type**: `KRuntime.getArgs()` returns a `KList` (which is Kestrel `List<String>`). The `extern fun` declares `List<String>` as the return type. No checkcast is needed — `KList` IS the runtime representation of `List<T>`. The codegen emits `invokestatic KRuntime.getArgs()Lkestrel/runtime/KList;`... but wait, the current codegen uses `()Lkestrel/runtime/KList;` — we need to verify whether `extern fun` codegen emits the correct descriptor when return type is `List<String>` (a Kestrel generic, not a Java class). This is a codegen detail: Kestrel collections are represented as `KList` objects at runtime, so the JVM descriptor is `()Ljava/lang/Object;` (since `KList` is already Object-compatible). Clarify this during implementation.
- **`ProcessResult`**: `process.ks` returns a `Task<Result<ProcessResult, String>>`. `ProcessResult` is a Kestrel ADT defined in `process.ks` itself. The `extern fun` for `runProcessAsync` must ensure the return type matches: the actual KRuntime method returns a `KTask` whose payload is a `KRecord` representing `ProcessResult` or a `String` error. The Kestrel type annotation in the extern binding expresses this but the runtime guarantee is not statically verified.
- **`--run_process` async blocker**: same as S02-08 — async extern fun must be supported in S02-02 or a follow-up.
