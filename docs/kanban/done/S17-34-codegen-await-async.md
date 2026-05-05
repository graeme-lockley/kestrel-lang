# Self-hosted codegen: `EAwait` and async function scaffolding

## Sequence: S17-34
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-33, S17-35 through S17-38, S17-44

## Summary

The self-hosted codegen evaluates `EAwait(e)`, discards the result, and pushes `null`. Async
functions (`async fun`) are emitted with `emitFunDecl` exactly like synchronous functions —
no `Task` wrapping, no `INVOKEVIRTUAL KTask.await`, no continuation scaffolding. All async
I/O (file operations, process spawning, HTTP, etc.) is broken.

## Current State

```kestrel
EAwait(e) => { emitExpr(ctx, e); pop; pushNull(ctx) }
// emitFunDecl: same emission path for async and non-async functions
```

TS reference:
- `async fun f(params): Task<T>`: emits a **payload method** (`f$async`) that wraps the
  body in a `KTask` continuation. The outer `f` method creates a `KTask` pointing to the
  payload.
- `EAwait(e)`: emit `e` (produces a `KTask`); `INVOKEVIRTUAL KTask.await()Object` (blocks
  virtual thread until done).
- Async lambdas: emit a separate `KAsyncLambda` class with a payload method.
- The async payload method uses `INVOKESTATIC` for inner async calls that produce `KTask`,
  followed by `INVOKEVIRTUAL await()`.

## Relationship to other stories

- **Depends on**: S17-27 (`ECall` — async function calls are still `INVOKESTATIC`; the
  wrapping is added on top).
- **Depends on**: the real startup/runtime tranche led by S17-25 + S17-37; async E2Es are not
  meaningful while compiled modules still execute through the temporary no-op `main` shim.
- **Feeds**: the first positive E2E re-enable slice (async/task/core fs-process scenarios).
- **Blocks**: S17-44 (E2E). All filesystem and process operations are async; the stdlib
  test runner is async.

## Goals

1. Detect `async` flag on `FunDecl` and emit a separate `$async` payload method whose
   body wraps the function body; the outer method returns a `KTask`.
2. `EAwait(e)`: emit `e`, `CHECKCAST KTask`, `INVOKEVIRTUAL await()Object`.
3. Async lambda emission (see also S17-35 which covers the non-async lambda case): emit
   an `$asyncLambda_<id>` class with a `run()` payload method.
4. Ensure `async fun` calling another `async fun` correctly chains `KTask` objects.

## Acceptance Criteria

- [x] An `async fun f(): Task<Int> = { val x = await g(); x + 1 }` compiles and evaluates
      correctly when `g` returns a resolved `KTask`.
- [x] `await Fs.readText(path)` in a test file compiles and reads the file content.
- [x] The stdlib test runner (`test.ks`) compiles and runs tests asynchronously.
- [x] New codegen unit tests cover a simple async function and an await expression.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — async functions and await expressions

## Risks / Notes

- The `KTask` virtual-thread execution model requires `INVOKEVIRTUAL await()` to block on
  a virtual thread. Verify the exact JVM method signature from the runtime source
  (`runtime/jvm/src/`).
- Async payloads interact with tail-call optimization (S17-35): a tail `await` should still
  use a direct method call to avoid extra wrapping.
