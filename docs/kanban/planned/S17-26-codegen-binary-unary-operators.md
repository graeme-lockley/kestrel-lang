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
- **Recommended after**: the S17-25 + S17-37 execution tranche, so operator results flow through
  real global/module startup instead of the temporary startup shim.
- **Feeds**: S17-30, S17-31, S17-34, and the first positive E2E re-enable slice (core async/task
  and basic computation-heavy scenarios).
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
  inferred types may not be available at codegen time without a richer `CodegenContext`. Verified:
  the TS codegen uses `getInferredType(expr)` from `TypecheckResult`; the self-hosted codegen
  must thread this through `jvmCodegen` → `CodegenContext` (see Tasks).
- The runtime helpers `KObject`, `KString` class names and method signatures must match the
  JVM runtime exactly. Verified: string append is `KRuntime.concat(Object,Object):String` (not
  `KString.append`); equality is `KRuntime.equals(Object,Object):Boolean`; arithmetic and
  comparisons go through `KMath` static methods.
- This story is part of the "make expressions compute real values again" tranche. Do not use E2E
  unskips as the primary verification here; add focused operator tests first, then re-enable the
  positive scenarios that actually depend on them.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/tools/compiler/codegen.ks` | Core change. (1) Add `import * as Ty from "kestrel:dev/typecheck/types"`. (2) Add `getInferredType: (Ast.Expr) -> Option<Ty.InternalType>` field to `CodegenContext`. (3) Add `noTypeInfo` constant. (4) Update `newCodegenContext` signature (4th param). (5) Update 3 internal callers to pass `noTypeInfo`. (6) Update `jvmCodegen` signature to accept `getInferredType`. (7) Add `patchShort`, `jvmMangleName`, `primNameFromType` helpers. (8) Implement `emitUnaryExpr` and `emitBinaryExpr`. (9) Replace 2 stub match arms. |
| `stdlib/kestrel/tools/compiler/driver.ks` | Update single `Codegen.jvmCodegen(mctx, prog)` call to pass `tcResult.getInferredType` as third argument. |
| `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Update 3 `CG.newCodegenContext` call sites to pass `CG.noTypeInfo`; add 7+ new test groups covering each operator class. |
| JVM runtime (`runtime/jvm/`) | No changes required. `KRuntime.concat`, `KRuntime.equals`, and all `KMath` methods already exist. |
| TS compiler (`compiler/`) | No changes. Reference only. |
| Specs / docs | No language-visible behaviour changes; spec text does not need updating. |
| **Risk: type dispatch** | `getInferredType` returns `None` for extern-fun stubs, lambda stubs, and unit-test contexts; `primNameFromType(None)` returns `"Other"` which is safe because those paths never emit arithmetic. |
| **Risk: runtime method names** | `KRuntime.concat(Object,Object):String` is the actual string-append method (not `KString.append`). `KMath` comparison methods are JVM-mangled: `$less`, `$less$eq`, `$greater`, `$greater$eq`; float variants append `Float` (`$lessFloat`, `$less$eqFloat`, `$greaterFloat`, `$greater$eqFloat`). |

## Tasks

