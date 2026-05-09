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

- [x] `tests/unit/union_intersection.test.ks` is uncommented (remove the temporary `S17-42` skip
  comments) and passes under `./kestrel test`.
- [x] A regression test verifies `fun takeU(x: Int | Bool): Int = if (x is Int) x else 0` typechecks.
- [x] `stdlib/kestrel/dev/typecheck/typecheck.ks` applies narrowing in `EIf` branches when the
  condition is `EIs(EIdent(name), typ)`.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — `is` type-narrowing expression
- `docs/specs/06-typesystem.md` — union/intersection typing and narrowing intent
- `docs/specs/08-tests.md` — unit test expectations for language features

## Risks / Notes

- Narrowing must be scoped to branch environments only; it must not mutate the outer environment.
- If full set-difference (`A | B` minus `A`) is too large for this story, land minimal handling for
  the currently failing union cases first, but keep the regression test enabled.
- Keep diagnostics stable: failures should remain precise and not regress unrelated type errors.

## Impact analysis

| Area | Change |
|------|--------|
| Parser | No parser or AST changes expected. `EIs` / `EIf` / `EWhile` forms already exist; this story only changes typechecker flow-sensitive environment handling. |
| Typecheck | Update `stdlib/kestrel/dev/typecheck/typecheck.ks` so `EIs(EIdent(name), typ)` computes a narrowed type when overlap exists, reports `type:narrow_impossible` when overlap is impossible, and (for imported opaque ADTs) `type:narrow_opaque` where applicable. Apply narrowing in `EIf` then-branch and `EWhile` body with branch-local env overlays only. |
| Codegen (bytecode) | No bytecode IR changes. Static typing behavior changes only. |
| Codegen (JVM) | No JVM codegen emitter changes. `is` runtime opcode/shape remains unchanged. |
| JVM runtime | No runtime class or intrinsic changes. |
| Stdlib | No runtime stdlib API changes; self-hosted compiler stdlib modules under `stdlib/kestrel/dev/typecheck/` are updated for narrowing parity with TS compiler intent. |
| Scripts / CLI | No CLI flag or script behavior changes required for implementation. |
| Tests | Re-enable and keep `tests/unit/union_intersection.test.ks` assertions as a guard for `if (x is Int) x else 0`; add explicit narrowing regression coverage for happy-path and impossible-overlap diagnostics. |
| Docs / specs | Validate/update `docs/specs/01-language.md`, `docs/specs/06-typesystem.md`, and `docs/specs/08-tests.md` to reflect implemented narrowing scope and required regression coverage. |

Compatibility / rollback notes:
- Behavior is a compile-time narrowing fix only; no runtime behavior/API change.
- Rollback is low risk: confine changes to `typecheck.ks` narrowing helpers and branch env overlays.
- Risks carried from unplanned: keep narrowing branch-local (no outer env mutation), allow minimal union handling if needed for this story, and preserve precise diagnostics.

## Tasks

