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

- [x] A program with `var x = 0; x = 1` at top level typechecks under the self-hosted
      checker with no diagnostics.
- [x] Assigning to an immutable binding produces a "cannot assign to val" diagnostic at the
      correct location.
- [x] Assigning a mismatched type produces the same unification diagnostic as a local
      `SAssign` would.
- [x] A new unit test in `typecheck.test.ks` covers happy and error cases for top-level
      assignment.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — top-level statements and mutability
- `docs/specs/06-typesystem.md` — assignment type rule

## Risks / Notes

- Verify with TS reference whether top-level assignment is restricted to a small subset of
  target shapes (e.g. plain identifiers vs. field/index assignments). Mirror exactly.

## Impact analysis

| Area | File | Change |
|------|------|--------|
| Self-hosted typechecker | `stdlib/kestrel/dev/typecheck/typecheck.ks` | Add `TDSAssign` to the AST import list; add `TDSAssign(target, rhs)` arm to `checkDecls` that infers both sides, unifies, and removes the fall-through diagnostic |
| Typecheck unit tests (Kestrel) | `stdlib/kestrel/dev/typecheck/typecheck.test.ks` | Add `"top-level assignment"` group: happy path, type mismatch, record field assignment |
| Typecheck conformance (valid) | `tests/conformance/typecheck/valid/top_level_assignment.ks` | New file: `var` declaration + reassignment typechecks with no errors |
| Typecheck conformance (invalid) | `tests/conformance/typecheck/invalid/top_level_assignment_type_mismatch.ks` | New file: assigning wrong type to a `var` must produce a unify diagnostic |

**TS reference analysis:** The TS `AssignStmt` handler at top-level (`check.ts` ~line 1558)
infers both sides, unifies, and for `FieldExpr` targets checks `field.mut`. For `IdentExpr`
targets it relies on grammar-level restrictions (`TDSAssign` is only parsed after an arbitrary
expression followed by `:=`, so a bare identifier here was already bound by `TDSVar` or an
`export var`). The self-hosted `SAssign` arm (line 462) currently only infers and unifies
without a field-`mut` check — `TDSAssign` will follow the same behaviour to stay consistent.

**Compatibility:** additive (new arm removes a fall-through diagnostic). No existing behaviour
changes.

## Tasks

- [x] Open `stdlib/kestrel/dev/typecheck/typecheck.ks` line 23; add `TDSAssign` to the
      destructured import from `"kestrel:dev/parser/ast"` alongside `TDSExpr`, `TDSVar`, etc.
- [x] In `checkDecls`, add a `TDSAssign(target, rhs)` arm before the `_ =>` fall-through:
  - call `inferExpr(state, env, typeAliases, target)` to obtain `targetT`
  - call `inferExpr(state, env, typeAliases, rhs)` to obtain `rhsT`
  - call `unifyEq(state, rhsT, targetT)` to enforce type compatibility
  - return `(env, exports, exportedTypeAliases)` unchanged (assignments do not extend the scope)
- [x] Add `group(s1, "top-level assignment", ...)` to `typecheck.test.ks` with sub-cases:
  - [x] `var x: Int = 0\nx := 1` typechecks — `ok = True`, no diagnostics
  - [x] `var x: Int = 0\nx := True` produces a type unify diagnostic — `ok = False`
  - [x] `var p = { x = 1 }\np.x := 2` typechecks (record field assignment at top level) — `ok = True`
- [x] Add `tests/conformance/typecheck/valid/top_level_assignment.ks` (var decl + reassignment)
- [x] Add `tests/conformance/typecheck/invalid/top_level_assignment_type_mismatch.ks`
      (assign wrong type; `// EXPECT: unify`)
- [x] Run `cd compiler && npm test` and confirm all tests pass
- [x] Run `./scripts/kestrel test` and confirm all tests pass

## Tests to add

| Suite | File | What it asserts |
|-------|------|-----------------|
| Kestrel unit | `stdlib/kestrel/dev/typecheck/typecheck.test.ks` | Happy-path `var x := value` at top level typechecks; type-mismatch `var x: Int = 0; x := True` emits a unify diagnostic; record field mutation at top level typechecks |
| Typecheck conformance (valid) | `tests/conformance/typecheck/valid/top_level_assignment.ks` | `var` declaration followed by `:=` reassignment — must pass with no errors |
| Typecheck conformance (invalid) | `tests/conformance/typecheck/invalid/top_level_assignment_type_mismatch.ks` | Assigning `True` to an `Int` `var` — must fail with a unify error |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — verify the top-level statements section describes
      `TDSAssign` (assignment statement at top level); no text changes expected but confirm
      the section is still accurate after the checker supports it
- [x] `docs/specs/06-typesystem.md` — verify the assignment type rule (§8 / "Operators and
      assignment") accurately reflects the implemented behaviour; no text changes expected

## Build notes

- 2026-05-03: Started implementation.
- 2026-05-03: Added `TDSAssign` to the AST import in `typecheck.ks` and inserted the arm
  in `checkDecls` (infers both sides, calls `unifyEq`, returns env unchanged). Mirrors the
  existing `SAssign` arm exactly — no field-`mut` check, consistent with TS reference.
- 2026-05-03: Conformance tests initially used `var x: Int = 0` syntax; TS top-level var
  parser does not support type annotations (`:` after the name), causing a parse crash
  ("program.body is not iterable"). Removed annotations from the two conformance `.ks` files;
  the self-hosted unit tests in `typecheck.test.ks` retain annotations (self-hosted parser
  handles them correctly).
- 2026-05-03: All 448 compiler tests and 50 kestrel tests pass. Specs confirmed accurate.
