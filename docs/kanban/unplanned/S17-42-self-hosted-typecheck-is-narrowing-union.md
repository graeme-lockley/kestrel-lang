# Self-hosted typecheck: `is` narrowing for union-typed identifiers

## Sequence: S17-42
## Tier: 8
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-22, S17-38, S17-44

## Summary

Implement flow-sensitive narrowing in the self-hosted typechecker for `if (x is T)` when `x` is
an identifier with a union type (for example `Int | Bool`). Today `EIs` returns `Bool` but does
not refine the environment in branch scope, so expressions like `if (x is Int) x else 0` fail with
unification errors even though they are valid and covered by unit tests.

## Current State

- `tests/unit/union_intersection.test.ks` currently fails under self-hosted checking with repeated
  `Cannot unify Int | Bool with Int/Bool` diagnostics.
- `stdlib/kestrel/dev/typecheck/typecheck.ks` handles `EIs(e, _)` as `inferExpr(e); Bool` without
  branch-specific type environment refinement.
- To keep `./kestrel test` usable while this gap remains, the assertions in
  `tests/unit/union_intersection.test.ks` are temporarily commented out and marked with `S17-42`.

## Relationship to other stories

- **Depends on**: no additional parser/AST work; union/intersection AST + internal types already exist.
- **Companion**: S17-38 covers codegen/runtime semantics of `EIs` (`INSTANCEOF`) and should remain
  aligned with this typechecker behavior.
- **Must complete before**: S17-44 final no-Node E2E validation, so the re-enabled unit test is
  part of the final green gate.

## Goals

- Add branch-local narrowing for identifier guards of the form `x is T` in `if` conditions.
- Ensure then-branch sees `x: T` and else-branch sees `x: original \ T` (or at minimum preserves
  sound typing for current union cases such as `Int | Bool`).
- Re-enable `tests/unit/union_intersection.test.ks` assertions and keep them passing under
  `./kestrel test`.

## Acceptance Criteria

- [ ] `tests/unit/union_intersection.test.ks` is uncommented (remove the temporary `S17-42` skip
      comments) and passes under `./kestrel test`.
- [ ] A regression test verifies `fun takeU(x: Int | Bool): Int = if (x is Int) x else 0` typechecks.
- [ ] `stdlib/kestrel/dev/typecheck/typecheck.ks` applies narrowing in `EIf` branches when the
      condition is `EIs(EIdent(name), typ)`.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — `is` type-narrowing expression
- `docs/specs/06-typesystem.md` — union/intersection typing and narrowing intent
- `docs/specs/08-tests.md` — unit test expectations for language features

## Risks / Notes

- Narrowing must be scoped to branch environments only; it must not mutate the outer environment.
- If full set-difference (`A | B` minus `A`) is too large for this story, land minimal handling for
  the currently failing union cases first, but keep the regression test enabled.
- Keep diagnostics stable: failures should remain precise and not regress unrelated type errors.
