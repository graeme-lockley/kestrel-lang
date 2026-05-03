# Self-hosted codegen: `EField`, `ERecord`, spread, and mutable-field assignment

## Sequence: S17-28
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-27, S17-29 through S17-38, S17-44

## Summary

The self-hosted codegen stubs both `EField` (field access) and `ERecord` (record
construction): `EField` evaluates the object, discards it, and pushes `null`; `ERecord`
evaluates all fields, discards them, and pushes `null`. Records are the central value type
in Kestrel — virtually every data structure uses them — so the entire stdlib and all
user programs that create or read records are broken.

## Current State

```kestrel
EField(obj, _field) => { emitExpr(ctx, obj); CF.mbEmit1(ctx.mb, Op.JvmOp.pop); pushNull(ctx) }
ERecord(spreadOpt, fields) => {
  match (spreadOpt) { Some(sp) => { emitExpr(ctx, sp); pop } None => () }
  emitExprList(ctx, Lst.map(fields, (f) => f.value)); pushNull(ctx)
}
```

TS reference:
- `EField`: `CHECKCAST KRecord; LDC fieldName; INVOKEVIRTUAL KRecord.get(String)Object`.
- `ERecord` (no spread): `NEW KRecord; DUP; INVOKESPECIAL <init>; LDC k; <val>; INVOKEVIRTUAL
  put(String, Object)` for each field.
- `ERecord` (spread): clone-and-update pattern — `CHECKCAST KRecord; INVOKEVIRTUAL clone()KRecord;`
  then overwrite each named field.
- Mutable-field `SAssign` targeting a field: `CHECKCAST KRecord; LDC k; <val>; INVOKEVIRTUAL put`.

## Relationship to other stories

- **Depends on**: S17-27 (`ECall` — `KRecord` construction uses `INVOKESPECIAL`; field access
  uses `INVOKEVIRTUAL`).
- **Recommended early in the tranche**: records are needed before most stdlib-backed positive
  E2Es can be re-enabled, especially fs/process/http result-handling scenarios.
- **Blocks**: S17-44 (E2E). Records are used everywhere.

## Goals

1. `EField(obj, name)`: emit `CHECKCAST KRecord; LDC name; INVOKEVIRTUAL get`.
2. `ERecord(None, fields)`: emit `NEW KRecord; DUP; INVOKESPECIAL <init>;` then for each
   field `DUP; LDC key; <emit value>; INVOKEVIRTUAL set` (set returns void).
3. `ERecord(Some(spread), fields)`: emit spread, `CHECKCAST KRecord; INVOKEVIRTUAL copy;`
   then overwrite each named field.
4. `SAssign` targeting `EField(obj, name)` in `emitBlockStmt`: emit RHS to temp slot,
   emit object, `CHECKCAST KRecord; LDC name; ALOAD temp; INVOKEVIRTUAL set`.
5. Mutable `var` boxing: local `var` values are wrapped in a single-field `KRecord` with
   key `"0"`. `SVar` boxing: NEW KRecord + DUP + INVOKESPECIAL + DUP + LDC "0" + ALOAD rhs +
   INVOKEVIRTUAL set + ASTORE slot. Reading: after `loadLocal`, if name is in `varLocals`,
   call `emitVarUnbox`. Writing via `SAssign` on a var-local: ALOAD box, CHECKCAST KRecord,
   LDC "0", emit rhs, INVOKEVIRTUAL set. Module-level var boxing is handled in S17-37.

## Acceptance Criteria

- [ ] `{ x = 1, y = 2 }.x` compiles and evaluates to `1`.
- [ ] `{ ...base, x = 3 }` compiles and the spread fields are preserved.
- [ ] Assigning `r.x = 10` (where `r` has a mutable field `x`) mutates the field in place.
- [ ] A local `var n = 0; n = n + 1` compiles correctly using the KRecord boxing scheme.
- [ ] New codegen unit tests cover field read, record construction (with and without spread),
      and mutable field assignment.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — record expressions and field access
- `docs/specs/06-typesystem.md` — mutable record fields

## Risks / Notes

- `KRecord.set` returns `void` (not the record — it is not a fluent API). The TS codegen
  emits `INVOKEVIRTUAL set(String,Object)V` with no POP after it. Confirm the descriptor
  `(Ljava/lang/String;Ljava/lang/Object;)V` matches `KRecord.set` before emitting.
- `KRecord.copy()` returns a new `KRecord` that shallow-copies all fields — sufficient for
  Kestrel value semantics since fields are boxed `Object` references.
- `CodegenContext` currently has no `varLocals` tracking. Adding
  `varLocals: mut Dict<String, Unit>` is a prerequisite for correct `SVar` boxing and
  the corresponding `EIdent` unboxing for local vars. This is a structural change to the
  `CodegenContext` type and all call-sites that construct it (`newCodegenContext`,
  `emitFunDecl`, and any internal context construction).
- Spread + mutable-field interaction: ensure the cloned KRecord is fully independent
  (shallow copy suffices if fields are boxed Objects).
