# Self-hosted codegen: `EBinary` and `EUnary` operator emission

## Sequence: S17-26
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24, S17-25, S17-27 through S17-38, S17-42

## Summary

The self-hosted codegen emits both operands of `EBinary` and `EUnary` but then discards
them and pushes `null`. No arithmetic, comparison, equality, boolean short-circuit, or
string-concatenation is ever computed. This makes virtually every function body that
performs computation produce the wrong value.

## Current State

```kestrel
EBinary(_op, l, r) => {
  emitExpr(ctx, l); CF.mbEmit1(ctx.mb, Op.JvmOp.pop);
  emitExpr(ctx, r); CF.mbEmit1(ctx.mb, Op.JvmOp.pop);
  pushNull(ctx)
}
EUnary(_op, e) => { emitExpr(ctx, e); CF.mbEmit1(ctx.mb, Op.JvmOp.pop); pushNull(ctx) }
```

The TS reference handles all operators in `'BinaryExpr'` (~300 lines):
- `&` / `|` — short-circuit boolean with `CHECKCAST Boolean; INVOKEVIRTUAL booleanValue;
  IFEQ/IFNE; GETSTATIC TRUE/FALSE`.
- `==` — `INVOKESTATIC KObject.equals(Object,Object)`.
- `!=` — same as `==`, then negate.
- `<`, `>`, `<=`, `>=` — `INVOKESTATIC KObject.compare`, then `IFLT/IFGT/IFLE/IFGE`.
- `+`, `-`, `*`, `/`, `%` — unbox both sides to `long`/`double`, apply opcode, rebox.
- `++` (string append) — `INVOKESTATIC KString.append(Object,Object)`.
- `!` (unary not) — unbox boolean, `IFEQ`, rebox.
- `-` (unary negate) — unbox long/double, `LNEG`/`DNEG`, rebox.

## Relationship to other stories

- **Depends on**: S17-24 (literal emission helpers), S17-25 (EIdent resolution to produce
  correct operand values).
- **Blocks**: S17-42 (E2E). Without operators, no comparison, arithmetic, or boolean logic
  works in self-hosted-compiled code.

## Goals

1. Add a real `EBinary(op, l, r)` arm that dispatches on `op`:
   - Boolean short-circuit (`&`, `|`): emit conditional branches, produce boxed Boolean.
   - Equality (`==`, `!=`): call `KObject.equals`.
   - Order comparison (`<`, `>`, `<=`, `>=`): call `KObject.compare`, branch on int result.
   - Arithmetic (`+`, `-`, `*`, `/`, `%`): unbox operands to long/double, apply JVM
     arithmetic opcode, rebox.
   - String append (`++`): call `KString.append`.
2. Add a real `EUnary(op, e)` arm:
   - `!`: unbox to boolean, `IFEQ`, push `TRUE`/`FALSE`.
   - `-`: unbox to long or double (type-driven), apply `LNEG`/`DNEG`, rebox.
3. Preserve correct stack depth and JVM frame state after each operator.

## Acceptance Criteria

- [ ] `1 + 2` compiles to bytecode that produces `3` at runtime.
- [ ] `"hello" ++ " world"` compiles and concatenates correctly.
- [ ] `a == b` compiles to a boolean comparison that returns `True`/`False`.
- [ ] `a < b` compiles and the comparison produces the correct boolean.
- [ ] `!True` compiles and produces `False`.
- [ ] `-42` compiles and produces `-42`.
- [ ] Boolean short-circuit `(f() & g())` only evaluates `g` when `f` is `True`.
- [ ] New codegen unit tests cover every operator kind.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — binary and unary operator semantics
- `docs/specs/06-typesystem.md` — overloaded operator types

## Risks / Notes

- Type context is needed to decide whether arithmetic is integer or float. The typechecker
  inferred types may not be available at codegen time without a richer `CodegenContext`. Verify
  whether the TS compiler uses inferred types or heuristics (e.g. both operands boxed as
  Long/Double, dispatched at runtime via a helper).
- The runtime helpers `KObject`, `KString` class names and method signatures must match the
  JVM runtime exactly.
