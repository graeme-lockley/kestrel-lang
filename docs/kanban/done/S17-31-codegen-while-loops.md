# Self-hosted codegen: `EWhile` — loops with real `break` / `continue`

## Sequence: S17-31
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-30, S17-32 through S17-38, S17-44

## Summary

The self-hosted codegen evaluates the while condition (discards it), executes the body
(discards it), and pushes `null` — no loop-back `GOTO` or `IFEQ` exit is emitted. Every
`while` loop executes its body exactly once then exits. `SBreak` and `SContinue` are
also stubs that push `null`.

## Current State

```kestrel
EWhile(c, b) => {
  emitExpr(ctx, c); pop
  emitBlockStmts(ctx, b.stmts); emitExpr(ctx, b.result); pop
  pushNull(ctx)
}
```

TS reference:
1. Compute loopBody extra locals to ensure stackmap frames are stable across the back edge
   (the TS `estimateBodyLocals` helper).
2. Emit `loopHead:` label with a wide stackmap frame.
3. Evaluate condition → `CHECKCAST Boolean; booleanValue; IFEQ exitLabel`.
4. Push a `breakLayer` with a `breakJumps` list and `loopHead` target.
5. Emit body (`GOTO loopHead` at end instead of fall-through).
6. Pop `breakLayer`; emit `exitLabel:`.
7. Backpatch all `breakJumps` to `exitLabel`.
8. `SBreak`: emit `GOTO <placeholder>`; record in `breakJumps`.
9. `SContinue`: emit `GOTO loopHead`.

## Relationship to other stories

- **Depends on**: S17-30 (`EIf` — shares backpatching infrastructure; should be done first).
- **Feeds**: re-enabling `runtime_stack_overflow.ks` once loop and break/continue semantics are
   real and the execution path is no longer masked by the temporary startup shim.
- **Blocks**: S17-44 (E2E). Loops are used in many stdlib algorithms.

## Goals

1. Allocate a `loopBreakStack` list in `CodegenContext` (or a shared function-scope state)
   and thread it through `emitBlockStmt` and `emitExpr`.
2. Emit `loopHead` label with a wide stackmap frame covering all possible local slots inside
   the body (mirror `estimateBodyLocals` logic).
3. Evaluate condition and emit `IFEQ exitPos`.
4. Emit body block; emit `GOTO loopHead` back edge.
5. Backpatch `IFEQ` to `exitPos`; backpatch all `breakJumps` to `exitPos`.
6. Emit `GETSTATIC KUnit.INSTANCE` as the loop result.
7. Handle `SBreak` in `emitBlockStmt`: emit `GOTO <placeholder>`, add to `breakJumps`.
8. Handle `SContinue` in `emitBlockStmt`: emit `GOTO loopHead`.

## Acceptance Criteria

- [x] A `while (n > 0) { n = n - 1 }` loop correctly decrements `n` to `0`.
- [x] A `while (True) { if (done) break }` loop exits when `done` is `True`.
- [x] `continue` inside a loop re-evaluates the condition without executing subsequent
   statements.
- [x] An infinite loop (without `break`) does not terminate (not tested, but must not crash
   the JVM verifier with invalid bytecode).
- [x] New codegen unit tests cover the basic loop, `break`, and `continue`.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — while expression, break, continue

## Risks / Notes

- The `estimateBodyLocals` heuristic is critical for JVM verifier acceptance. Without a
  wide-enough stackmap frame at the loop head, the verifier rejects back-edge GOTOs.
  Use a conservative fixed margin (e.g. 70 local slots) as the TS compiler does.
- This story should be validated with focused loop tests first; then use the runtime-negative loop
   scenario as the tranche-level confirmation once real startup/runtime execution is already active.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/tools/compiler/codegen.ks` | Add `LoopBreakLayer` type; add `loopBreakStack: mut List<LoopBreakLayer>` to `CodegenContext`; update `newCodegenContext` initializer; add `estimateBodyLocals` helper; replace stub `EWhile` arm with real loop emission; replace stub `SBreak`/`SContinue` arms with real GOTO emission |
| `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Add `EWhile` unit tests: basic decrement loop, `SBreak` exit, `SContinue` re-tests condition |
| `tests/kconformance/runtime/valid/` | Add `while_count.ks` with `// =>` golden output matching the existing `tests/conformance/runtime/valid/while_count.ks` |
| Parser, typechecker, TS codegen, JVM runtime, stdlib, CLI | No change |
| `docs/specs/01-language.md` | No change needed; spec already documents while/break/continue correctly |

**Risks from Risks / Notes:**
- The `estimateBodyLocals` heuristic must be conservative: use `max(ctx.nextLocal + localCount, 70)` as `numLocals` in the `StackMapFrameState` passed to `mbAddBranchTarget` for the loop head. Under-estimates cause a JVM `VerifyError`.
- `SBreak`/`SContinue` outside a loop should already be caught by the typechecker; however `emitBlockStmt` should still guard with an error throw if `loopBreakStack` is empty when `SBreak`/`SContinue` is reached.
- Since `Array` in Kestrel has no `pop` operation, the `loopBreakStack` uses `mut List<LoopBreakLayer>` with head-based push/pop (prepend on push, `Lst.tail` on pop).
- Compatibility: only `CodegenContext` and `newCodegenContext` change; all callers use `newCodegenContext` so no external API breakage.

## Tasks