- This story is also a prerequisite for removing the placeholder-null execution behavior
  from many record-heavy test modules; use it to unlock the fs/process positive E2E slice
  after core call emission is stable.
- Module-level `var` boxing (wrapping in KRecord inside the `$init` method) is deferred
  to S17-37 (global lazy init). This story covers only local-scope `var` boxing.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/tools/compiler/codegen.ks` — `CodegenContext` type | Add `varLocals: mut Dict<String, Unit>` field to track KRecord-boxed local vars. |
| `stdlib/kestrel/tools/compiler/codegen.ks` — `newCodegenContext` | Initialize `varLocals = Dict.emptyStringDict()`. |
| `stdlib/kestrel/tools/compiler/codegen.ks` — `EIdent` in `emitExpr` | After successful `loadLocal`, check `ctx.varLocals` and call `emitVarUnbox(ctx)` if the name is a var local. |
| `stdlib/kestrel/tools/compiler/codegen.ks` — `SVar` in `emitBlockStmt` | Replace simple store with KRecord boxing: evaluate RHS into a temp slot, NEW KRecord, set key "0", ASTORE named slot, insert name into `ctx.varLocals`. |
| `stdlib/kestrel/tools/compiler/codegen.ks` — `SAssign` in `emitBlockStmt` | Replace stub with: (a) var-local target → load KRecord box, CHECKCAST, LDC "0", emit rhs, INVOKEVIRTUAL set; (b) FieldExpr target → emit rhs to temp, emit object, CHECKCAST KRecord, LDC fieldname, ALOAD temp, INVOKEVIRTUAL set. |
| `stdlib/kestrel/tools/compiler/codegen.ks` — `EField` in `emitExpr` (non-namespace path) | Replace pop+pushNull stub with: `emitExpr obj; CHECKCAST KRecord; LDC_W fieldName; INVOKEVIRTUAL get(String)Object`. |
| `stdlib/kestrel/tools/compiler/codegen.ks` — `ERecord` in `emitExpr` | Replace stub with: no-spread path (NEW KRecord + INVOKESPECIAL + per-field DUP+LDC+emitExpr+INVOKEVIRTUAL set); spread path (emitExpr spread + CHECKCAST + INVOKEVIRTUAL copy + per-field overwrite). |
| JVM runtime (`runtime/jvm/src/kestrel/runtime/KRecord.java`) | No change. `set(String,Object):void`, `get(String):Object`, and `copy():KRecord` already exist with the exact signatures needed. |
| TS reference compiler (`compiler/src/jvm-codegen/codegen.ts`) | No change. Read-only reference for emission patterns. |
| Conformance tests | Add `tests/conformance/runtime/valid/conform_record_basic.ks` (record create + field read) and `tests/conformance/runtime/valid/conform_record_mutable_field.ks` (mutable field write + read). Existing tests `conform_record_spread.ks`, `while_count.ks`, and `conform_closure_val_vs_var.ks` cover acceptance criteria 2 and 4 once codegen is correct. |
| Kestrel harness tests | Extend `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` with groups for EField, ERecord (no spread), ERecord (spread), SVar boxing, SAssign var-local, SAssign field-expr. |

## Tasks

- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks`, add `varLocals: mut Dict<String, Unit>` field to the `CodegenContext` type definition (after `nextLocal`).
- [ ] Update `newCodegenContext` in `codegen.ks` to initialize `mut varLocals = Dict.emptyStringDict()`.
- [ ] Update the `EIdent` branch in `emitExpr` (`codegen.ks`): after `loadLocal(ctx, name)` succeeds (returns `True`), check `Dict.member(ctx.varLocals, name)` and call `emitVarUnbox(ctx)` if true; otherwise do nothing.
- [ ] Update the `SVar` branch in `emitBlockStmt` (`codegen.ks`):
  1. Evaluate RHS with `emitExpr(ctx, e)`.
  2. Allocate a temp slot (`ctx.nextLocal`) and `ASTORE` the RHS value into it.
  3. `NEW KRecord; DUP; INVOKESPECIAL <init>`.
  4. `DUP; LDC_W "0"; ALOAD tempSlot; INVOKEVIRTUAL set(String,Object)V`.
  5. Bind the named local via `bindLocal(ctx, name)` and `storeLocal(ctx, idx)`.
  6. Insert `name` into `ctx.varLocals` via `ctx.varLocals := Dict.insert(ctx.varLocals, name, ())`.
- [ ] Update the `SAssign` branch in `emitBlockStmt` (`codegen.ks`) to replace the stub:
  - Pattern-match on the target:
    - `SAssign(IdentExpr(name), rhs)` where `Dict.member(ctx.varLocals, name)`:  emit `rhs` to a temp slot; `loadLocalSlot(ctx, slot); CHECKCAST KRecord; LDC_W "0"; ALOAD temp; INVOKEVIRTUAL set(String,Object)V`.
    - `SAssign(IdentExpr(name), rhs)` where name is a plain val-local (in `ctx.locals` but not `varLocals`): emit `rhs`, `storeLocal(ctx, idx)`.
    - `SAssign(FieldExpr(obj, field), rhs)`: emit `rhs` to a temp slot; `emitExpr(ctx, obj); CHECKCAST KRecord; LDC_W field; ALOAD temp; INVOKEVIRTUAL set(String,Object)V`.
    - Fallback (target not recognized): emit `rhs` and `POP` (keep stub behavior for unknown targets).
