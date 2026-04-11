# Hindley-Milner Type Checker

## Sequence: S14-04
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-03, S14-05, S14-06, S14-07, S14-08, S14-09, S14-10, S14-11, S14-12, S14-13, S14-14

## Summary

Port the Hindley-Milner type checker from `compiler/src/typecheck/check.ts` (~1 878 lines)
to `stdlib/kestrel/compiler/typecheck.ks`. This is the largest single-module port in the epic
and the centrepiece of the self-hosted compiler: it infers and checks types for every language
construct, producing a `Diagnostic` list for type errors and decorating each AST node with its
inferred `InternalType` for downstream codegen.

## Current State

`compiler/src/typecheck/check.ts` implements:
- Environment management: `TypeEnv` (name → `InternalType` bindings), `TypeAliasEnv`, `OpaqueEnv`
- Expression inference: literals, identifiers, function application, let/var/val bindings,
  lambda, binary ops, field access, record construction, tuple, match/pattern matching,
  try/catch/throw, async/await, if-then-else, block, `is`-narrowing
- Declaration checking: `fun`, `val`, `var`, `type`, `extern fun`, `extern type`, `exception`
- Top-level: `typecheck(program, options)` returns exports map and diagnostics
- Symbol decorating: inferred types attached to AST nodes via a `WeakMap` keyed by node ref
- Recursive/mutual-recursive function inference via pre-declaration with fresh vars

Attached type info is consumed by `jvmCodegen` via `getInferredType` helpers.

## Relationship to other stories

- **Depends on**: S14-01 (Diagnostic), S14-02 (InternalType, Subst helpers), S14-03 (unify, astTypeToInternal)
- **Depends on (indirectly)**: `kestrel:dev/parser/ast` for `Program`, `Expr`, `TopLevelDecl` AST types
- **Blocks**: S14-09 (KTI writer needs export type map from typecheck), S14-11 (driver calls typecheck)

## Goals

1. Create `stdlib/kestrel/compiler/typecheck.ks` with:
   - `TypeEnv` type — mapping from name to `InternalType`
   - `TypecheckOptions` record — mirroring the TS options struct
   - `DependencyExportSnapshot` record
   - `typecheck(prog: Program, opts: TypecheckOptions): TypecheckResult`
   - `TypecheckResult` = `{ ok: Bool, exports, exportedTypeAliases, exportedConstructors, exportedTypeVisibility, diagnostics }`
   - `getInferredType(node: Expr): Option<InternalType>`
   - `setInferredType(node: Expr, t: InternalType): Unit`
   - All expression-inference and declaration-check helpers as private functions
2. Ensure the output is interoperable: export maps use the same key names as the TypeScript
   compiler so KTI round-trips are compatible.

## Acceptance Criteria

- `stdlib/kestrel/compiler/typecheck.ks` compiles without errors.
- A test file `stdlib/kestrel/compiler/typecheck.test.ks` covers:
  - simple integer and boolean expressions are typed correctly
  - type error (e.g. adding Int + Bool) produces a Diagnostic
  - function declaration with annotated return type is accepted
  - `let` polymorphism: a generic identity function works with Int and Bool
  - pattern match exhaustiveness for a simple ADT
- All tests in `tests/conformance/typecheck/` pass unchanged when running via the TypeScript
  compiler (regression guard).
- `./kestrel test stdlib/kestrel/compiler/typecheck.test.ks` passes.
- `cd compiler && npm test` still passes.

## Spec References

- `compiler/src/typecheck/check.ts`
- `docs/specs/06-typesystem.md`
- `docs/specs/01-language.md` — expression forms and their type rules

## Risks / Notes

- TypeScript uses `WeakMap<AstNode, InternalType>` for side-channel type annotation; in Kestrel
  this must use a different mechanism (e.g. a `Dict<Int, InternalType>` keyed by node span
  offset, or a parallel tree with the same structure).
- The `is`-narrowing feature (NarrowingByIsExpr WeakMap) is similarly side-channel;
  plan for a typed-node wrapper or annotation map.
- Mutual-recursion pre-declaration uses mutable `TypeEnv` updates; use `var` in Kestrel.
- 1 878 lines is too large for a single focused implementation session; proceed function-group
  by function-group (literals, then let/fun, then ADTs, then async/await).
- Row polymorphism for records (open-record extension) must be handled correctly.
- The TypeScript checker uses TypeScript's own generics for `TypeEnv`; Kestrel parametric types
  will need careful handling.
