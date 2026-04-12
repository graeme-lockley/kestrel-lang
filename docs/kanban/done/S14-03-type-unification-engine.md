# Type Unification Engine

## Sequence: S14-03
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/done/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-04, S14-05, S14-06, S14-07, S14-08, S14-09, S14-10, S14-11, S14-12, S14-13, S14-14

## Summary

Port the type unification engine to `stdlib/kestrel/tools/compiler/types.ks` (or a companion
`unify.ks`), covering `compiler/src/types/unify.ts` (~428 lines) and the AST-to-internal-type
translation in `compiler/src/types/from-ast.ts` (~121 lines).

These are the constraint-solving heart of the Hindley-Milner engine: `unify` builds a
substitution map by structural decomposition, `unifySubtype` handles record-subtype checking,
and `astTypeToInternal` converts source-AST type annotations into `InternalType` for the checker.

## Current State

`compiler/src/types/unify.ts`:
- `unify(s: Subst, t1: InternalType, t2: InternalType): Subst | UnifyError` — main unification
- `unifySubtype` — for open-record row extension
- `UnifyError` class — structured error with left/right types
- `expandGenericAliasHead` — expand named type aliases before unification

`compiler/src/types/from-ast.ts`:
- `astTypeToInternal(astType, scope)` — converts parsed type nodes to `InternalType`
- `astTypeToInternalWithScope` — variant that threads a type-var scope

## Relationship to other stories

- **Depends on**: S14-02 (InternalType ADT and substitution map type)
- **Blocks**: S14-04 (type checker calls unify heavily)

## Goals

1. Extend or create a companion to `stdlib/kestrel/tools/compiler/types.ks` with:
   - `Subst` type alias (e.g. `Dict<Int, InternalType>`) exported
   - `UnifyError` ADT with left/right `InternalType` fields
   - `unify(subst: Subst, t1: InternalType, t2: InternalType): Result<Subst, UnifyError>`
   - `unifySubtype(subst: Subst, t1: InternalType, t2: InternalType): Result<Subst, UnifyError>`
   - `applySubstFull(subst: Subst, t: InternalType): InternalType` (chase chains)
   - `expandGenericAliasHead(name: String, args: List<InternalType>, aliases: Dict<String, InternalType>): InternalType`
2. Create `stdlib/kestrel/tools/compiler/from-ast.ks` (or include in `types.ks`) with:
   - `astTypeToInternal(node: Type, scope: Dict<String, InternalType>): InternalType`
   - `astTypeToInternalWithScope(node: Type, scope: Dict<String, InternalType>, typeParams: List<String>): InternalType`
   - These depend on `kestrel:dev/parser/ast` for the `Type` AST node type

## Acceptance Criteria

- Modules compile without errors.
- A test file covers:
  - `unify` on identical primitives returns the same subst
  - `unify` of a var with a primitive produces a singleton subst
  - `unify` of two different primitives returns `Err(UnifyError)`
  - occur-check: unifying a var with an `App` containing that var returns an error
  - `astTypeToInternal` on `Int` returns `tInt`
  - `astTypeToInternal` on a function type returns `Arrow`
- `./kestrel test` on the new test file passes.
- `cd compiler && npm test` still passes.

## Spec References

- `compiler/src/types/unify.ts`
- `compiler/src/types/from-ast.ts`
- `docs/specs/06-typesystem.md` — unification rules, row polymorphism

## Risks / Notes

- TypeScript `unify` is imperative (mutates sets); Kestrel version should use functional
  substitution map (`Dict`), passing it through recursive calls.
- Row unification (open-record extension) is subtle; port carefully and test with open/closed
  record examples.
- `expandGenericAliasHead` requires access to the type-alias environment; pass as a parameter.

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib | Extended `stdlib/kestrel/tools/compiler/types.ks` with unification APIs: `applySubstFull`, `unify`, `unifySubtype`, and alias-head helper. |
| Stdlib | Added `stdlib/kestrel/tools/compiler/from-ast.ks` with AST-to-internal-type conversion helpers. |
| Parser AST helpers | Extended `stdlib/kestrel/dev/parser/ast.ks` with `astType*` deconstructor helpers to avoid imported-constructor pattern matching limits. |
| Kestrel tests | Added `stdlib/kestrel/tools/compiler/unify.test.ks` for unification and ast conversion acceptance cases. |
| Specs/docs | Updated `docs/specs/06-typesystem.md` self-hosting note with unify/from-ast parity details. |

## Tasks

- [x] Extend `stdlib/kestrel/tools/compiler/types.ks` with `applySubstFull`, `unify`, `unifySubtype`, and `expandGenericAliasHead`.
- [x] Implement occurs-check based variable binding and structural decomposition for primitives, arrows, apps, tuples, unions, intersections, and records.
- [x] Add `stdlib/kestrel/tools/compiler/from-ast.ks` with `astTypeToInternal` and `astTypeToInternalWithScope`.
- [x] Add AST deconstructor helpers in `stdlib/kestrel/dev/parser/ast.ks` used by `from-ast.ks`.
- [x] Add `stdlib/kestrel/tools/compiler/unify.test.ks` covering acceptance criteria cases.
- [x] Run `./kestrel test stdlib/kestrel/tools/compiler/unify.test.ks`.
- [x] Run `./kestrel test stdlib/kestrel/tools/compiler/diagnostics.test.ks stdlib/kestrel/tools/compiler/types.test.ks stdlib/kestrel/tools/compiler/opcodes.test.ks stdlib/kestrel/tools/compiler/unify.test.ks`.
- [x] Run `cd compiler && npm test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/tools/compiler/unify.test.ks` | `unify` on identical/different primitives and var-vs-primitive substitution. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/unify.test.ks` | Occurs check guard: reject `TVar` unified with an application containing that same var. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/unify.test.ks` | `astTypeToInternal` conversion for primitive and arrow node shapes. |

## Documentation and specs to update

- [x] `docs/specs/06-typesystem.md` — extend the self-hosting compiler note to include unification (`unify`, `unifySubtype`) and AST conversion parity (`from-ast`).

## Build notes

- 2026-04-12: Started implementation.
- 2026-04-12: Imported-constructor pattern matching from other modules remains unsupported (for example `Ast.ATPrim(_)` and `Ty.TArrow(_)` in external modules). Added `astType*` deconstructor helpers in `kestrel:dev/parser/ast` and rewired `from-ast` to use those helpers.
- 2026-04-12: `Result` payload matching in deeply nested branches caused parser/binding instability in this module; switched unification chaining to `kestrel:data/result.andThen` for robustness and clearer control flow.
- 2026-04-12: `cd compiler && npm test` initially hit a transient integration failure (`ClassFormatError: Truncated class file` in `jvm-async-runtime`), which passed on immediate rerun and then passed in full-suite rerun (`436 passed`).
