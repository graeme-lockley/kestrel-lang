# Self-hosted codegen: `EIf` — conditional branching with JVM backpatching

## Sequence: S17-30
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-29, S17-31 through S17-38, S17-44

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
- **Blocks**: S17-44 (E2E).

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

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/tools/compiler/codegen.ks` — `emitExpr` `EIf` branch | Replace the stub (pop-condition / emit-both-arms) with real JVM conditional branching: `CHECKCAST Boolean → INVOKEVIRTUAL booleanValue → IFEQ placeholder → emit then arm → ASTORE ifResultSlot → GOTO placeholder → elseLabel: emit else arm (or KUnit.INSTANCE) → ASTORE ifResultSlot → endLabel: ALOAD ifResultSlot`. Add `CF.mbAddBranchTarget` calls at `elseLabel` and `endLabel` for the JVM stackmap verifier. |
| `stdlib/kestrel/tools/compiler/codegen.ks` — new `thenArmPushesValue` helper | Add `fun thenArmPushesValue(expr: Ast.Expr): Bool` that returns `False` for `ENever` (and for `EBlock` whose last statement is a tail-transferring statement) so an unreachable `ASTORE`/`GOTO` is not emitted after the then arm exits via ARETURN. Mirrors TS reference lines 163–171. |
| Fixed temp slot 53 (`ifResultSlot`) | Must match the TS reference. The constant is already described in `compiler/src/jvm-codegen/codegen.ts` line 1624 and must be consistently used. No change to slot allocation scheme required beyond declaring the constant in the Kestrel codegen. |
| `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Replace the smoke-only "if emits" test with targeted opcode / byte-sequence assertions that distinguish true/false branching outcomes; add a no-else arm test verifying KUnit emission. |
| `tests/conformance/runtime/valid/if_branching.ks` | New runtime conformance test (with `// stdout` golden lines) that exercises: `if True`, `if False`, `if` with a numeric condition, and a no-else arm returning `Unit`. |
| `docs/specs/01-language.md` | No behavioral change — spec already documents `if` expression. No update needed. |
| `docs/specs/11-bootstrap.md` | No behavioral change — stackmap frame requirements are already documented at a policy level. No update needed. |
| Rollback risk | Low. The stub was always wrong; reverting to the stub restores the broken state. No class-file format change. |

## Tasks

- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks`, add helper function `fun thenArmPushesValue(expr: Ast.Expr): Bool`:
  - Return `False` for `ENever`.
  - For `EBlock(block)`: if `block.stmts` is empty, recurse on `block.result`; otherwise return `False` when the last statement is a break or continue (check `SBreak` / `SContinue` node kinds), else return `True`.
  - Default: return `True`.
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks`, replace the `EIf(c, t, eOpt)` arm of `emitExpr` with:
  1. `emitExpr(ctx, c)`
  2. `CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, BOOLEAN))`
  3. `CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, BOOLEAN, "booleanValue", "()Z"))`
  4. Capture `code = CF.mbGetCode(ctx.mb)` and `ifeqPos = CF.mbLength(ctx.mb)`.
  5. `CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)` — placeholder offset.
  6. `CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), None)` — stackmap at then-arm entry.
  7. Declare `ifResultSlot = 53`.
  8. `emitExpr(ctx, t)` — emit then arm.
  9. If `thenArmPushesValue(t)`:
     - `storeLocal(ctx, ifResultSlot)` (i.e., `CF.mbEmit1b(ctx.mb, Op.JvmOp.astore, ifResultSlot)`)
     - Capture `gotoPos = CF.mbLength(ctx.mb)`.
     - `CF.mbEmit1s(ctx.mb, Op.JvmOp.goto_, 0)` — placeholder.
  10. Capture `elseStart = CF.mbLength(ctx.mb)`.
  11. `CF.mbAddBranchTarget(ctx.mb, elseStart, None)` — stackmap at else-arm entry.
  12. `patchShort(code, ifeqPos + 1, elseStart - ifeqPos)` — backpatch IFEQ.
  13. `match (eOpt) { Some(e) => emitExpr(ctx, e) | None => CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, CF.cfFieldref(ctx.cf, KUNIT, "INSTANCE", "Lkestrel/runtime/KUnit;")) }`.
  14. `storeLocal(ctx, ifResultSlot)`.
  15. Capture `ifEndPos = CF.mbLength(ctx.mb)`.
  16. `CF.mbAddBranchTarget(ctx.mb, ifEndPos, None)` — stackmap at join point.
  17. If `thenArmPushesValue(t)`: `patchShort(code, gotoPos + 1, ifEndPos - gotoPos)` — backpatch GOTO.
  18. `loadLocalSlot(ctx, ifResultSlot)`.
- [ ] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`, replace the smoke "if emits" test with two or more opcode-level tests:
  - A test verifying that `if (True) 1 else 2` emits an `ifeq` opcode (opcode byte `153`) within the generated byte sequence.
  - A test verifying that the no-else arm form `if (True) unit` emits `getstatic` for `KUnit.INSTANCE` in the else path (opcode byte `178`).
- [ ] Add `tests/conformance/runtime/valid/if_branching.ks` with `println`-based golden stdout:
  - `if (True) println("yes") else println("no")` — expect `yes`.
  - `if (False) println("yes") else println("no")` — expect `no`.
  - `val x = 5; if (x > 3) println("big") else println("small")` — expect `big`.
  - `val r = if (True) 42 else 0; println(r)` — expect `42`.
  - No-else arm: `if (True) println("unit-arm")` — expect `unit-arm`.
- [ ] Run `cd compiler && npm run build && npm test`
- [ ] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel unit (codegen) | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Replace smoke test with opcode-level assertions: verify `ifeq` (opcode 153) is emitted in the then/else form; verify `KUnit.INSTANCE getstatic` (opcode 178) is present in the no-else fallback. |
| Conformance runtime | `tests/conformance/runtime/valid/if_branching.ks` | Happy-path branching: `True` takes then arm; `False` takes else arm; numeric condition branches correctly; no-else arm emits KUnit and does not crash. |

## Documentation and specs to update

- [ ] `docs/specs/01-language.md` — no functional change; confirm that the spec's existing `if` expression documentation remains accurate after this fix (no edit needed, but reviewer should check).
- [ ] `docs/specs/11-bootstrap.md` — no structural change; stackmap frame policy is unchanged. No edit needed, but confirm the policy comment in `codegen.ks` matches the spec intent.
