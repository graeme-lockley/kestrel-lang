# Hindley-Milner Type Checker

## Sequence: S14-04
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-03, S14-05, S14-06, S14-07, S14-08, S14-09, S14-10, S14-11, S14-12, S14-13, S14-14

## Summary

Port the Hindley-Milner type checker from `compiler/src/typecheck/check.ts` (~1 878 lines)
to `stdlib/kestrel/tools/compiler/typecheck.ks`. This is the largest single-module port in the epic
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

1. Create `stdlib/kestrel/tools/compiler/typecheck.ks` with:
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

- `stdlib/kestrel/tools/compiler/typecheck.ks` compiles without errors.
- A test file `stdlib/kestrel/tools/compiler/typecheck.test.ks` covers:
  - simple integer and boolean expressions are typed correctly
  - type error (e.g. adding Int + Bool) produces a Diagnostic
  - function declaration with annotated return type is accepted
  - `let` polymorphism: a generic identity function works with Int and Bool
  - pattern match exhaustiveness for a simple ADT
- All tests in `tests/conformance/typecheck/` pass unchanged when running via the TypeScript
  compiler (regression guard).
- `./kestrel test stdlib/kestrel/tools/compiler/typecheck.test.ks` passes.
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

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib | Add `stdlib/kestrel/tools/compiler/typecheck.ks` implementing the self-hosted typechecker entry point, type environment, inference helpers, diagnostics emission, and export maps. |
| Stdlib | Likely extend `stdlib/kestrel/tools/compiler/types.ks` usage sites to support full substitution, subtype checking, and pretty-printing inside type errors without changing public shape. |
| Parser AST helpers | Reuse `kestrel:dev/parser/ast` node shapes and likely key inferred-type storage by AST node offset/spans instead of TS `WeakMap`. |
| Kestrel tests | Add `stdlib/kestrel/tools/compiler/typecheck.test.ks` for acceptance-criteria coverage: literals, type errors, annotated functions, let polymorphism, and match exhaustiveness. |
| TypeScript compiler tests | Keep `cd compiler && npm test` passing as regression guard while self-hosted checker is introduced; no TS source changes expected for the first port. |
| Specs/docs | Update `docs/specs/06-typesystem.md` with self-hosted checker parity note and `docs/specs/01-language.md` only if the implementation exposes a spec mismatch around narrowing, blocks, or pattern exhaustiveness. |

## Tasks

- [x] Create `stdlib/kestrel/tools/compiler/typecheck.ks` with `TypeEnv`, `TypecheckOptions`, `DependencyExportSnapshot`, `TypecheckResult`, and top-level `typecheck` entrypoint.
- [x] Implement inferred-type annotation storage (`setInferredType`, `getInferredType`) using a Kestrel-friendly key scheme based on AST identity substitutes (for example node span offsets) rather than `WeakMap`.
- [x] Port the minimal inference core for literals, identifiers, arithmetic/boolean/comparison ops, if/while/block, function declarations, function application, `val`/`var`, and let-generalisation/instantiation.
- [x] Port pattern binding and exhaustiveness checking sufficient for simple ADTs, wildcard/var/literal patterns, tuple/list patterns, and `match` expressions.
- [x] Port declaration handling for top-level `fun`, `val`, `var`, `type`, and exported constructor/type visibility maps needed by downstream KTI/driver stories.
- [x] Emit diagnostics using `kestrel:tools/compiler/diagnostics` with stable code strings and messages for unification errors, undefined names, impossible narrowing, loop-control misuse, and exhaustiveness failures.
- [x] Add `stdlib/kestrel/tools/compiler/typecheck.test.ks` covering acceptance criteria and a small multi-declaration integration case.
- [x] Run `./kestrel test stdlib/kestrel/tools/compiler/typecheck.test.ks`.
- [x] Run `cd compiler && npm test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/tools/compiler/typecheck.test.ks` | Simple integer/boolean expressions infer `Int`/`Bool` correctly and store inferred types for downstream lookup. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/typecheck.test.ks` | `Int + Bool` (or similar mismatch) returns a diagnostic with a stable type-error code/message. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/typecheck.test.ks` | Function declaration with annotated return type typechecks and exported environment contains the declared function type. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/typecheck.test.ks` | Let-polymorphic identity function instantiates independently for `Int` and `Bool`. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/typecheck.test.ks` | Simple ADT match requires exhaustiveness or emits a diagnostic. |
| Vitest integration | `compiler/test/integration/typecheck-integration.test.ts` (existing) | Regression guard: existing bootstrap checker behaviour remains unchanged while self-hosted checker lands. |

## Documentation and specs to update

- [x] `docs/specs/06-typesystem.md` — extend the self-hosting parity note to include `kestrel:dev/typecheck/typecheck` as the checker-side consumer of `types` / `from-ast` and its exported environment maps.
- [x] `docs/specs/01-language.md` — reviewed; no updates required because no spec mismatch surfaced in expression typing, match exhaustiveness, `is` narrowing, loop control, or top-level recursion rules.

## Build notes

- 2026-04-12: Story entered doing with implementation already present in `stdlib/kestrel/tools/compiler/typecheck.ks`; verified parity using story-specific harness tests plus full compiler/Kestrel suites.
- 2026-04-12: Updated `docs/specs/06-typesystem.md` to include `kestrel:tools/compiler/typecheck` in the self-hosting parity note; `docs/specs/01-language.md` required no change after review.
- 2026-04-12: Entire checker cluster (`typecheck.ks`, `types.ks`, `from-ast.ks`, `diagnostics.ks`, `reporter.ks`) physically relocated from `kestrel:tools/compiler/` to `kestrel:dev/typecheck/`; `inferredState` global replaced with a per-invocation `mut` field on `TcState`; `TypecheckResult` now carries a `getInferredType` closure. All 1796 Kestrel + 440 compiler tests pass.