- [ ] Add `import * as Ty from "kestrel:dev/typecheck/types"` to `codegen.ks`.
- [ ] Add `getInferredType: (Ast.Expr) -> Option<Ty.InternalType>` field to `CodegenContext` record type in `codegen.ks`.
- [ ] Add exported constant `val noTypeInfo: (Ast.Expr) -> Option<Ty.InternalType> = (_: Ast.Expr) => None` in `codegen.ks`.
- [ ] Update `newCodegenContext` to accept `getInferredType` as a 4th parameter and store it in the returned `CodegenContext`.
- [ ] Update the 3 internal callers of `newCodegenContext` in `codegen.ks` (in `emitFunDecl` ~line 313, `emitExternFun` ~line 345, `emitExternOverride` ~line 353) to pass `noTypeInfo`.
- [ ] Update `jvmCodegen(mctx, prog)` to `jvmCodegen(mctx, prog, getInferredType)` and thread the new parameter through to the `newCodegenContext` call for function declarations.
- [ ] Update `driver.ks`: change `Codegen.jvmCodegen(mctx, prog)` to `Codegen.jvmCodegen(mctx, prog, tcResult.getInferredType)`.
- [ ] Update the 3 `CG.newCodegenContext(cf, mb, mctx)` call sites in `codegen-expr.test.ks` to pass `CG.noTypeInfo` as the 4th argument.
- [ ] Add helper `fun patchShort(code: Array<Int>, pos: Int, offset: Int): Unit` in `codegen.ks` that writes high byte of `offset` to `code[pos]` and low byte to `code[pos+1]` via `Arr.set`.
- [ ] Add helper `fun jvmMangleName(op: String): String` in `codegen.ks` mapping `<` → `$less`, `>` → `$greater`, `<=` → `$less$eq`, `>=` → `$greater$eq`; identity for anything else.
- [ ] Add helper `fun primNameFromType(t: Option<Ty.InternalType>): String` in `codegen.ks` returning `"Int"` for `Some(TPrim("Int"))`, `"Float"` for `Some(TPrim("Float"))`, `"Char"` for `Some(TPrim("Char"))` or `Some(TPrim("Rune"))`, and `"Other"` for all other cases.
- [ ] Implement `fun emitUnaryExpr(ctx: CodegenContext, op: String, e: Ast.Expr): Unit` in `codegen.ks`: for `!` emit operand, `GETSTATIC Boolean.TRUE`, `IF_ACMPEQ` to false-label, push `TRUE`, `GOTO` end-label, false-label push `FALSE`, end-label (register both with `mbAddBranchTarget`); for `-` with Int push `Long.valueOf(0L)`, emit operand, `CHECKCAST Long`, `INVOKESTATIC KMath.sub`; for `-` with Float push `Double.valueOf(0.0)`, emit operand, `CHECKCAST Double`, `INVOKESTATIC KMath.subFloat`.
- [ ] Implement `fun emitBinaryExpr(ctx: CodegenContext, op: String, left: Ast.Expr, right: Ast.Expr): Unit` in `codegen.ks` covering: `&` / `|` short-circuit boolean with `CHECKCAST Boolean`, `INVOKEVIRTUAL booleanValue`, `IFEQ`/`IFNE` branches back-patched via `patchShort`; `==` via `INVOKESTATIC KRuntime.equals`; `!=` via `KRuntime.equals` + negation branch; `<`/`>`/`<=`/`>=` for Int via `KMath.$less` etc., for Float via `KMath.$lessFloat` etc.; arithmetic `+`/`-`/`*`/`/`/`%`/`**` for Int via `KMath.add/sub/mul/div/mod/pow`, for Float via `KMath.addFloat/subFloat/mulFloat/divFloat/powFloat`; `++` via `INVOKESTATIC KRuntime.concat(Object,Object)`.
- [ ] Replace `EBinary(_op, l, r)` null-push stub with `EBinary(op, l, r) => emitBinaryExpr(ctx, op, l, r)` in `emitExpr`.
- [ ] Replace `EUnary(_op, e)` null-push stub with `EUnary(op, e) => emitUnaryExpr(ctx, op, e)` in `emitExpr`.
- [ ] Add test groups in `codegen-expr.test.ks` covering each operator kind (see Tests to add).
- [ ] Run `cd compiler && npm run build && npm test`.
- [ ] Run `./scripts/kestrel test`.
- [ ] Run `./scripts/run-e2e.sh`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Codegen unit | `codegen-expr.test.ks` — int add | `EBinary("+", ELit("int","1"), ELit("int","2"))` emits `invokestatic(184)` and pool contains `KMath` UTF-8 bytes. |
| Codegen unit | `codegen-expr.test.ks` — string concat | `EBinary("++", ELit("string","hello"), ELit("string","world"))` emits `invokestatic(184)` and pool contains `concat` UTF-8 bytes. |
| Codegen unit | `codegen-expr.test.ks` — equality | `EBinary("==", ELit("int","1"), ELit("int","1"))` emits `invokestatic(184)` and pool contains `equals` UTF-8 bytes. |
| Codegen unit | `codegen-expr.test.ks` — inequality | `EBinary("!=", ELit("int","1"), ELit("int","2"))` produces bytecode of non-zero length containing a branch opcode. |
| Codegen unit | `codegen-expr.test.ks` — comparison | `EBinary("<", ELit("int","1"), ELit("int","2"))` emits `invokestatic(184)` and pool contains `$less` UTF-8 bytes. |
| Codegen unit | `codegen-expr.test.ks` — unary not | `EUnary("!", ELit("true","True"))` emits `getstatic(178)` and pool contains `FALSE` UTF-8 bytes. |
| Codegen unit | `codegen-expr.test.ks` — unary negate | `EUnary("-", ELit("int","5"))` emits `invokestatic(184)` and pool contains `sub` UTF-8 bytes (via KMath). |
| Codegen unit | `codegen-expr.test.ks` — short-circuit and | `EBinary("&", ELit("true","True"), ELit("true","True"))` produces bytecode containing two `getstatic(178)` refs (TRUE and FALSE). |
| Codegen unit | `codegen-expr.test.ks` — short-circuit or | `EBinary("|", ELit("false","False"), ELit("true","True"))` produces bytecode containing two `getstatic(178)` refs (TRUE and FALSE). |

## Documentation and specs to update

- [ ] `docs/specs/01-language.md` — review binary and unary operator sections; no wording changes expected but confirm self-hosted codegen is consistent with spec.
- [ ] `docs/specs/06-typesystem.md` — review overloaded operator type rules; no wording changes expected.
