# Internal Type Representation

## Sequence: S14-02
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/done/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-03, S14-04, S14-05, S14-06, S14-07, S14-08, S14-09, S14-10, S14-11, S14-12, S14-13, S14-14

## Summary

Port the compiler's internal type representation from TypeScript to Kestrel, creating
`stdlib/kestrel/compiler/types.ks`. This module defines the `InternalType` ADT — the
backbone of the type-checker, codegen, and KTI serializer — plus core type-construction
helpers (`freshVar`, `prim`, `tInt`, etc.) and structural operations (`freeVars`,
`generalize`, `instantiate`, `applySubst`).

Covers `compiler/src/types/internal.ts` (~149 lines).

## Current State

`compiler/src/types/internal.ts` defines the `InternalType` union:
- `Var` (unification variable with integer id)
- `Prim` (Int, Float, Bool, String, Unit, Char)
- `Arrow` (params: InternalType[], return: InternalType)
- `Record` (fields with optional row variable for open records)
- `App` (named type application, e.g. `List<Int>`)
- `Tuple` (anonymous product)

It also provides `freshVar`, `resetVarId`, `prim` helpers, shorthand constructors (`tInt`,
`tFloat`, etc.), `freeVars`, `generalize`, `instantiate`, and `applySubst`.

## Relationship to other stories

- **Depends on**: S14-01 (Diagnostic types used in error paths)
- **Blocks**: S14-03 (type unification), S14-04 (type checker), S14-06–S14-08 (codegen uses InternalType), S14-09 (KTI serializer stores InternalType)

## Goals

1. Create `stdlib/kestrel/compiler/types.ks` with:
   - `InternalType` ADT covering all seven variants
   - `Prim` ADT/type for primitive kinds
   - `freshVar(): InternalType` and `resetVarId(): Unit`
   - `prim(name: String): InternalType` and shorthands `tInt`, `tFloat`, `tBool`, `tString`, `tUnit`, `tChar`
   - `freeVars(t: InternalType): Set<Int>` (returns set of free var ids)
   - `generalize(env: Dict<String, InternalType>, t: InternalType): InternalType` — produces a Scheme-like `ForAll` or wraps via closure
   - `instantiate(t: InternalType): InternalType` — replace bound vars with fresh vars
   - `applySubst(subst: Dict<Int, InternalType>, t: InternalType): InternalType`
   - `typeToString(t: InternalType): String` — debug display

## Acceptance Criteria

- `stdlib/kestrel/compiler/types.ks` compiles without errors.
- A test file `stdlib/kestrel/compiler/types.test.ks` verifies:
  - `freshVar()` returns distinct ids on successive calls
  - `resetVarId()` resets the counter
  - `freeVars` on concrete types returns empty set
  - `applySubst` with a single var mapping replaces correctly
  - `generalize`/`instantiate` round-trip produces fresh vars
- `./kestrel test stdlib/kestrel/compiler/types.test.ks` passes.
- `cd compiler && npm test` still passes.

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib | Add `stdlib/kestrel/compiler/types.ks` with `InternalType` ADT and primitive constructors to mirror `compiler/src/types/internal.ts`. |
| Stdlib | Add substitution and quantification helpers: `freeVars`, `generalize`, `instantiate`, `applySubst`, and debug renderer `typeToString`. |
| Kestrel tests | Add `stdlib/kestrel/compiler/types.test.ks` for fresh var generation, substitution behaviour, and generalize/instantiate round-trips. |
| Compiler (TS reference parity) | Keep constructor names and helper behaviour aligned with `compiler/src/types/internal.ts` for bootstrap interoperability. |
| Specs/docs | Update type-system spec with a short note that self-hosted compiler modules use the same internal type categories and id conventions. |

## Tasks

- [x] Create `stdlib/kestrel/compiler/types.ks` with exported `InternalType` ADT (`Var`, `Prim`, `Arrow`, `Record`, `App`, `Tuple`) and `TypeField` helper record.
- [x] Implement primitive helpers (`prim`, `tInt`, `tFloat`, `tBool`, `tString`, `tUnit`, `tChar`) and mutable fresh-id state (`freshVar`, `resetVarId`).
- [x] Implement `freeVars` and a simple integer-set representation for free variable collection.
- [x] Implement `applySubst(subst, t)` with recursive traversal across all InternalType constructors.
- [x] Implement `generalize(env, t)` and `instantiate(t)` using a ForAll wrapper constructor in `InternalType`.
- [x] Implement `typeToString(t)` for deterministic debug rendering.
- [x] Add `stdlib/kestrel/compiler/types.test.ks` covering fresh var ids, reset semantics, substitution, and generalize/instantiate behaviour.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test stdlib/kestrel/compiler/types.test.ks`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/compiler/types.test.ks` | Ensure `freshVar` generates distinct ids and `resetVarId` restarts allocation deterministically. |
| Kestrel harness | `stdlib/kestrel/compiler/types.test.ks` | Ensure `freeVars` excludes primitives and includes variables under nested Arrow/App/Tuple structures. |
| Kestrel harness | `stdlib/kestrel/compiler/types.test.ks` | Ensure `applySubst` recursively replaces vars in nested type structures. |
| Kestrel harness | `stdlib/kestrel/compiler/types.test.ks` | Ensure `generalize` introduces quantified vars and `instantiate` returns fresh ids on each call. |

## Documentation and specs to update

- [x] `docs/specs/06-typesystem.md` — note self-hosted compiler internal type constructors (`Var`, `Prim`, `Arrow`, `Record`, `App`, `Tuple`) and fresh-id allocation parity with bootstrap compiler.
- [x] `docs/guide.md` — add short compiler-hacking note that `stdlib/kestrel/compiler/types.ks` mirrors `compiler/src/types/internal.ts`.

## Spec References

- `compiler/src/types/internal.ts`
- `docs/specs/06-typesystem.md` — type representation and unification rules

## Risks / Notes

- TypeScript uses a mutable global counter for var ids; in Kestrel use a `var` module-level
  counter behind a `freshVar()` function.
- Kestrel generics differ from TypeScript generics; the `InternalType` ADT will use
  Kestrel variant records (ADTs), not TypeScript unions.
- `ForAll`/Scheme quantification in TypeScript is encoded via positive var ids for bound,
  negative ids for free; the Kestrel port can use the same convention.
- `applySubst` is recursive and may need careful handling of cycles (occur-check in unify).

## Build notes

- 2026-04-11: Started implementation.
- 2026-04-11: Blocked on JVM verifier failure while running `./kestrel test stdlib/kestrel/compiler/types.test.ks`. The generated method for `applySubstMany` fails with `VerifyError: Inconsistent stackmap frames`. Multiple simplification attempts (removing list-map lambdas, replacing Option pattern bindings, simplifying pattern forms) did not eliminate the verifier error. Stopping further retries for this file per the 3-attempt safety rule.
- 2026-04-11: Resolved VerifyError by extracting complex match arms into dedicated helper functions. The root cause was that 10-arm match expressions with branches introducing different numbers of local variables (especially TRecord with if/else + locals `fields2` and `row2`) caused inconsistent JVM stackmap frames at branch targets within the large generated method. The fix: extracted `applySubstRecord`, `applySubstFields`, `typeToStringRecord`, `freeVarsRecord`, and `freeVarsScheme` helpers so each top-level match arm in `applySubst`, `typeToString`, and `freeVarsWithBound` is a simple function call rather than a multi-statement block. All 5 tests now pass.
