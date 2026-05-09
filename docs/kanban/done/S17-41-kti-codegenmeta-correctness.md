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

- [x] `extractCodegenMeta` returns correct values for a representative program that exports:
      a 2-param function, an async function, a val, a var, an ADT with two constructors, and an
      exception with one field.
- [x] `buildKtiV4` emits a JSON KTI where each export entry has the correct `kind` and `arity`;
      ADT type entries carry `kind = "adt"` with a `constructors` array.
- [x] `readKtiFile` → `writeKtiFile` round-trip preserves `adtConstructors` and `exceptionDecls`
      without data loss.
- [x] All pre-existing `kti.test.ks` tests pass.
- [x] New unit tests in `kti.test.ks` cover: correct arity, async detection, var/val distinction,
      ADT constructor list, exception arity, round-trip of `adtConstructors` and `exceptionDecls`.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

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

## Impact analysis

| Area | Change |
|------|--------|
| Parser | No parser grammar change. Existing AST nodes (`TDType`, `TBAdt`, `TDException`, `TDExternFun`) are consumed more precisely by KTI metadata extraction in `stdlib/kestrel/tools/compiler/kti.ks`. |
| Typecheck | No typechecker algorithm change. `buildKtiV4` plumbing in `stdlib/kestrel/tools/compiler/kti.ks` will pass `exportedTypeAliases` and `exportedTypeVisibility` into `extractCodegenMeta` so exported-surface filtering and opaque visibility decisions match TS parity. |
| Codegen (bytecode) | No bytecode opcode changes. Correct `functions` entry `kind` and `arity` values in KTI remove downstream bytecode misclassification risks for imported names. |
| Codegen (JVM) | No direct emitter rewrite in this story; imported metadata consumed by JVM codegen becomes accurate (`funArities`, async names, ADT constructor metadata, exception arities). |
| JVM runtime | No runtime (`runtime/jvm/src/**`) changes expected. |
| Stdlib | Main implementation surface: `stdlib/kestrel/tools/compiler/kti.ks` (`parseCodegenMeta`, `extractCodegenMeta`, `buildEntries`, `buildTypeEntries`, `buildKtiV4`). Add missing `KtiAdtConstructorGroup` / `KtiAdtCtor` / `KtiExceptionEntry` parse support where needed. |
| CLI / scripts | No CLI behavior wiring changes, but self-hosted compile correctness improves because generated KTIs now preserve full codegen metadata. |
| Tests | Extend `stdlib/kestrel/tools/compiler/kti.test.ks` with focused assertions for arity/kind classification, async detection (including extern Task-return), var vs val tracking, ADT constructor groups, exception arity, and read/write round-trip preservation of `adtConstructors` + `exceptionDecls`. |
| Docs / specs | Update `docs/specs/11-bootstrap.md` KTI-related wording (or cross-reference `kti-format`) so `codegenMeta` fields and ADT/exception persistence expectations match implementation. Keep `compiler/src/kti.ts` parity reference aligned. |

Compatibility and rollback notes:
- `extractCodegenMeta` signature expansion (`(prog, exports)` -> `(prog, exports, exportedTypeAliases, exportedTypeVisibility)`) is source-compatible once all local callers are updated in the same patch (`buildKtiV4`); rollback is low risk because the change is isolated to KTI construction.
- `buildEntries` must assign constructor `adt_id` / `ctor_index` deterministically by program declaration order; mismatches here can break downstream constructor dispatch, so tests must lock ordering.
- `buildTypeEntries` must distinguish ADT vs alias from `prog.body` and preserve opaque behavior (`type_ = opaque` sentinel). Regressions here can leak opaque type internals.
- `parseCodegenMeta` must parse nested ADT constructor groups and exception declarations instead of dropping them; this directly addresses current silent data loss when reading bootstrap-authored KTIs.

## Tasks

