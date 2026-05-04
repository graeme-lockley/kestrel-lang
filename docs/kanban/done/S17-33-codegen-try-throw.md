# Self-hosted codegen: `ETry` / `EThrow` — real JVM exception handling

## Sequence: S17-33
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-32, S17-34 through S17-38, S17-44

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
- **Blocks**: S17-44 (E2E). Exception handling is used throughout the stdlib for IO errors.

## Goals

1. `EThrow(e)`: emit expression, `NEW kestrel/runtime/KException`, `DUP_X1`, `SWAP`,
   `INVOKESPECIAL KException.<init>(Ljava/lang/Object;)V`, `ATHROW`.
2. `ETry(block, varOpt, cases)`:
   a. Record `tryStart = mb.length()`.
   b. Emit try body; `ASTORE tryResultSlot`; `GOTO tryEnd` (placeholder backpatched later).
   c. Record `handlerStart`; register exception-table entry
      `(tryStart, handlerStart, handlerStart, throwableClassIdx)` via `CF.mbAddException`.
   d. `ASTORE EXN_SLOT (57)`; `ALOAD EXN_SLOT`; `CHECKCAST java/lang/Throwable`.
   e. Push ArithmeticOverflow / DivideByZero / Cancelled class strings (or ACONST_NULL) from
      `ctx.mctx.adtClassByConstructor`; `INVOKESTATIC KRuntime.normalizeCaught`.
   f. `ASTORE PAYLOAD_SLOT (56)`.
   g. Dispatch catch arms using `emitMatchArmsFull` with PAYLOAD_SLOT as scrutSlot and
      tryResultSlot as matchResultSlot.
   h. Rethrow: `ALOAD EXN_SLOT (57)`; `CHECKCAST java/lang/Throwable`; `ATHROW`.
   i. Backpatch `GOTO tryEnd` and all arm-end labels → `afterCatch`; `ALOAD tryResultSlot`.
3. Exception table entries are added via the already-present `CF.mbAddException` API.
4. Add `exceptionHandlerFrame(numLocals: Int, catchTypeIdx: Int): StackMapFrameState`
   helper to `classfile.ks` to create a frame with `stackDepth = 1` (for the exception
   handler entry point).

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

- `classfile.ks` must expose an `addExceptionTableEntry` or equivalent API. **`CF.mbAddException` already exists** at line 518 of `classfile.ks` — no new classfile API is needed for the exception table itself. A new `exceptionHandlerFrame` helper is needed to create a `StackMapFrameState` with `stackDepth = 1` (the JVM exception handler entry frame has the caught exception on the operand stack).
- The `varOpt` parameter of `ETry` (variable name for the raw caught Throwable in the finally-clause-style usage) — in the TS reference `catchVar` maps to `PAYLOAD_SLOT (56)` (the normalized payload, not the raw throwable). Bind `varOpt` → PAYLOAD_SLOT in `ctx.locals` when present, and restore after arm dispatch.
- Fixed slots: `EXN_SLOT = 57` (raw Throwable), `PAYLOAD_SLOT = 56` (normalized payload), `scrutSlot = 55` (EMatch), `matchResultSlot = 54` (EMatch) — ETry should avoid colliding with these. Use `ctx.nextLocal` for `tryResultSlot`.
- The handler frame's `numLocals` must be `max(ctx.nextLocal + estimateBodyLocals(EBlock(block)), 70)` to satisfy the JVM stackmap verifier (see S08-10 pattern).
- Catch arm dispatch reuses `emitMatchArmsFull` with `catchBaseState = paramOnlyFrame(max(ctx.nextLocal, 58))` to ensure slots 56 and 57 are covered.
- Validate this story against the restored runtime-negative scenarios before re-enabling broader fs/process/http positive tests, because exception paths are central to those result types.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/tools/compiler/codegen.ks` | Add `val K_EXCEPTION` constant; replace `EThrow` stub with real `NEW`/`ATHROW` sequence; replace `ETry` stub with full JVM exception handling (exception table, handler frame, `normalizeCaught` dispatch, arm matching, rethrow, backpatching). Remove `emitMatchArmsStub` dead code. |
| `stdlib/kestrel/tools/compiler/classfile.ks` | Add `exceptionHandlerFrame(numLocals: Int, catchTypeIdx: Int): StackMapFrameState` export helper (creates frame with `stackDepth = 1`, `stackItemCpIdx = catchTypeIdx`). |
| `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Add test groups: `EThrow` opcode sequence, `ETry` no-throw path, `ETry` catch arm dispatch, nested `ETry`. |
| `tests/e2e/scenarios/negative/uncaught_throw.ks` | Existing file; should pass (produce stack trace) once real `ATHROW` is emitted by the self-hosted compiler. |
| `tests/e2e/scenarios/negative/runtime_catch_no_match_rethrow.ks` | Existing file; should pass (rethrow on no match) once real exception dispatch is wired. |
| `docs/specs/01-language.md` | Read-only review: no changes expected; existing spec already describes throw/try correctly. |