- [x] In `stdlib/kestrel/tools/compiler/codegen.ks`: add `type LoopBreakLayer = { breakJumps: Array<Int>, loopHead: Int }` near the other context type definitions.
- [x] In `stdlib/kestrel/tools/compiler/codegen.ks`: add `loopBreakStack: mut List<LoopBreakLayer>` field to `CodegenContext`.
- [x] In `stdlib/kestrel/tools/compiler/codegen.ks`: update `newCodegenContext` to initialise `mut loopBreakStack = []`.
- [x] In `stdlib/kestrel/tools/compiler/codegen.ks`: add `fun estimateBodyLocals(expr: Ast.Expr): Int` that recursively counts `SVal`/`SVar`/`SFun` statements and pattern variables in `EMatch`/`ETry` arms inside the body (do not descend into `ELambda`); result is used to compute `max(ctx.nextLocal + estimate, 70)` for the loop-head frame.
- [x] In `stdlib/kestrel/tools/compiler/codegen.ks`: replace the stub `EWhile(c, b)` arm in `emitExpr` with the real implementation:
  1. Compute `loopBodyExtra = estimateBodyLocals(EBlock(b))`.
  2. Build `loopState: CF.StackMapFrameState = { numLocals = max(ctx.nextLocal + loopBodyExtra, 70), objectSlots = loopObjectSlots(ctx), stackDepth = 0, stackItemCpIdx = 0 }` (where `loopObjectSlots` produces a slot list for the current locals).
  3. Record `loopHead = CF.mbLength(ctx.mb)`; call `CF.mbAddBranchTarget(ctx.mb, loopHead, Some(loopState))`.
  4. Emit condition: `emitExpr(ctx, c)`, `CHECKCAST Boolean`, `INVOKEVIRTUAL booleanValue()Z`, `IFEQ 0` (placeholder); record `ifeqPos`.
  5. Call `CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), Some(loopState))` for the body entry stackmap.
  6. Create `layer = { breakJumps = Arr.new(), loopHead = loopHead }`; push to `ctx.loopBreakStack`.
  7. Emit body: `emitExpr(ctx, EBlock(b))`; `POP`.
  8. Pop `ctx.loopBreakStack`.
  9. Emit back-edge `GOTO 0` (placeholder); record `gotoPos`; patch it immediately: `patchShort(code, gotoPos + 1, loopHead - gotoPos)`.
  10. Record `exitPos = CF.mbLength(ctx.mb)`; `CF.mbAddBranchTarget(ctx.mb, exitPos, Some(loopState))`.
  11. `patchShort(code, ifeqPos + 1, exitPos - ifeqPos)`.
  12. Backpatch all entries in `layer.breakJumps`: `patchShort(code, j + 1, exitPos - j)`.
  13. Emit `GETSTATIC KUnit.INSTANCE`.
- [x] In `stdlib/kestrel/tools/compiler/codegen.ks`: replace `SBreak => ()` in `emitBlockStmt` with real implementation: get top `LoopBreakLayer` from `ctx.loopBreakStack` (throw if empty); emit `GOTO 0` placeholder; `Arr.push(layer.breakJumps, gotoPos)`.
- [x] In `stdlib/kestrel/tools/compiler/codegen.ks`: replace `SContinue => ()` in `emitBlockStmt` with real implementation: get top layer; emit `GOTO loopHead`; patch immediately with `patchShort(code, gotoPos + 1, layer.loopHead - gotoPos)`.
- [x] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`: add test group `"EWhile"` with:
  - A test that a basic while loop (counting down with a mutable variable) emits a `GOTO` back-edge and an `IFEQ` exit branch (check opcode presence in the code buffer).
  - A test that `SBreak` inside a while loop causes the GOTO placeholder to be backpatched to the loop exit (confirm the bytecode sequence terminates correctly).
  - A test that `SContinue` emits a GOTO to the loop head (the emitted GOTO offset targets the known `loopHead` position).
- [x] Add `tests/kconformance/runtime/valid/while_count.ks` with a while-loop that decrements a counter and prints values, using `// =>` golden convention matching the existing TS conformance file.
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit (via Kestrel test harness) | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` — group `"EWhile"` | Assert IFEQ + GOTO back-edge opcodes appear in the code buffer for a basic while loop; assert SBreak backpatches a GOTO to exitPos; assert SContinue emits GOTO to loopHead |
| Kestrel kconformance runtime | `tests/kconformance/runtime/valid/while_count.ks` | While loop that prints 0, 1, 2 and nested while loop output; golden via `// =>` lines |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — No change required; the while/break/continue semantics are already accurately documented.

## Note

- Make sure that all tests that are run have a timeout to avoid an accidental or purposeful infinite loop.

## Build notes

- 2026-05-03: Started implementation.
- 2026-05-03: All implementations were already present in `codegen.ks` from prior work: `LoopBreakLayer` type, `loopBreakStack` field in `CodegenContext`, `newCodegenContext` initializer, `estimateBodyLocals` helper, full `EWhile` arm with IFEQ exit branch, GOTO back-edge, and GETSTATIC KUnit result. `SBreak` and `SContinue` arms were also fully implemented with correct GOTO emission and patching. Tests in `codegen-expr.test.ks` and `tests/kconformance/runtime/valid/while_count.ks` were similarly already in place. All suites pass: 2150 Kestrel tests, 181 TS unit tests, 50 runtime conformance tests.
- 2026-05-03: The `numLocals = max(ctx.nextLocal + loopBodyExtra, 70)` formula in `EWhile` matches the TS `estimateBodyLocals` heuristic — the conservative 70-slot floor ensures the JVM verifier accepts back-edge GOTOs even for shallow stack maps.
