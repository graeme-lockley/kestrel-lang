# Self-hosted codegen: `EField`, `ERecord`, spread, and mutable-field assignment

## Sequence: S17-28
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-27, S17-29 through S17-38, S17-41

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
- **Blocks**: S17-41 (E2E). Records are used everywhere.

## Goals

1. `EField(obj, name)`: emit `CHECKCAST KRecord; LDC name; INVOKEVIRTUAL get`.
2. `ERecord(None, fields)`: emit `NEW KRecord; DUP; INVOKESPECIAL <init>;` then for each
   field `LDC key; <emit value>; INVOKEVIRTUAL put; POP` (KRecord returns self from put).
3. `ERecord(Some(spread), fields)`: emit spread, `CHECKCAST KRecord; INVOKEVIRTUAL clone;`
   then overwrite each named field.
4. `SAssign` targeting `EField(obj, name)` in `emitBlockStmt`: emit object, `CHECKCAST
   KRecord; LDC name; <emit value>; INVOKEVIRTUAL put; POP`.
5. Mutable `var` boxing: module-level and local `var` values are wrapped in a single-field
   `KRecord` with key `"0"`. `ALOAD slot; CHECKCAST KRecord; LDC "0"; GETSTATIC/...` for
   reading; `ALOAD slot; CHECKCAST KRecord; LDC "0"; <val>; INVOKEVIRTUAL put; POP` for
   writing.

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

- `KRecord.put` returns the record (fluent API) or void — check the runtime signature
  exactly so the stack is correct after each put call.
- Spread + mutable-field interaction: ensure the cloned KRecord is fully independent
  (shallow copy suffices if fields are boxed Objects).
- This story is also a prerequisite for removing the placeholder-null execution behavior from many
  record-heavy test modules; use it to unlock the fs/process positive E2E slice after core call
  emission is stable.