- [ ] Update the `EField` fallback case in `emitExpr` (`codegen.ks`) (the non-namespace path that currently does `pop; pushNull`): replace with `emitExpr(ctx, obj); CHECKCAST KRecord; LDC_W fieldName; INVOKEVIRTUAL get(String)Object`.
- [ ] Update `ERecord` in `emitExpr` (`codegen.ks`):
  - No-spread path: `NEW KRecord; DUP; INVOKESPECIAL <init>; for each field: DUP; LDC_W f.name; emitExpr(ctx, f.value); INVOKEVIRTUAL set(String,Object)V`.
  - Spread path: `emitExpr(ctx, sp); CHECKCAST KRecord; INVOKEVIRTUAL copy()KRecord; for each field: DUP; LDC_W f.name; emitExpr(ctx, f.value); INVOKEVIRTUAL set(String,Object)V`.
- [ ] Add test group `"ERecord no-spread creates KRecord"` to `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`: verify opcode `new_` (187) appears at offset 0, and constant pool contains the UTF-8 bytes for `"KRecord"`.
- [ ] Add test group `"ERecord spread calls copy"` to `codegen-expr.test.ks`: construct a spread record with one field override; verify constant pool contains the UTF-8 bytes for `"copy"`.
- [ ] Add test group `"EField emits get invokevirtual"` to `codegen-expr.test.ks`: record with a known field, then EField access; verify `invokevirtual` (182) appears in emitted code and constant pool contains UTF-8 bytes for `"get"`.
- [ ] Add test group `"SVar boxes in KRecord"` to `codegen-expr.test.ks` (or `codegen-decl.test.ks`): emit a `SVar` statement via `emitBlockStmt`; verify `new_` (187) appears and constant pool contains `"KRecord"`.
- [ ] Add test group `"SAssign var-local updates KRecord box"` in `codegen-expr.test.ks`: emit `SVar` then `SAssign` on same name; verify `invokevirtual` (182) + `"set"` in constant pool.
- [ ] Add test group `"SAssign field-expr updates KRecord field"` in `codegen-expr.test.ks`: emit an `SAssign` with `FieldExpr` target; verify `invokevirtual` (182) + `"set"` in constant pool.
- [ ] Add `tests/conformance/runtime/valid/conform_record_basic.ks` asserting `{ x = 1, y = 2 }.x` prints `1` and `{ a = "hi" }.a` prints `"hi"`.
- [ ] Add `tests/conformance/runtime/valid/conform_record_mutable_field.ks` asserting that assigning to a mutable field updates the stored value and subsequent reads see the new value.
- [ ] Run `cd compiler && npm run build && npm test`
- [ ] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `ERecord` no-spread: opcode 187 (`new_`) at offset 0; pool contains `"KRecord"` UTF-8 |
| Kestrel harness | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `ERecord` spread: pool contains `"copy"` UTF-8 |
| Kestrel harness | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `EField`: opcode 182 (`invokevirtual`) present; pool contains `"get"` UTF-8 |
| Kestrel harness | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `SVar` boxing: opcode 187 (`new_`) present; pool contains `"KRecord"` UTF-8 |
| Kestrel harness | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `SAssign` var-local: opcode 182 + pool contains `"set"` UTF-8 |
| Kestrel harness | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | `SAssign` field-expr: opcode 182 + pool contains `"set"` UTF-8 |
| Conformance runtime | `tests/conformance/runtime/valid/conform_record_basic.ks` | Record construction + field read: `{ x = 1, y = 2 }.x` → `1`; `{ a = "hi" }.a` → `"hi"` |
| Conformance runtime | `tests/conformance/runtime/valid/conform_record_mutable_field.ks` | Mutable field assignment: `r.x := 42` then read `r.x` → `42` |
| Conformance runtime (existing) | `tests/conformance/runtime/valid/conform_record_spread.ks` | Spread record: existing test verifies spread fields propagate; passes once `ERecord` spread emits correctly |
| Conformance runtime (existing) | `tests/conformance/runtime/valid/while_count.ks` | Local `var` boxing + `:=` assignment: existing while-loop test with `var i = 0; i := i + 1` |
| Conformance runtime (existing) | `tests/conformance/runtime/valid/conform_closure_val_vs_var.ks` | Local `var` boxing + closure capture: existing test with `var counter = 20; counter := 99` |

## Documentation and specs to update

- [ ] `docs/specs/01-language.md` — verify §3.6 (records, field access, spread) and §3.3 (assignment `r.f := v`) accurately describe what the self-hosted codegen now emits; no prose change expected but confirm nothing contradicts the KRecord boxing scheme.
- [ ] `docs/specs/06-typesystem.md` — verify §2 (mutable fields) and §8 (SET_FIELD constraint) match the implemented KRecord-based mutable field assignment; no prose change expected unless a discrepancy is found.
