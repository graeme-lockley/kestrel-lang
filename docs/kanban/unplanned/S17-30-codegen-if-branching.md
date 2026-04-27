# Self-hosted codegen: `EIf` — conditional branching with JVM backpatching

## Sequence: S17-30
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-29, S17-31 through S17-38, S17-42

## Summary

The self-hosted `EIf` implementation evaluates the condition, discards it, evaluates both
the `then` and `else` branches sequentially, and returns the last value — no branching
occurs. Every `if` expression in a self-hosted-compiled program always executes both
branches and returns the last one.

## Current State

```kestrel
EIf(c, t, eOpt) => {
  emitExpr(ctx, c); CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
  emitExpr(ctx, t)
  match (eOpt) {
    Some(e) => { CF.mbEmit1(ctx.mb, Op.JvmOp.pop); emitExpr(ctx, e) }
    None => ()
  }
}
```

TS reference emits real conditional branching:
1. Evaluate condition → `CHECKCAST Boolean; INVOKEVIRTUAL booleanValue; IFEQ elseLabel`.
2. Emit `then` expression → `ASTORE resultSlot; GOTO endLabel`.
3. `elseLabel:` emit `else` expression (or `KUnit.INSTANCE`) → `ASTORE resultSlot`.
4. `endLabel:` `ALOAD resultSlot`.
5. Backpatch `IFEQ` and `GOTO` offsets after emitting both branches.
Also handles the tail-call optimisation case where `then` ends with `ARETURN`
(no result slot needed for the then arm).

## Relationship to other stories

- **Depends on**: S17-24 (literals for unit), S17-26 (operators — condition is usually a
  comparison), S17-27 (call emission).
- **Blocks**: S17-31 (`EWhile`) and S17-32 (`EMatch`) — all of these require the same
  backpatching infrastructure. `EIf` is the simplest form to implement first.
- **Blocks**: restoring meaningful runtime-negative execution, because `if`-driven control flow is
  required before runtime stack/throw/catch scenarios can be trusted again.
- **Blocks**: S17-42 (E2E).

## Goals

1. Evaluate condition; `CHECKCAST Boolean; INVOKEVIRTUAL booleanValue; IFEQ <placeholder>`.
2. Emit then-branch; store to a fixed temp slot; emit `GOTO <placeholder>`.
3. Backpatch the `IFEQ` to point here; emit else-branch (or `KUnit.INSTANCE`); store to
   the same temp slot.
4. Backpatch the `GOTO` to point here; `ALOAD` the temp slot.
5. Verify that JVM stackmap frames are correct at the branch targets (required for Java 7+
   class files). Add `addBranchTarget` calls as the TS reference does.

## Acceptance Criteria

- [ ] `if (True) 1 else 2` evaluates to `1`, not `2`.
- [ ] `if (False) 1 else 2` evaluates to `2`.
- [ ] `if (x > 0) "pos" else "neg"` branches correctly at runtime.
- [ ] `if (cond) doSideEffect()` (no else arm) emits `KUnit` for the missing else.
- [ ] New codegen unit tests verify correct branching for both arms.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — if expression
- `docs/specs/11-bootstrap.md` — JVM stackmap frame requirements

## Risks / Notes

- The TS reference uses fixed temp slots (e.g. slot 53 for `if` result) to avoid collisions
  with parameter slots (slots 0–N). The Kestrel implementation must use the same or a
  compatible slot-allocation scheme.
- `thenArmPushesValue` (TS line 163) — a predicate that returns `false` when the then arm
  ends with `ARETURN` (tail call). This avoids emitting an unreachable `ASTORE` after the
  return, which confuses the verifier. Port this predicate.
- This is the control-flow foundation story. Re-enable runtime-negative scenarios only after this,
  S17-31/S17-33, and the real startup tranche are all in place.
