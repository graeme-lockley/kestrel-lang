# Self-hosted codegen: `EWhile` — loops with real `break` / `continue`

## Sequence: S17-31
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-30, S17-32 through S17-38, S17-42

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
- **Blocks**: S17-42 (E2E). Loops are used in many stdlib algorithms.

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

- [ ] A `while (n > 0) { n = n - 1 }` loop correctly decrements `n` to `0`.
- [ ] A `while (True) { if (done) break }` loop exits when `done` is `True`.
- [ ] `continue` inside a loop re-evaluates the condition without executing subsequent
      statements.
- [ ] An infinite loop (without `break`) does not terminate (not tested, but must not crash
      the JVM verifier with invalid bytecode).
- [ ] New codegen unit tests cover the basic loop, `break`, and `continue`.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — while expression, break, continue

## Risks / Notes

- The `estimateBodyLocals` heuristic is critical for JVM verifier acceptance. Without a
  wide-enough stackmap frame at the loop head, the verifier rejects back-edge GOTOs.
  Use a conservative fixed margin (e.g. 70 local slots) as the TS compiler does.
- This story should be validated with focused loop tests first; then use the runtime-negative loop
   scenario as the tranche-level confirmation once real startup/runtime execution is already active.