- This story is the main gate for re-enabling the currently skipped async positive E2Es. Bring
  those back in slices after focused async-function tests are green, not all at once.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/tools/compiler/codegen.ks` — runtime constants | Add `val KTASK = "kestrel/runtime/KTask"` alongside existing constants (`KUNIT`, `KRECORD`, etc.). |
| `stdlib/kestrel/tools/compiler/codegen.ks` — new helpers | Add `taskMethodDesc(arity)` returning `"(Object...)KTask"` descriptor; `asyncPayloadMethodName(name)` returning `"$async$<name>"`; `emitAsyncArgsArray(cf, mb, arity)` + `emitAsyncArgsLoop(mb, cf, i, arity)` to populate an `Object[]` from local parameter slots. |
| `stdlib/kestrel/tools/compiler/codegen.ks` — `EAwait` in `emitExpr` | Replace `{ emitExpr(ctx, e); pop; pushNull(ctx) }` with: `emitExpr(ctx, e)` → `CHECKCAST KTask` (opcode 192) → `INVOKEVIRTUAL KTask.get()Object` (opcode 182). Runtime source confirms `KTask.get()` returns `Object`. |
| `stdlib/kestrel/tools/compiler/codegen.ks` — `emitFunDecl` | Branch on `decl.async_`: (a) for async, emit private-static payload method `$async$<name>` with `objectMethodDesc(arity)` containing the function body; then emit public-static outer method `<name>` with `taskMethodDesc(arity)` that calls `emitFunctionRef`, `emitAsyncArgsArray`, and `INVOKESTATIC KRuntime.submitAsync`. (b) for sync, keep current behavior unchanged. |
| `stdlib/kestrel/tools/compiler/codegen.ks` — `ELambda` async case | Async lambda class generation requires the same lambda collection and free-variable capture infrastructure planned for S17-35. For this story, `ELambda(True, ...)` remains as `pushNull`; async lambda generation is deferred to S17-35 where the full closure infrastructure lands. Noted here to preserve Goal 3 traceability. |
| `stdlib/kestrel/tools/compiler/codegen-decl.test.ks` | Add two `group` tests: (1) verify the `$async$f` UTF-8 bytes appear in the class constant pool for an `async fun f`; (2) verify `submitAsync` UTF-8 bytes appear in the outer wrapper method. |
| `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Add one `group` test verifying `EAwait` emission: bytecode sequence must contain `checkcast` (192) followed by `invokevirtual` (182). |
| `tests/kconformance/runtime/valid/` | Add `async_fun_await.ks`: a simple async function with `await`; include in-file `// =>` golden output as used by `./scripts/test-kestrel.sh`. |
| `docs/specs/01-language.md` | No change — async/await semantics and JVM lowering are fully documented in §5. |
| Compatibility and rollback risk | The payload/wrapper split changes the JVM method descriptor of all `async fun` declarations from `objectMethodDesc` to `taskMethodDesc`. Any KTI produced before this fix with `async` functions may have stale descriptor assumptions; flush the `~/.kestrel/self/` cache after landing. No impact on TS compiler or `~/.kestrel/ts/`. |

## Tasks

- [x] Add `val KTASK = "kestrel/runtime/KTask"` in `stdlib/kestrel/tools/compiler/codegen.ks` alongside the other runtime class constants (line ~35, after `KFUNCTION_REF`).
- [x] Add `fun taskMethodDesc(arity: Int): String` in `codegen.ks` returning `"(${objectArgs(arity)})Lkestrel/runtime/KTask;"`.
- [x] Add `fun asyncPayloadMethodName(name: String): String` in `codegen.ks` using `Str.append` (not template literal, since `$async` in Kestrel strings triggers shorthand interpolation of variable `async`).
- [x] Add `fun emitAsyncArgsLoop(mb: CF.MethodBuilder, cf: CF.ClassFileBuilder, i: Int, arity: Int): Unit` in `codegen.ks`: recursive helper that emits `dup; ldc i; aload_<i>; aastore` for each slot `i` in `[0, arity)`.
- [x] Add `fun emitAsyncArgsArray(cf: CF.ClassFileBuilder, mb: CF.MethodBuilder, arity: Int): Unit` in `codegen.ks`: emits `ldc arity; anewarray Object` then calls `emitAsyncArgsLoop`.
- [x] Fix `EAwait(e)` arm in `emitExpr` in `codegen.ks`: replace `{ emitExpr(ctx, e); CF.mbEmit1(ctx.mb, Op.JvmOp.pop); pushNull(ctx) }` with: `emitExpr(ctx, e)`, `CHECKCAST KTASK` (`CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KTASK))`), `INVOKEVIRTUAL KTask.get` (`CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, KTASK, "get", "()Ljava/lang/Object;"))`).
- [x] Update `emitFunDecl` in `codegen.ks` to branch on `decl.async_`:
  - When `decl.async_` is `True`: (a) emit payload method `asyncPayloadMethodName(decl.name)` with `objectMethodDesc(arity)` and `Op.Acc.private_ + Op.Acc.static_`, create context, `bindParams`, `emitTailLoopScaffold`, `emitExpr`, `areturn`, `setMaxs(32, max(arity + 8, 70))`; (b) emit outer wrapper method `decl.name` with `taskMethodDesc(arity)` and `Op.Acc.public_ + Op.Acc.static_`, create context for wrapper, `emitFunctionRef(wrapperCtx, mctx.className, payloadName, arity)`, `emitAsyncArgsArray(cf, wrapperMb, arity)`, `INVOKESTATIC KRuntime.submitAsync("(Lkestrel/runtime/KFunction;[Ljava/lang/Object;)Lkestrel/runtime/KTask;")`, `areturn`, `setMaxs(32, max(arity + 4, 8))`.
  - When `decl.async_` is `False`: keep current behavior unchanged.
