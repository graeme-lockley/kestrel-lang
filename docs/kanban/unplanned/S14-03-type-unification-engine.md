# Type Unification Engine

## Sequence: S14-03
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-04, S14-05, S14-06, S14-07, S14-08, S14-09, S14-10, S14-11, S14-12, S14-13, S14-14

## Summary

Port the type unification engine to `stdlib/kestrel/compiler/types.ks` (or a companion
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

1. Extend or create a companion to `stdlib/kestrel/compiler/types.ks` with:
   - `Subst` type alias (e.g. `Dict<Int, InternalType>`) exported
   - `UnifyError` ADT with left/right `InternalType` fields
   - `unify(subst: Subst, t1: InternalType, t2: InternalType): Result<Subst, UnifyError>`
   - `unifySubtype(subst: Subst, t1: InternalType, t2: InternalType): Result<Subst, UnifyError>`
   - `applySubstFull(subst: Subst, t: InternalType): InternalType` (chase chains)
   - `expandGenericAliasHead(name: String, args: List<InternalType>, aliases: Dict<String, InternalType>): InternalType`
2. Create `stdlib/kestrel/compiler/from-ast.ks` (or include in `types.ks`) with:
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