## Tasks

- [ ] Add `val K_EXCEPTION = "kestrel/runtime/KException"` near other class-name constants in `stdlib/kestrel/tools/compiler/codegen.ks` (around line 44).
- [ ] Add `export fun exceptionHandlerFrame(numLocals: Int, catchTypeIdx: Int): StackMapFrameState` to `stdlib/kestrel/tools/compiler/classfile.ks`. The helper constructs `{ numLocals = numLocals, objectSlots = slotList(0, numLocals, []), stackDepth = 1, stackItemCpIdx = catchTypeIdx }`.
- [ ] Rewrite `EThrow` arm in `emitExpr` (`codegen.ks`): emit the exception value expression; then `NEW K_EXCEPTION`; `DUP_X1`; `SWAP`; `INVOKESPECIAL K_EXCEPTION "<init>" "(Ljava/lang/Object;)V"`; `ATHROW`. Return (no further value push since ATHROW transfers control).
- [ ] Rewrite `ETry` arm in `emitExpr` (`codegen.ks`) — try body:
  - Allocate `tryResultSlot = ctx.nextLocal; ctx.nextLocal += 1`.
  - Record `tryStart = CF.mbLength(ctx.mb)`; register branch target via `CF.mbAddBranchTarget` with `Some(CF.paramOnlyFrame(ctx.nextLocal))`.
  - Emit `emitBlockStmts(ctx, block.stmts)` then `emitExpr(ctx, block.result)`.
  - `ASTORE tryResultSlot`; record `gotoAfterTry = CF.mbLength(ctx.mb)`; emit `GOTO 0` (placeholder).
- [ ] Rewrite `ETry` arm — exception handler and table entry:
  - Record `handlerStart = CF.mbLength(ctx.mb)`.
  - Compute `tryBodyExtra = estimateBodyLocals(EBlock(block))`; compute `handlerNumLocals = max(ctx.nextLocal + tryBodyExtra, 70)`.
  - Obtain `throwableClassIdx = CF.cfClassRef(ctx.cf, "java/lang/Throwable")`.
  - Register handler branch target: `CF.mbAddBranchTarget(ctx.mb, handlerStart, Some(CF.exceptionHandlerFrame(handlerNumLocals, throwableClassIdx)))`.
  - Register exception table entry: `CF.mbAddException(ctx.mb, tryStart, handlerStart, handlerStart, throwableClassIdx)`.
- [ ] Rewrite `ETry` arm — normalizeCaught dispatch:
  - `ASTORE EXN_SLOT (57)`; `ALOAD EXN_SLOT`; `CHECKCAST "java/lang/Throwable"`.
  - Look up `ArithmeticOverflow`, `DivideByZero`, `Cancelled` from `ctx.mctx.adtClassByConstructor`; push each via `LDC_W` string or `ACONST_NULL`.
  - `INVOKESTATIC KRuntime "normalizeCaught" "(Ljava/lang/Throwable;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/Object;"`.
  - `ASTORE PAYLOAD_SLOT (56)`.
  - If `varOpt = Some(name)`, bind `name` → PAYLOAD_SLOT in `ctx.locals`.
