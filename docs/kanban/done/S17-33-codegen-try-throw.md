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

- [x] `throw MyError("msg")` causes the JVM to throw the exception at runtime.
- [x] `try { throw E("x") } catch (E(m)) { m }` evaluates to `"x"`.
- [x] A `try` block that does not throw returns its body value.
- [x] Nested `try` expressions work correctly.
- [x] New codegen unit tests cover throw, catch, and no-throw paths.
- [x] `cd compiler && npm test` passes (457 tests).
- [x] `./scripts/kestrel test` passes (2188 tests).

## Spec References

- `docs/specs/01-language.md` — throw and try expressions; confirmed §4 spec text matches new codegen behavior.

## Build notes

- 2026-05-04: Started implementation. Implemented `EThrow` with `NEW KException`, `DUP_X1`, `SWAP`, `INVOKESPECIAL`, `ATHROW`. Implemented `ETry` with exception table entry, `normalizeCaught` dispatch, catch arm pattern matching via `emitMatchArmsFull`, rethrow tail, and backpatching. Added `exceptionHandlerFrame` helper to `classfile.ks`.
- 2026-05-04: Discovered TS compiler OOM during codegen.ks typechecking; the large `ETry` implementation in the `emitExpr` match body exceeded the TS compiler's analysis budget. Extracted `emitEThrow` and `emitETry` helpers to split the match expression into smaller independent functions, reducing each function's type complexity. Fixed syntax error: bare `match` arms with `:=` mutation require `{ }` braces. Bootstrap JAR now builds cleanly at 4 GB Node heap (vs. OOM at 16 GB with monolithic match arm).
- 2026-05-04: All test suites pass: compiler (457 tests), kestrel (2188 tests). Bootstrap JAR builds successfully. Self-hosted bootstrap completed. All acceptance criteria satisfied.

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

- [x] Add `val K_EXCEPTION = "kestrel/runtime/KException"` near other class-name constants in `stdlib/kestrel/tools/compiler/codegen.ks` (around line 44).
- [x] Add `export fun exceptionHandlerFrame(numLocals: Int, catchTypeIdx: Int): StackMapFrameState` to `stdlib/kestrel/tools/compiler/classfile.ks`. The helper constructs `{ numLocals = numLocals, objectSlots = slotList(0, numLocals, []), stackDepth = 1, stackItemCpIdx = catchTypeIdx }`.
- [x] Rewrite `EThrow` arm in `emitExpr` (`codegen.ks`): emit the exception value expression; then `NEW K_EXCEPTION`; `DUP_X1`; `SWAP`; `INVOKESPECIAL K_EXCEPTION "<init>" "(Ljava/lang/Object;)V"`; `ATHROW`. Return (no further value push since ATHROW transfers control).
- [x] Rewrite `ETry` arm in `emitExpr` (`codegen.ks`) — try body, handler setup, normalizeCaught dispatch, catch arm dispatch, rethrow, backpatching, and result.
- [x] Remove or tombstone `emitMatchArmsStub` from `codegen.ks` — it was a placeholder for ETry and is no longer needed. Remove calls to it from ETry.
- [x] Extract `emitEThrow` and `emitETry` helpers to avoid typechecker OOM on large match body (refactored after initial implementation).
- [x] Add test group `"EThrow emits ATHROW"` to `codegen-expr.test.ks`.
- [x] Add test group `"ETry no-throw path returns body value"` to `codegen-expr.test.ks`.
- [x] Add test group `"ETry catch arm pattern dispatch"` to `codegen-expr.test.ks`.
- [x] Add test group `"nested ETry"` to `codegen-expr.test.ks`.
- [x] Run `cd compiler && npm test` (457 tests pass).
- [x] Run `./scripts/kestrel test` (2188 tests pass).

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

- [x] `docs/specs/01-language.md` — review §4 (throw/try semantics) to confirm spec text matches the new codegen behaviour; no text changes are expected but verify.
