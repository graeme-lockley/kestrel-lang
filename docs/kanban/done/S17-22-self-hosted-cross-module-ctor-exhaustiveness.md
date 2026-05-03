# Cross-module ADT constructor environment for the self-hosted typechecker

## Sequence: S17-22
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-16, S17-17, S17-18, S17-19, S17-20, S17-21, S17-23

## Summary

Today the self-hosted typechecker populates `adtConstructors` and `ctorOwners` only from ADT
declarations encountered **locally** in the module being checked. Constructors imported from
other modules are visible as plain values (because `exportedConstructors` is merged into
`functions` in the KTI) but the **exhaustiveness checker** does not know which constructors
belong to which imported ADT, so:

- Pattern matching against an imported ADT cannot detect missing arms reliably.
- Direct use of imported constructors in patterns may emit "Unknown constructor" diagnostics
  in some situations (the symptom seen during S17-13 with `DKFun` / `DKExternFun` /
  `DKType` from `kestrel:dev/doc/extract`).

This story closes the gap by populating `adtConstructors` and `ctorOwners` from the imported
KTIs so the self-hosted checker has a complete constructor universe.

## Current State

- KTI now records `exportedConstructors` and `types` (after the in-flight session work in
  `kti.ks`). `loadDepBindings` returns a `DepBindingBundle` with `importBindings`,
  `typeAliasBindings`, and `importOpaqueTypes`, but **not** an `importCtorEnv` /
  `importAdtConstructors` / `importCtorOwners`.
- `typecheck.ks` `emptyTypeRegistry` initializes `adtConstructors`, `ctorOwners`, and
  `ctorEnv` to empty dicts; only local `registerTypeDecl` calls populate them.
- The TS typechecker (reference) does receive a flat constructor → owning-type map for
  imported ADTs and uses it both during `PCon` inference and exhaustiveness analysis.

## Relationship to other stories

- **Depends on**: S17-16/S17-17/S17-19/S17-20 (so the producer side actually emits complete
  constructor and visibility information into KTI).
- **Blocks**: S17-23 (E2E) wherever cross-module pattern matching is required (which is
  most of the stdlib).
- **Companion**: S17-21.

## Goals

1. Extend `DepBindingBundle` (in `kti.ks`) with three additional fields:
   - `importCtorEnv: Dict<String, Ty.InternalType>` — ctor name → generalized arrow type.
   - `importAdtConstructors: Dict<String, List<String>>` — owning type name → ordered ctor
     names.
   - `importCtorOwners: Dict<String, String>` — ctor name → owning type name.
2. Populate these fields from each dep KTI's `exportedConstructors` / `types` sections
   inside `loadDepBindings`.
3. Extend `TypecheckOptions` with corresponding `Option` inputs and have `driver.ks` pass
   them through alongside the existing `importBindings` / `typeAliasBindings` /
   `importOpaqueTypes`.
4. Update `emptyTypeRegistry` and the registry construction path in `typecheck.ks` to seed
   `ctorEnv`, `adtConstructors`, and `ctorOwners` from these inputs **before** local type
   prebinding runs.
5. Verify exhaustiveness checking now sees imported constructors (a `match` over an imported
   ADT with an incomplete set of arms emits a `non_exhaustive` diagnostic).

## Acceptance Criteria

- [x] A program that pattern matches against an imported ADT (e.g. `DocKind` from
      `kestrel:dev/doc/extract`) typechecks without emitting "Unknown variable" / "Unknown
      constructor" diagnostics under the self-hosted checker.
- [x] An incomplete `match` against an imported ADT raises the same exhaustiveness
      diagnostic that the TS compiler does.
- [x] `stdlib/kestrel/dev/doc/sig.ks` typechecks end-to-end via the self-hosted checker (the
      observed `DKFun` / `DKExternFun` / `DKType` failures from the S17-13 pre-mortem are
      gone).
- [x] New unit tests cover both happy-path imported-ctor pattern matching and the
      exhaustiveness diagnostic for imported ADTs.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/06-typesystem.md` — exhaustiveness rules
- `docs/specs/07-modules.md` — exported types and visibility

## Risks / Notes

- Constructor name collisions between modules (rare but possible) must be handled
  deterministically; mirror the TS compiler's last-wins or first-wins choice and add a test.
- KTI format compatibility: writing additional structure must remain backwards-compatible
  with KTI files written by the TS compiler. Cross-check the KTI v4 schema.
- This story is a prerequisite for the catch-pattern checks in S17-19 to interoperate with
  imported exception types.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/tools/compiler/kti.ks` | (1) `parseTypeEntry` — parse `constructors` array `[{name, params}]` from JSON into `Option<List<(String, Int)>>`; backwards-compatible (field absent → `None`). (2) `typeEntryToJson` — emit `constructors` when present. (3) `buildTypeEntries` — accept `adtCtorGroups: Dict<String, List<String>>` param; populate `constructors` field for ADT type entries. (4) `buildKtiV4` — compute `adtCtorGroups` from `prog` body (iterate `TDType` with `TBAdt` body and non-opaque visibility); pass to `buildTypeEntries`. (5) Add exported `deserializeCtorMaps(kti: KtiV4)` → `(Dict<String, Ty.InternalType>, Dict<String, List<String>>, Dict<String, String>)` (ctorEnv, adtConstructors, ctorOwners). (6) `DepBindingBundle` — add three new fields: `importCtorEnv`, `importAdtConstructors`, `importCtorOwners`. (7) `loadDepBindings` — initialize new fields to empty in base case; in recursive case call `deserializeCtorMaps` and merge per-dep results into bundle (named imports: include only ADT groups where at least one ctor was imported; namespace imports: include all ADT groups). |
