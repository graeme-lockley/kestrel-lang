# Fix KTI `serializeType` to write JSON object format

## Sequence: S17-40
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-41, S17-24 through S17-38, S17-42

## Summary

The self-hosted `serializeType` function in `stdlib/kestrel/tools/compiler/kti.ks` currently
serializes types by calling `Ty.typeToString(t)`, producing a human-readable string such as
`"forall 1 vars. ('0) -> '0"`. When another module reads that KTI with `deserializeType`, the
string-parsing fallback only recognises primitive types and simple arrow types; every other
form (schemes, type-application, records, tuples, unions, intersections, type vars) silently
deserialises as `tUnit`.

The TS bootstrap compiler serialises types as structured JSON objects (`{k:"scheme", vs:[0],
b:{k:"arrow", ps:[{k:"var",id:0}], r:{k:"var",id:0}}}`) and `deserializeTypeFromObj` in
`kti.ks` already parses that format correctly. The fix is to change `serializeType` to emit
the same structured JSON, making self-hosted-written KTI files binary-compatible with
bootstrap-written files.

Without this fix, any Kestrel source file compiled by the self-hosted driver that is then
imported by a second file will see all polymorphic types as `Unit`, causing cascading type
errors throughout multi-module self-hosted compilation.

## Current State

`stdlib/kestrel/tools/compiler/kti.ks` lines 49-51:

```kestrel
export fun serializeType(t: Ty.InternalType): Json.Value =
  StrVal(Ty.typeToString(t))
```

`deserializeType` (lines 65-88) handles both:
- `StrVal(s)` — string fallback: only parses `Int`, `Bool`, `String`, `Unit`, and simple
  single-`"->"` arrow types (via `parseNamedType`).
- `Object(ps)` — JSON-object path: `deserializeTypeFromObj` correctly handles all type forms
  using the `{k:"prim"|"var"|"arrow"|"record"|"app"|"tuple"|"union"|"inter"|"scheme", ...}`
  format that the TS compiler writes.

## Relationship to other stories

- **Depends on**: nothing (standalone KTI utility fix).
- **Blocks**: S17-42 (E2E gate) — multi-module self-hosted compilation produces wrong type
  bindings without this fix.
- **Companion**: S17-41 (freshen imported type vars — depends on correct serialisation).

## Goals

1. Replace the body of `serializeType` with a recursive encoder that emits `Object([...])`
   JSON values matching the TS `{k:"..."}` schema for every `InternalType` constructor:
   - `TPrim(name)` → `{k:"prim", n:name}`
   - `TVar(id)` → `{k:"var", id:id}`
   - `TArrow(ps, r)` → `{k:"arrow", ps:[...], r:{...}}`
   - `TRecord(fields, rowOpt)` → `{k:"record", fs:[{n,mut,t}...], row:null|{...}}`
   - `TApp(n, args)` → `{k:"app", n:n, as:[...]}`
   - `TTuple(es)` → `{k:"tuple", es:[...]}`
   - `TUnion(l, r)` → `{k:"union", l:{...}, r:{...}}`
   - `TInter(l, r)` → `{k:"inter", l:{...}, r:{...}}`
   - `TScheme(vars, body)` → `{k:"scheme", vs:[ints...], b:{...}}`
   - `TNamespace(_)` → runtime error or `{k:"prim", n:"Unit"}` (namespace types must never
     appear in exported types)
2. Remove the now-redundant `parseNamedType` / `parseTypeList` / `parseTypeList` string
   parsers from `kti.ks` (or leave them with a comment that they are no longer called from
   the write path, since `deserializeType` still uses its `StrVal` branch to read old files).
3. Verify that the KTI files written by the self-hosted compiler are valid JSON and parse
   correctly via `deserializeType`.

## Acceptance Criteria

- [ ] After this fix, a self-hosted-compiled module that exports a polymorphic function (e.g.
      `fun id(x) = x`) writes a KTI containing `{k:"scheme", vs:[0], b:{k:"arrow",...}}`
      rather than the string `"forall 1 vars. ('0) -> '0"`.
- [ ] A downstream module importing the above function receives the correct `TScheme` type via
      `loadDepBindings`, not `tUnit`.
- [ ] A round-trip unit test: `deserializeType(serializeType(t)) == t` for all `InternalType`
      constructors (primitives, vars, arrows, records, apps, tuples, unions, inters, schemes).
- [ ] Existing tests pass: `cd compiler && npm test` and `./scripts/kestrel test`.

## Spec References

- `docs/specs/kti-format.md` — KTI v4 format spec; type encoding described there.

## Risks / Notes

- The `StrVal` branch of `deserializeType` can be preserved for backward compatibility so
  that old/hand-written KTIs still parse without error.
- `TNamespace` types must never appear in KTI exports (they are internal scope-only types);
  the serialiser should throw or emit a safe placeholder, consistent with the TS compiler's
  `throw new Error('Internal error: namespace type cannot be serialized to .kti')`.
- The `mut` field on record fields may need to be surfaced — check `TypeField` in `types.ks`
  to see if mutability is tracked there (it may be `False` for all fields at the type level).
