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

- [ ] A program that pattern matches against an imported ADT (e.g. `DocKind` from
      `kestrel:dev/doc/extract`) typechecks without emitting "Unknown variable" / "Unknown
      constructor" diagnostics under the self-hosted checker.
- [ ] An incomplete `match` against an imported ADT raises the same exhaustiveness
      diagnostic that the TS compiler does.
- [ ] `stdlib/kestrel/dev/doc/sig.ks` typechecks end-to-end via the self-hosted checker (the
      observed `DKFun` / `DKExternFun` / `DKType` failures from the S17-13 pre-mortem are
      gone).
- [ ] New unit tests cover both happy-path imported-ctor pattern matching and the
      exhaustiveness diagnostic for imported ADTs.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

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