| `stdlib/kestrel/dev/typecheck/typecheck.ks` | (8) `TypecheckOptions` — add `importCtorEnv: Option<Dict<String, Ty.InternalType>>`, `importAdtConstructors: Option<Dict<String, List<String>>>`, `importCtorOwners: Option<Dict<String, String>>`. (9) `defaultTypecheckOptions` — set new fields to `None`. (10) `emptyTypeRegistry` — seed `ctorEnv`, `adtConstructors`, `ctorOwners` from the option fields when present; local `prebindTypeDecls` then layers on top (local declarations override imports via `Dict.insert`). |
| `stdlib/kestrel/tools/compiler/driver.ks` | (11) `doTypecheckAndEmit` — extract `importCtorEnv`, `importAdtConstructors`, `importCtorOwners` from `depBindings`; pass to `tcOpts`. |
| Tests | New unit tests in `kti.test.ks`, `typecheck.test.ks`, and `driver-kti-loading.test.ks` (see § Tests to add). |
| `docs/specs/06-typesystem.md` | Minor note: exhaustiveness is now also enforced for imported (non-opaque) ADTs when the complete constructor list is available via KTI. |
| `docs/specs/07-modules.md` | Minor note: `DepBindingBundle` carries `importCtorEnv / importAdtConstructors / importCtorOwners` sourced from dep KTI `types` entries; these seed the typecheck registry. |

**Compatibility notes:**
- `parseTypeEntry` gracefully handles absent `constructors` field → `None`; no breakage for old TS-written or old self-hosted KTIs.
- `DepBindingBundle` is an internal struct; no external contract to break.
- Collision policy: `Dict.union(newCtors, accumulated)` — first-write-wins across deps (d1 takes precedence); mirrors the deterministic behaviour of the TS reference which uses a Map and last-write wins when deps are sorted by resolution order. Document choice with a test.

## Tasks

