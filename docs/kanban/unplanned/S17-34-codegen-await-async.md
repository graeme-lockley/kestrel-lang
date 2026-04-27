# Self-hosted codegen: `EAwait` and async function scaffolding

## Sequence: S17-34
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-33, S17-35 through S17-38, S17-42

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
- **Blocks**: S17-42 (E2E). All filesystem and process operations are async; the stdlib
  test runner is async.

## Goals

1. Detect `async` flag on `FunDecl` and emit a separate `$async` payload method whose
   body wraps the function body; the outer method returns a `KTask`.
2. `EAwait(e)`: emit `e`, `CHECKCAST KTask`, `INVOKEVIRTUAL await()Object`.
3. Async lambda emission (see also S17-35 which covers the non-async lambda case): emit
   an `$asyncLambda_<id>` class with a `run()` payload method.
4. Ensure `async fun` calling another `async fun` correctly chains `KTask` objects.

## Acceptance Criteria

- [ ] An `async fun f(): Task<Int> = { val x = await g(); x + 1 }` compiles and evaluates
      correctly when `g` returns a resolved `KTask`.
- [ ] `await Fs.readText(path)` in a test file compiles and reads the file content.
- [ ] The stdlib test runner (`test.ks`) compiles and runs tests asynchronously.
- [ ] New codegen unit tests cover a simple async function and an await expression.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — async functions and await expressions

## Risks / Notes

- The `KTask` virtual-thread execution model requires `INVOKEVIRTUAL await()` to block on
  a virtual thread. Verify the exact JVM method signature from the runtime source
  (`runtime/jvm/src/`).
- Async payloads interact with tail-call optimization (S17-35): a tail `await` should still
  use a direct method call to avoid extra wrapping.