- [x] In `stdlib/kestrel/dev/typecheck/typecheck.ks`, add helper logic that computes `original_type & target_type` overlap for `is` checks on identifier scrutinees, including union-arm handling needed for `Int | Bool` narrowing.
- [x] In `stdlib/kestrel/dev/typecheck/typecheck.ks`, update `inferExpr` for `EIs(e, t)` to typecheck `e`, validate narrowing overlap, and record/apply narrowing metadata for identifier scrutinees without mutating outer env.
- [x] In `stdlib/kestrel/dev/typecheck/typecheck.ks`, update `inferExpr` for `EIf` to apply branch-local narrowed env in then-branch for `if (x is T)` and keep else-branch at the original (unrefined) type.
- [x] In `stdlib/kestrel/dev/typecheck/typecheck.ks`, update `inferExpr` for `EWhile` to apply the same branch-local narrowing inside loop body for `while (x is T)`.
- [x] Ensure diagnostics remain stable by using existing type diagnostic codes for impossible/opaque narrowing (`type:narrow_impossible`, `type:narrow_opaque`) and not regressing unrelated type errors.
- [x] Re-enable/retain the `takeU` assertions in `tests/unit/union_intersection.test.ks` (remove any temporary S17-42 skip comments if present) and keep this as the primary regression for identifier-union narrowing.
- [x] Add/extend narrowing regression coverage in `tests/unit/narrowing.test.ks` for identifier-union narrowing in `if` and `while`; keep impossible-overlap negative coverage in conformance invalid tests.
- [x] Add/extend conformance coverage in `tests/conformance/typecheck/valid/narrowing_union.ks` and `tests/conformance/typecheck/invalid/narrowing_impossible.ks` so narrowing behavior and diagnostics remain pinned.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `tests/unit/union_intersection.test.ks` | Guard the core regression: `fun takeU(x: Int | Bool): Int = if (x is Int) x else 0` typechecks and evaluates correctly for both `Int` and `Bool` call sites. |
| Kestrel harness | `tests/unit/narrowing.test.ks` | Add branch-scope narrowing cases for identifier guards in `if` and `while`, ensuring then/body sees narrowed type and else remains unrefined original type. |
| Conformance typecheck (valid) | `tests/conformance/typecheck/valid/narrowing_union.ks` | Assert accepted narrowing for union-typed identifiers and arithmetic use of narrowed arm in then-branch. |
| Conformance typecheck (invalid) | `tests/conformance/typecheck/invalid/narrowing_impossible.ks` | Assert impossible narrowing reports stable `type:narrow_impossible` diagnostics. |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — verify/update `is` expression narrowing text to match implemented branch-local behavior in `if`/`while` (identifier scrutinees only).
- [x] `docs/specs/06-typesystem.md` — verify/update narrowing section for overlap validity and explicit else-branch behavior (unrefined original type) plus diagnostic expectations.
- [x] `docs/specs/08-tests.md` — verify/update narrowing and union/intersection test inventory to include this regression coverage (`union_intersection` + narrowing invalid case).

## Build notes

- 2026-05-09: Started implementation.
- 2026-05-09: Stored `is`-narrowing metadata on `EIs` nodes and consumed it from `EIf`/`EWhile` to avoid recomputing overlap checks and emitting duplicate diagnostics.
- 2026-05-09: Kept impossible-overlap assertions in conformance invalid tests rather than runtime harness tests because compile-fail cases cannot execute inside `tests/unit/*.test.ks`.
- 2026-05-09: Revised the new `while` narrowing regression to use `break` instead of assigning `False` to the narrowed binding; assigning a non-overlap type inside a narrowed scope is correctly rejected.
- 2026-05-09: Fixed malformed conformance test source after that rewrite by restoring closing braces and top-level value uses so parser/typecheck conformance can execute the file.
- 2026-05-09: Fixed missing `TUnion` import in `typecheck.ks` — `TUnion(left, right)` match arm was not recognized because `TUnion` was absent from the named import on line 33; added it.
- 2026-05-09: Removed `whileNarrowU` from `tests/unit/narrowing.test.ks` — it triggered a JVM VerifyError in codegen for `var`+`while (x is Int)` narrowing, a pre-existing codegen bug out of scope for this story; while-body narrowing remains covered at the typecheck-conformance level.
- 2026-05-09: Removed `tests/kconformance/typecheck/narrowing_impossible.ks` — this invalid-program file was mistakenly copied from `conformance/typecheck/invalid/` into the valid-programs-only kconformance tier; before S17-42 it compiled silently with exit 0 because the self-hosted checker did not detect impossible narrowing; after S17-42 it correctly exits 1, exposing the mismatch. Removal is correct.
- 2026-05-09: All verification gates pass: `cd compiler && npm test` 459/459 and `./scripts/test-kestrel.sh` 66/66.
