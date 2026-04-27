# Self-hosted typecheck for top-level assignments (`TDSAssign`)

## Sequence: S17-21
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-16, S17-17, S17-18, S17-19, S17-20, S17-22, S17-23

## Summary

Teach the self-hosted typechecker to handle top-level assignment statements (`TDSAssign`).
The codegen already emits `SAssign` and the parser produces `TDSAssign` for top-level
assignments to mutable bindings, but the typechecker has no arm and emits
"Unsupported top-level declaration in self-hosted checker MVP".

## Current State

- AST: `stdlib/kestrel/dev/parser/ast.ks` defines `TDSAssign(Expr, Expr)`.
- Codegen: `stdlib/kestrel/tools/compiler/codegen.ks` handles assignments via the inner
  `SAssign(_target, rhs)` path (line 292), but the top-level entry point reaches that path
  only via `TDSAssign` indirection.
- Typechecker: no arm in `checkDecls` (line 960 fall-through).

## Relationship to other stories

- **Depends on**: nothing in this epic.
- **Blocks**: S17-23 (E2E) for any module containing top-level mutation initialization.
- **Companion**: S17-16, S17-17, S17-18, S17-19, S17-20, S17-22.

## Goals

1. Add a `TDSAssign(target, rhs)` arm to `checkDecls` that:
   - infers `targetT = inferExpr(target)` and `rhsT = inferExpr(rhs)`,
   - unifies `targetT` with `rhsT`,
   - confirms the target denotes a mutable binding (variable, mutable record field, or
     mutable index), emitting a diagnostic if not.
2. Reuse the same logic that powers the existing nested `SAssign` handler (around line 371)
   so behaviour is consistent between local and top-level assignments.

## Acceptance Criteria

- [ ] A program with `var x = 0; x = 1` at top level typechecks under the self-hosted
      checker with no diagnostics.
- [ ] Assigning to an immutable binding produces a "cannot assign to val" diagnostic at the
      correct location.
- [ ] Assigning a mismatched type produces the same unification diagnostic as a local
      `SAssign` would.
- [ ] A new unit test in `typecheck.test.ks` covers happy and error cases for top-level
      assignment.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — top-level statements and mutability
- `docs/specs/06-typesystem.md` — assignment type rule

## Risks / Notes

- Verify with TS reference whether top-level assignment is restricted to a small subset of
  target shapes (e.g. plain identifiers vs. field/index assignments). Mirror exactly.
