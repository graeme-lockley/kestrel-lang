# Self-hosted codegen: `ETry` / `EThrow` — real JVM exception handling

## Sequence: S17-33
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-32, S17-34 through S17-38, S17-42

## Summary

The self-hosted codegen executes `ETry` block statements, discards the block result, runs
all catch arms sequentially (no branching), and pushes `null`. `EThrow` evaluates the
exception expression, discards it, and pushes `null` — nothing is actually thrown. JVM
`ATHROW` is never emitted; `try/catch` JVM exception tables are never written.

## Current State

```kestrel
EThrow(e) => { emitExpr(ctx, e); pop; pushNull(ctx) }
ETry(block, _varOpt, cases) => {
  emitBlockStmts(ctx, block.stmts)
  emitExpr(ctx, block.result); pop
  emitMatchArms(ctx, cases)   // executed unconditionally
}
```

TS reference:
- `EThrow`: emit expression, `CHECKCAST Throwable`, `ATHROW`.
- `ETry`: emit the try body; register JVM exception-table entries for each catch arm
  (one entry per concrete exception type); emit catch dispatch; end with a `GOTO` past
  all handlers.
- Catch arm: `ASTORE exnSlot`, pattern-match on the exception type using `instanceof`,
  bind fields, emit arm body, `GOTO matchEnd`.

## Relationship to other stories

- **Depends on**: S17-30 (`EIf` — backpatching) and S17-32 (`EMatch` — catch arm dispatch
  shares pattern infrastructure).
- **Runtime-negative tranche**: this story is the direct gate for re-enabling
  `uncaught_throw.ks` and `runtime_catch_no_match_rethrow.ks` once real startup is in place.
- **Blocks**: S17-42 (E2E). Exception handling is used throughout the stdlib for IO errors.

## Goals

1. `EThrow(e)`: emit expression, `CHECKCAST java/lang/Throwable`, `ATHROW`.
2. `ETry(block, varOpt, cases)`:
   a. Record `tryStart = mb.length()`.
   b. Emit try body; `ASTORE resultSlot`; `GOTO tryEnd`.
   c. For each catch arm: record `handlerStart`; register exception-table entry
      `(tryStart, handlerStart, handlerStart, ExceptionClass)` in the classfile;
      `ASTORE exnSlot`; emit pattern matching on the exception; `GOTO tryEnd`.
   d. Backpatch `tryEnd`; `ALOAD resultSlot`.
3. Exception table entries must be added via `classfile.ks`'s builder API (add helper if
   absent).

## Acceptance Criteria

- [ ] `throw MyError("msg")` causes the JVM to throw the exception at runtime.
- [ ] `try { throw E("x") } catch (E(m)) { m }` evaluates to `"x"`.
- [ ] A `try` block that does not throw returns its body value.
- [ ] Nested `try` expressions work correctly.
- [ ] New codegen unit tests cover throw, catch, and no-throw paths.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — throw and try expressions

## Risks / Notes

- `classfile.ks` must expose an `addExceptionTableEntry` or equivalent API. Check whether
  this is already present; if not, add it as part of this story.
- The `varOpt` parameter of `ETry` (variable name for the raw caught Throwable in the
  finally-clause-style usage) — verify with the TS reference how this is handled.
- Validate this story against the restored runtime-negative scenarios before re-enabling broader
  fs/process/http positive tests, because exception paths are central to those result types.
