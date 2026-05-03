# Fix KTI `codegenMeta` extraction and serialisation

## Sequence: S17-41
## Tier: 8
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01 through S17-44

## Summary

The self-hosted KTI layer has three interconnected stubs that cause every KTI written by the
self-hosted compiler to carry incorrect `codegenMeta`, and cause every KTI read back (including
bootstrap-written KTIs) to have its ADT-constructor and exception information silently dropped.
Together these bugs make cross-module codegen structurally unsound: downstream modules will emit
wrong `INVOKESTATIC` arities, fail to recognise async functions, miss `var`/`val` distinctions,
and be unable to reconstruct ADT constructors or exceptions from KTI.

Files affected:
- `stdlib/kestrel/tools/compiler/kti.ks` — `extractCodegenMeta`, `parseCodegenMeta`,
  `buildEntries`, `buildTypeEntries`, `buildKtiV4`

TS reference: `compiler/src/kti.ts` lines 202–282 (`extractCodegenMeta`) and 330–445
(`buildKtiV4` including ADT type entries).

## Current State

After S17-39 (serializeType JSON format) and S17-40 (freshenImportedTypeVars), KTI type
serialisation is structurally correct. However, the `codegenMeta` field written to every KTI
by the self-hosted compiler is still wrong:

- `extractCodegenMeta` (kti.ks line ~363) sets all `funArities` to `0`, leaves `asyncFunNames`,
  `varNames`, `adtConstructors`, and `exceptionDecls` as empty lists.
- `buildEntries` (kti.ks line ~375) writes `kind = "function"` and `arity = 0` for every export
  regardless of whether it is a function, val, var, constructor, or exception.
- `buildTypeEntries` (kti.ks line ~405) always writes `kind = "alias"`; it never writes
  `kind = "adt"` with a `constructors` list even for ADT types.
- `parseCodegenMeta` (kti.ks line ~331) reads `funArities`, `asyncFunNames`, `varNames`, and
  `valOrVarNames` from JSON correctly, but hardcodes `adtConstructors = []` and
  `exceptionDecls = []`, silently dropping this data from any KTI (including bootstrap-written
  KTIs that contain it).

## Relationship to other stories

- **Depends on**: S17-39 (serializeType JSON format), since `buildEntries` and `buildTypeEntries`
  call `serializeType`.
- **Blocks**: S17-22 (cross-module ADT exhaustiveness), which relies on accurate
  `adtConstructors` being present in KTI.
- **Blocks**: Any story that relies on downstream codegen using correct function arities, async
  detection, or var/val metadata from imported modules.

## Goals

1. `extractCodegenMeta` walks `prog.body` and correctly populates:
   - `funArities` — actual `params.length` per `FunDecl` / `ExternFunDecl`
   - `asyncFunNames` — names of `FunDecl` with `async = True`, or `ExternFunDecl` with return
     type `Task<_>`
   - `varNames` — names of exported `VarDecl` nodes
   - `valOrVarNames` — names of exported `ValDecl` + `VarDecl` nodes
   - `adtConstructors` — `[{ typeName, constructors: [{ name, params: Int }] }]` for each
     non-opaque exported `TypeDecl` with an `ADTBody`
   - `exceptionDecls` — `[{ name, arity }]` for each exported `ExceptionDecl`
2. `buildEntries` emits the correct `kind` (`"function"` / `"val"` / `"var"` / `"constructor"`)
   and correct `arity` for each export, walking `prog.body` exactly as the TS reference does.
3. `buildTypeEntries` emits `kind = "adt"` with a `constructors` array (and `typeParams`) for
   ADT type exports; `kind = "alias"` for type aliases; `type_ = opaque` for opaque types.
4. `parseCodegenMeta` correctly reads and returns `adtConstructors` and `exceptionDecls` from
   JSON, adding `KtiAdtConstructorGroup`, `KtiAdtCtor`, and `KtiExceptionEntry` types to
   `kti.ks` if they do not already exist.
5. `buildKtiV4` signature is updated to pass `exportedTypeAliases` and `exportedTypeVisibility`
   into `extractCodegenMeta` so ADT visibility can be checked.

## Acceptance Criteria

- [ ] `extractCodegenMeta` returns correct values for a representative program that exports:
      a 2-param function, an async function, a val, a var, an ADT with two constructors, and an
      exception with one field.
- [ ] `buildKtiV4` emits a JSON KTI where each export entry has the correct `kind` and `arity`;
      ADT type entries carry `kind = "adt"` with a `constructors` array.
- [ ] `readKtiFile` → `writeKtiFile` round-trip preserves `adtConstructors` and `exceptionDecls`
      without data loss.
- [ ] All pre-existing `kti.test.ks` tests pass.
- [ ] New unit tests in `kti.test.ks` cover: correct arity, async detection, var/val distinction,
      ADT constructor list, exception arity, round-trip of `adtConstructors` and `exceptionDecls`.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/11-bootstrap.md` — KTI v4 format and `codegenMeta` schema
- `compiler/src/kti.ts` lines 202–282 (`extractCodegenMeta` reference)
- `compiler/src/kti.ts` lines 330–445 (`buildKtiV4` reference, ADT type entries)

## Risks / Notes

- `extractCodegenMeta` signature must be expanded from `(prog, exports)` to
  `(prog, exports, exportedTypeAliases, exportedTypeVisibility)` to match the TS reference.
  All callers (currently only `buildKtiV4`) must be updated.
- `buildEntries` needs a counter to assign `adt_id` and `ctor_index` for constructor entries, as
  the TS reference does. ADT id is assigned per-type in the order types appear in `prog.body`.
- `buildTypeEntries` needs access to `prog.body` (not just the type alias map) to distinguish
  `TypeDecl` with `ADTBody` from plain type aliases and to read `typeParams`.
- `parseCodegenMeta` must parse a nested JSON structure for `adtConstructors`:
  `[{ typeName: String, constructors: [{ name: String, params: Int }] }]`.
- Reading these fields correctly from bootstrap-written KTIs will immediately fix the silent
  data loss that currently affects downstream cross-module codegen in self-hosted mode.
- This story should be completed before S17-22 (cross-module ADT exhaustiveness).
