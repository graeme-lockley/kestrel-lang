# Self-hosted codegen: tail-call optimisation (loop-back GOTO)

## Sequence: S17-36
## Tier: 8
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-35, S17-37 through S17-38, S17-42

## Summary

The TS compiler applies self-tail-call optimisation to recursive functions: instead of a
recursive `INVOKESTATIC` + `ARETURN`, the last call to the function itself is replaced with
argument stores followed by a `GOTO` back to the method's start label. Without this
optimisation the self-hosted codegen will produce stack-overflowing recursive programs where
the TS compiler would produce a tight loop.

## Current State

The self-hosted `emitFunDecl` calls `emitTailLoopScaffold` which emits a `GOTO` to a
`loopStart` label and assigns `loopStart` in the method builder — but `emitExpr` never
emits the corresponding back-edge `GOTO`. The scaffold exists but the tail-call detection
and `GOTO` emission are absent.

TS reference:
- Each method starts with a label `loopHead` and a `GOTO loopHead+N` (skip the stores).
- When `emitExpr` detects a tail-position self-call (callee is the current function name
  and we are in a tail context `tailCtx`): store each arg to the corresponding parameter
  slot, `GOTO loopHead`.
- The `subJvmTail` / `JvmEmitTailContext` mechanism tracks whether an expression is in
  tail position through blocks, if-branches, match arms, etc.

## Relationship to other stories

- **Depends on**: S17-27 (`ECall` — tail calls are a special case of call emission).
- **Recommended after**: S17-30 (`EIf`) and S17-32 (`EMatch`) — tail position must be
  propagated through branches and match arms.
- **Blocks**: S17-42 (E2E) only indirectly — programs will still run without TCO but will
  stack-overflow on deeply recursive calls.

## Goals

1. Introduce a `TailContext` type (mirroring `JvmEmitTailContext`) and thread it through
   `emitExpr`, `emitBlockStmt`, and `emitBlockStmts`.
2. In `emitFunDecl`, set `tailCtx = TailContext(funcName, paramSlots)` for the body.
3. Propagate tail context through `EBlock` (only the final expression), `EIf` (both arms),
   `EMatch` arms, `ETry` (try body only), and `EWhile` (never tail).
4. In `ECall`, when `tailCtx` is set and the callee is `tailCtx.funcName`:
   - Evaluate each argument.
   - Store each argument to the corresponding parameter slot in reverse order.
   - `GOTO loopHead` (the scaffold label emitted by `emitTailLoopScaffold`).
5. Verify that the `thenArmPushesValue` predicate (used in `EIf`) correctly returns `False`
   for arms that end with a tail call → `GOTO` (no stack value pushed).

## Acceptance Criteria

- [ ] A recursive `fun sum(n, acc)` compiles without stack overflow for `n = 100_000`.
- [ ] A mutually recursive function pair that is NOT self-tail still uses `INVOKESTATIC`
      (mutual tail-call optimisation is out of scope for this story).
- [ ] New conformance tests cover deep self-recursion that would overflow without TCO.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — tail-call semantics (implicit; functions must not overflow
  for tail-recursive patterns)

## Risks / Notes

- The TS compiler's `JvmEmitTailContext` is optional (`| undefined`) and threaded through
  every call to `emitExpr`. The self-hosted version must thread it through the recursive
  `emitExpr` call (currently a single function). Consider adding it as a second parameter
  to `emitExpr` and `emitBlockStmt`.