- [x] Update `stdlib/kestrel/tools/compiler/kti.ks` `extractCodegenMeta` signature and implementation to mirror TS filtering semantics: include only exported value/type names, detect async extern functions via `Task<_>` return types, and exclude opaque ADT constructor groups using `exportedTypeVisibility`.
- [x] Refactor `stdlib/kestrel/tools/compiler/kti.ks` `buildEntries` to classify exported entries as `function` / `val` / `var` / `constructor`, preserving real function arity and assigning deterministic constructor `adt_id` / `ctor_index` from `prog.body` order.
- [x] Refactor `stdlib/kestrel/tools/compiler/kti.ks` `buildTypeEntries` to derive `kind = adt|alias`, constructor lists, and `typeParams` from actual `TypeDecl` nodes while preserving opaque handling.
- [x] Implement nested JSON parsing for `adtConstructors` and `exceptionDecls` in `stdlib/kestrel/tools/compiler/kti.ks` `parseCodegenMeta` (including helper parsers / types as needed) so read/write round-trips retain metadata.
- [x] Update `stdlib/kestrel/tools/compiler/kti.ks` `buildKtiV4` call site to pass `exportedTypeAliases` and `exportedTypeVisibility` into `extractCodegenMeta`.
- [x] Extend `stdlib/kestrel/tools/compiler/kti.test.ks` with regression groups for metadata extraction correctness, KTI export entry kind/arity correctness, and metadata round-trip preservation.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.
- [x] Run `./scripts/run-e2e.sh`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/tools/compiler/kti.test.ks` | Assert `extractCodegenMeta` returns correct `funArities`, `asyncFunNames` (including extern Task-return), `varNames`, `valOrVarNames`, ADT constructor groups (`typeName`, ctor arity), and `exceptionDecls` for a mixed exported module. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/kti.test.ks` | Assert `buildKtiV4` writes `functions` entries with correct `kind` and arity for function/val/var/constructor exports and stable constructor ordering (`adt_id` / `ctor_index`). |
| Kestrel harness | `stdlib/kestrel/tools/compiler/kti.test.ks` | Assert `types` entries mark ADTs as `kind = "adt"` with constructor arrays and type params, while opaque exports omit constructor leakage and keep opaque type sentinel behavior. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/kti.test.ks` | Assert `writeKtiFile` -> `readKtiFile` preserves `codegenMeta.adtConstructors` and `codegenMeta.exceptionDecls` without silent loss. |

## Documentation and specs to update

- [x] `docs/specs/11-bootstrap.md` — update KTI/bootstrap sections to reflect required `codegenMeta` parity guarantees (including ADT constructor and exception metadata preservation in self-hosted KTIs), or add explicit pointer to the authoritative KTI format section.
- [x] `compiler/src/kti.ts` — verify/reference parity for `extractCodegenMeta` and `buildKtiV4` behavior used as implementation baseline; update comments only if parity assumptions changed.

## Build notes

- 2026-05-09: Started implementation.
- 2026-05-09: Expanded `KtiExportEntry` to explicit `function`/`val`/`var`/`constructor` variants so JSON round-trips preserve entry kind instead of collapsing every export to `function`.
- 2026-05-09: Kept `types[*].constructors[*].params` encoded as arrays (length = arity) for TS-format parity, while parsing `codegenMeta.adtConstructors[*].constructors[*].params` as ints per codegen metadata schema.
- 2026-05-09: Verified `compiler/src/kti.ts` remains the parity baseline for `extractCodegenMeta`/`buildKtiV4`; no TS source edits were needed for this story.
- 2026-05-09: `./scripts/kestrel test` initially failed because self-hosted cache artifacts were missing; rebuilt bootstrap artifacts and reinstalled self-hosted classes before running required suites.
- 2026-05-09: A JVM verifier error in `parseCodegenMeta` was resolved by refactoring nested inline `match` expressions into helper functions (`parseCodegenAdtGroups` / `parseCodegenExceptions`) with simpler local bindings.