- [x] `kti.ks` — `parseTypeEntry`: parse the optional JSON `constructors` array `[{"name": "X", "params": [...]}]` into `Option<List<(String, Int)>>` (name, params.length). Keep `None` when the field is absent or cannot be parsed.
- [x] `kti.ks` — `typeEntryToJson`: when `entry.constructors` is `Some(ctors)`, add a `"constructors"` JSON array `[{"name": n, "params": Array([])}]` for each `(n, _)` entry.
- [x] `kti.ks` — `buildTypeEntries`: add `adtCtorGroups: Dict<String, List<String>>` parameter; when a type name is present in `adtCtorGroups` emit `constructors = Some(Lst.map(ctors, (c: String) => (c, 0)))` in the `KtiTypeEntry` (arity stored as 0 — unused at typecheck time).
- [x] `kti.ks` — `buildKtiV4`: before calling `buildTypeEntries`, compute `adtCtorGroups` by iterating `prog.body` for `TDType(td)` nodes where `td.body` is `TBAdt(ctors)` and visibility is not opaque (check `exportedTypeVisibility`); build `Dict<String, List<String>>` mapping `td.name → Lst.map(ctors, (c: CtorDef) => c.name)`.
- [x] `kti.ks` — add `export fun deserializeCtorMaps(kti: KtiV4): (Dict<String, Ty.InternalType>, Dict<String, List<String>>, Dict<String, String>)`. Iterate `kti.types`; for each entry where `constructors` is `Some(ctors)`, build `adtConstructors[typeName] = [ctor names]` and `ctorOwners[ctorName] = typeName`; for each ctor name look it up in `kti.functions` → `deserializeType` to populate `ctorEnv`.
- [x] `kti.ks` — `DepBindingBundle` type: add `importCtorEnv: Dict<String, Ty.InternalType>`, `importAdtConstructors: Dict<String, List<String>>`, `importCtorOwners: Dict<String, String>`.
- [x] `kti.ks` — `loadDepBindings` base case (`[]`): initialize all three new fields to `Dict.emptyStringDict()` / `Dict.emptyStringDict()` / `Dict.emptyStringDict()`.
- [x] `kti.ks` — `loadDepBindings` recursive case: call `deserializeCtorMaps(depKti)` to obtain `(depCtorEnv, depAdtCtors, depCtorOwners)`. For `IDNamed` imports: collect the set of ADT type names for which at least one constructor was named in the import spec; merge only those ADT groups (and their ctors) into `b.importCtorEnv / importAdtConstructors / importCtorOwners` using `Dict.union`. For `IDNamespace` imports: merge all dep ctor data unconditionally. Ensure the final `DepLoadOk(...)` record includes the three new fields.
- [x] `kti.ks` — update every intermediate record literal inside `loadDepBindings` that constructs a `DepBindingBundle` to include the three new fields (the `IDNamed`, `IDNamespace`, and catch-all `_ => b` branches, plus the final accumulator literal).
- [x] `typecheck.ks` — `TypecheckOptions`: add `importCtorEnv: Option<Dict<String, Ty.InternalType>>`, `importAdtConstructors: Option<Dict<String, List<String>>>`, `importCtorOwners: Option<Dict<String, String>>`.
- [x] `typecheck.ks` — `defaultTypecheckOptions`: set the three new fields to `None`.
- [x] `typecheck.ks` — `emptyTypeRegistry`: when `opts.importCtorEnv` / `opts.importAdtConstructors` / `opts.importCtorOwners` are `Some(...)`, use them as the initial values for `ctorEnv`, `adtConstructors`, `ctorOwners` respectively; fall back to `Dict.emptyStringDict()` for `None`.
- [x] `driver.ks` — `doTypecheckAndEmit`: extract the three new fields from `depBindings`; wrap in `Option` (use `None` when the dict is empty, `Some(...)` otherwise); add to the `tcOpts` record literal.
- [x] `typecheck.test.ks` — add new test group `"cross-module ADT ctor exhaustiveness"`: (a) happy-path: construct `TypecheckOptions` with `importCtorEnv`, `importAdtConstructors`, `importCtorOwners` seeded for a two-ctor ADT; typecheck a match with both arms present → `ok = True`, no diagnostics; (b) incomplete-match: same setup but one arm absent → `ok = False`, `nonExhaustiveMatch` diagnostic emitted; (c) pattern binding: imported ctor resolves in `bindPattern` without "Unknown constructor" error.
- [x] `kti.test.ks` — add tests: (a) `buildKtiV4` with a program declaring an exported ADT emits constructor names in the `types` section; (b) round-trip: write and re-read the KTI; `deserializeCtorMaps` returns correct `adtConstructors`, `ctorOwners`, and `ctorEnv` entries matching the original ADT.
- [x] `driver-kti-loading.test.ks` — add async integration test: compile a dep with an exported two-ctor ADT; compile a consumer that named-imports the type and both ctors and does a complete match; assert `ok = True` and no diagnostics. Add a second case with only one arm to assert `ok = False` and `nonExhaustiveMatch` in diagnostics.
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel unit | `stdlib/kestrel/dev/typecheck/typecheck.test.ks` | Happy-path: imported ADT with all arms present typechecks OK; non-exhaustive imported ADT match emits `nonExhaustiveMatch`; imported ctor resolves in `bindPattern` (no "Unknown constructor" error) |
| Kestrel unit | `stdlib/kestrel/tools/compiler/kti.test.ks` | `buildKtiV4` emits constructor lists in `types` section for exported ADTs; `deserializeCtorMaps` returns correct `ctorEnv`, `adtConstructors`, `ctorOwners`; KTI round-trip preserves constructor data |
| Kestrel integration | `stdlib/kestrel/tools/compiler/driver-kti-loading.test.ks` | Compile dep with exported ADT + two ctors; compile consumer that imports and fully matches — `ok = True`, no diagnostics; compile consumer with missing arm — `ok = False`, `nonExhaustiveMatch` in diagnostics |

## Documentation and specs to update

- [x] `docs/specs/06-typesystem.md` — §5 exhaustiveness: add a note that when all constructors of an imported non-opaque ADT are known (via KTI `types` constructor lists), the same exhaustiveness rules apply as for locally-declared ADTs.
- [x] `docs/specs/07-modules.md` — add a note under the KTI/cross-module section that `DepBindingBundle` carries `importCtorEnv`, `importAdtConstructors`, and `importCtorOwners` sourced from dep KTI `types` entries, and that `TypecheckOptions` accepts these to seed the type registry for cross-module exhaustiveness checking.

## Build notes

- 2026-05-03: Started implementation.
- 2026-05-03: Discovered that `checkTypeDeclExports` in `typecheck.ks` did not add exported ADT types to `exportedTypeAliases` (unlike the TS checker). This meant `buildKtiV4` omitted ADT type entries from `kti.types`, so `deserializeCtorMaps` had nothing to iterate. Fixed by handling `TBAdt` in `checkTypeDeclExports` to insert the type name into `exportedTypeAliases` (matching TS behaviour).
- 2026-05-03: JVM codegen bug: inline `match` or `if` expressions inside a record literal generate incorrect stackmap frames (verified via `javap`; the frame at the branch-merge point references an offset inside an instruction). Worked around by extracting all branching sub-expressions into `val` bindings before the record literal, and by factoring helper functions (`resolvedImportCtorEnv`, etc.) instead of inline `match` in `emptyTypeRegistry`. Noted in build notes; the underlying codegen bug should be tracked separately.
- 2026-05-03: `extract.ks`'s `inferExportTypeStrings` was split into a thin dispatcher + `inferExportTypeStringsOk` helper to avoid a JVM VerifyError triggered by accessing `TC.defaultTypecheckOptions` inside a match arm block (same stackmap codegen issue).