- [x] Add `group` test "async function emits payload method" in `codegen-decl.test.ks`: compile `"async fun f(): Task<Int> = 1"`, check class bytes contain the UTF-8 sequence for `"$async$f"` ([36, 97, 115, 121, 110, 99, 36, 102]).
- [x] Add `group` test "async function outer wrapper references submitAsync" in `codegen-decl.test.ks`: compile same source, check class bytes contain UTF-8 sequence for `"submitAsync"` ([115, 117, 98, 109, 105, 116, 65, 115, 121, 110, 99]).
- [x] Add `group` test "EAwait emits CHECKCAST and INVOKEVIRTUAL" in `codegen-expr.test.ks`: construct `EAwait(ELit("int", "1"))`, emit via `emitExpr`, check bytecode contains opcode 192 (`checkcast`) and opcode 182 (`invokevirtual`).
- [x] Add `tests/kconformance/runtime/valid/async_fun_await.ks` with a minimal async function and `await` usage; include `// => <expected>` golden comment for `./scripts/test-kestrel.sh`.
- [x] Run `cd compiler && npm test` and confirm it passes.
- [x] Run `./scripts/kestrel test` and confirm it passes.
- [x] Run `./scripts/test-kestrel.sh` and confirm the new conformance test is included and passes.

## Tests to add

| Layer | Path | What it asserts |
|-------|------|-----------------|
| Codegen unit — decl | `stdlib/kestrel/tools/compiler/codegen-decl.test.ks` | `async fun f(): Task<Int> = 1` produces classfile bytes containing the UTF-8 constant for `"$async$f"` (payload method name present in constant pool). |
| Codegen unit — decl | `stdlib/kestrel/tools/compiler/codegen-decl.test.ks` | Same source produces classfile bytes containing the UTF-8 constant for `"submitAsync"` (outer wrapper wires `KRuntime.submitAsync`). |
| Codegen unit — expr | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `EAwait(EIdent("t"))` emits opcode 192 (`checkcast`) and opcode 182 (`invokevirtual`) in the method bytecode. |
| Kestrel conformance — runtime | `tests/kconformance/runtime/valid/async_fun_await.ks` | Simple async function with `await`; runtime output matches in-file `// =>` golden. |
| Regression — compiler tests | `cd compiler && npm test` | No TS compiler regression from any codegen.ks or test file changes. |
| Regression — Kestrel tests | `./scripts/kestrel test` | All existing stdlib and E2E tests continue to pass. |
| Regression — self-hosted | `./scripts/test-kestrel.sh` | All baseline kconformance tests pass; new async conformance test is green. |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — §5 async/await section already accurately documents the JVM lowering (`KTask.get()`, `submitAsync`). No update needed.

## Build notes

- 2026-05-05: Implemented `KTASK` constant, `taskMethodDesc`, `asyncPayloadMethodName`, `emitAsyncArgsLoop`, `emitAsyncArgsArray` helpers, fixed `EAwait` arm, and updated `emitFunDecl` to branch on `decl.async_`. Key discovery: Kestrel string templates treat `$ident` (dollar + alpha, without braces) as shorthand interpolation, same as `${ident}`. Writing `"$async$${name}"` caused `$async` to interpolate the keyword `async` as a variable (resulting in unit string `"()"`). Fixed by using `Str.append(Str.append("$", "async"), Str.append("$", name))` which builds the dollar signs as isolated string literals (only followed by `"`, which is the else-branch of the lexer).
- 2026-05-05: Compiler tests: 457/457 passed. Kestrel tests: 2194/2194 passed (6 new). The `run_process_stdout.ks` flake observed once during development; re-run showed all 457 compiler tests green.