- [ ] Rewrite `ETry` arm — catch arm dispatch and rethrow:
  - Compute `catchBaseState = CF.paramOnlyFrame(max(ctx.nextLocal, 58))`.
  - Save `savedNextLocal = ctx.nextLocal`.
  - Emit catch arms: `val catchEndLabels = emitMatchArmsFull(ctx, cases, 56, tryResultSlot, savedNextLocal, catchBaseState, CF.mbGetCode(ctx.mb))`.
  - Emit rethrow tail: register branch target with `catchBaseState`; `ALOAD EXN_SLOT (57)`; `CHECKCAST "java/lang/Throwable"`; `ATHROW`.
- [ ] Rewrite `ETry` arm — afterCatch backpatching and result:
  - Record `afterCatch = CF.mbLength(ctx.mb)`; register branch target with `CF.paramOnlyFrame(ctx.nextLocal)`.
  - Backpatch `gotoAfterTry` → afterCatch: `patchShort(code, gotoAfterTry + 1, afterCatch - gotoAfterTry)`.
  - Backpatch all `catchEndLabels` → afterCatch via `backpatchBreakJumps`.
  - Restore `varOpt` binding if set.
  - `ALOAD tryResultSlot` (push expression result).
- [ ] Remove or tombstone `emitMatchArmsStub` from `codegen.ks` — it was a placeholder for ETry and is no longer needed. Remove calls to it from ETry.
- [ ] Add test group `"EThrow emits ATHROW"` to `codegen-expr.test.ks`: construct an `EThrow(ELit("int", "1"))` expression; verify the code buffer contains the `ATHROW` opcode (191) and `NEW` opcode (187).
- [ ] Add test group `"ETry no-throw path returns body value"` to `codegen-expr.test.ks`: construct an `ETry` with a simple body and a wildcard catch arm; verify a non-empty class is produced (exception table present).
- [ ] Add test group `"ETry catch arm pattern dispatch"` to `codegen-expr.test.ks`: verify that the generated code buffer contains `INSTANCEOF` (193), `IFEQ` (153), and `INVOKESTATIC` for `normalizeCaught`.
- [ ] Add test group `"nested ETry"` to `codegen-expr.test.ks`: two nested `ETry` expressions; verify that two exception table entries are present in the resulting classfile bytes.
- [ ] Run `cd compiler && npm test`.
- [ ] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | What the test asserts |
|-------|------|-----------------------|
| Codegen unit — EThrow opcode | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `EThrow(ELit("int","1"))` emits `NEW` (187) for KException, `DUP_X1` (90), `SWAP` (95), `INVOKESPECIAL` (183), `ATHROW` (191) in code buffer |
| Codegen unit — ETry no-throw | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `ETry` block with no throw produces a class with non-empty exception table bytes and loads `tryResultSlot` after the handler region |
| Codegen unit — ETry catch dispatch | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Handler region contains `INVOKESTATIC` (184) for `normalizeCaught`, `ASTORE` for PAYLOAD_SLOT (56), and `INSTANCEOF` (193) for a constructor pattern |
| Codegen unit — nested ETry | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Two nested `ETry` expressions produce two exception table entries in the serialized classfile |
| E2E negative (existing) | `tests/e2e/scenarios/negative/uncaught_throw.ks` | Produces non-zero exit with stack trace once real ATHROW is emitted |
| E2E negative (existing) | `tests/e2e/scenarios/negative/runtime_catch_no_match_rethrow.ks` | Produces non-zero exit (rethrow) when no catch arm matches |

## Documentation and specs to update

- [ ] `docs/specs/01-language.md` — review §4 (throw/try semantics) to confirm spec text matches the new codegen behaviour; no text changes are expected but verify.
