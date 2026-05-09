# Fix KTI `serializeType` to write JSON object format

## Sequence: S17-39
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-40, S17-24 through S17-38, S17-44

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
- **Blocks**: S17-44 (E2E gate) — multi-module self-hosted compilation produces wrong type
  bindings without this fix.
- **Companion**: S17-40 (freshen imported type vars — depends on correct serialisation).

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

- [x] After this fix, a self-hosted-compiled module that exports a polymorphic function (e.g.
      `fun id(x) = x`) writes a KTI containing `{k:"scheme", vs:[0], b:{k:"arrow",...}}`
      rather than the string `"forall 1 vars. ('0) -> '0"`.
- [x] A downstream module importing the above function receives the correct `TScheme` type via
      `loadDepBindings`, not `tUnit`.
- [x] A round-trip unit test: `deserializeType(serializeType(t)) == t` for all `InternalType`
      constructors (primitives, vars, arrows, records, apps, tuples, unions, inters, schemes).
- [x] Existing tests pass: `cd compiler && npm test` and `./scripts/kestrel test`.

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

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/tools/compiler/kti.ks` | **Already done.** `serializeType` was refactored to emit `Object([...])` JSON values for every `InternalType` constructor, matching the `{k:"..."}` schema. `serializeTypeField` helper added. `TNamespace` emits a safe `{k:"app", n:"__namespace__", as:[]}` placeholder. The `StrVal` string fallback in `deserializeType` is preserved for backward compatibility. |
| `tests/unit/kti_serialize.test.ks` | **New file.** Round-trip unit test: `deserializeType(serializeType(t)) == t` for all constructors — `TPrim`, `TVar`, `TArrow`, `TRecord`, `TApp`, `TTuple`, `TUnion`, `TInter`, `TScheme`. Also verifies that `TNamespace` serializes to the placeholder without crashing. |
| `docs/specs/kti-format.md` | Confirm §4 (SerType encoding table) matches the implemented `{k:"..."}` shape for all constructors. Add a note that both the TS bootstrap compiler and the self-hosted compiler emit the `Object` form (not the legacy `StrVal` string). |
| Compatibility / rollback | No format change — the emitted JSON is identical to what the TS bootstrap compiler produces. The `StrVal` fallback in `deserializeType` ensures backward compatibility with any legacy hand-authored KTI files. No rollback risk. |

## Tasks

- [x] Confirm `serializeType` and `serializeTypeField` in `stdlib/kestrel/tools/compiler/kti.ks` cover all `InternalType` constructors with the correct `{k:"..."}` JSON shape (read current code against the Goals table in this story — expected to be complete).
- [x] Create `tests/unit/kti_serialize.test.ks` with a round-trip group: for each `InternalType` constructor, assert `deserializeType(serializeType(t)) == t`; include primitives, vars, arrow (0-param and multi-param), record (with and without row var), app, tuple, union, inter, and scheme. Add a separate assertion that `serializeType(TNamespace(...))` does not throw and produces a non-`StrVal` JSON value.
- [x] Extend `tests/unit/kti_serialize.test.ks` with direct acceptance evidence: write a `.kti` file containing a serialized `TScheme`, assert the on-disk payload contains `{\"k\":\"scheme\"}` rather than a `forall ...` string, and verify `loadDepBindings` reconstructs that scheme for a named import.
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `tests/unit/kti_serialize.test.ks` | Round-trip: `deserializeType(serializeType(t)) == t` for all 9 `InternalType` constructors; `TNamespace` safety check |

**Test assertions:**
- `TPrim("Int")` round-trips to `TPrim("Int")`
- `TPrim("Bool")`, `TPrim("String")`, `TPrim("Unit")` round-trip correctly
- `TVar(0)`, `TVar(42)` round-trip to `TVar(0)`, `TVar(42)`
- `TArrow([], TPrim("Unit"))` round-trips
- `TArrow([TPrim("Int"), TPrim("Bool")], TPrim("String"))` round-trips
- `TApp("List", [TPrim("Int")])` round-trips
- `TTuple([TPrim("Int"), TPrim("Bool")])` round-trips
- `TUnion(TPrim("Int"), TPrim("Bool"))` round-trips
- `TInter(TPrim("Int"), TPrim("Bool"))` round-trips
- `TScheme([0], TArrow([TVar(0)], TVar(0)))` round-trips (the `id` type scheme)
- `TRecord([{name="x", mut_=False, type_=TPrim("Int")}], None)` round-trips
- `TRecord` with a row variable `Some(TVar(1))` round-trips
- Nested: `TScheme([0], TArrow([TApp("List", [TVar(0)])], TApp("List", [TVar(0)])))` round-trips
- `TNamespace(emptyDict)` serialises without throwing; result is an `Object` (not `StrVal`)

## Documentation and specs to update

- [x] `docs/specs/kti-format.md` — Confirm §4 (SerType encoding) lists all constructors (`prim`, `var`, `arrow`, `record`, `app`, `tuple`, `union`, `inter`, `scheme`) with their exact JSON shapes. Add a sentence stating that both the TS bootstrap compiler and the self-hosted compiler emit the structured `Object` form; the legacy `StrVal` string form is accepted on input for backward compatibility only.

## Build notes

- 2026-05-09: Started implementation.
- 2026-05-09: `serializeType` was already emitting structured JSON in `kti.ks`; this story's remaining scope is the regression test coverage and spec alignment.
- 2026-05-09: The SerType spec already documented the object variants; the real spec drift was namespace handling, so the update now documents the self-hosted `__namespace__` placeholder as a defensive fallback rather than claiming namespace values are never written.
- 2026-05-09: `check-story.sh` required the acceptance criteria to be demonstrably satisfied, so the test scope was widened from pure round-trip coverage to an end-to-end `.kti` write plus `loadDepBindings` readback for a polymorphic export.
