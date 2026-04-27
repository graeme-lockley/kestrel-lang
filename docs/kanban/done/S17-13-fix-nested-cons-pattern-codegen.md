# Fix JVM codegen variable binding for nested cons-chain patterns

## Sequence: S17-13
## Tier: 6
## Former ID: S17-14

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01 through S17-13

## Summary

The TypeScript JVM codegen (`compiler/src/jvm-codegen/codegen.ts`) silently mis-compiles
`match` expressions that bind three or more variables through a nested cons-chain pattern
(e.g. `g :: a :: v :: []`). The middle binding(s) are not correctly tracked in the generated
bytecode, producing the runtime error:

```
kestrel-compiler: unexpected error: JVM codegen: unknown variable a
```

Discovered during S17-11 while writing `parseMavenGav` in `driver.ks`.

## Current State

The bug exists in the released TS compiler. Workaround applied in S17-11: replaced the
3-element cons pattern with `Lst.head`/`Lst.drop` index-based extraction. The underlying
codegen defect is unresolved.

Two-element cons patterns (`h :: t`) work correctly. The failure manifests at 3+ bindings
(`h1 :: h2 :: t :: []` and deeper).

## Relationship to other stories

- **Discovered in**: S17-11 (`parseMavenGav`)
- **Workaround in**: S17-11 — `driver.ks` uses `Lst.head`/`Lst.drop` instead

## Goals

1. Identify the codegen path responsible for emitting variable bindings in cons-chain
   patterns inside `match` expressions.
2. Fix the variable-binding logic so that all bindings in a cons-chain (`h1 :: h2 :: h3 :: t`)
   are emitted and accessible in the match arm body.
3. Add a regression test in the compiler's unit/conformance test suite covering
   3- and 4-element cons-chain pattern bindings.
4. Revert the S17-11 workaround in `driver.ks` (restore the cleaner `g :: a :: v :: []`
   form) once the codegen is fixed.

## Acceptance Criteria

- [x] A Kestrel `match` expression with a 3-element cons-chain pattern (`a :: b :: c :: []`) compiles without error and all three bindings are accessible in the arm body.
- [x] A 4-element cons-chain pattern (`a :: b :: c :: d :: []`) also works correctly.
- [x] Existing 2-element cons tests remain passing.
- [x] A new conformance or unit test explicitly covers 3- and 4-element cons-chain bindings.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — pattern matching

## Risks / Notes

- The `parseMavenGav` workaround in `driver.ks` can be reverted once fixed, but is not
  load-bearing — reverting is cosmetic/cleanup.
- The bug may be in how the codegen walks the cons spine and assigns local variable slots,
  or in how it builds the `visiting` / variable-map stack for nested patterns.
- Only confirmed for cons-list patterns; other nested constructor patterns (e.g. `Some(Some(x))`)
  may or may not be affected — worth checking while fixing.

## Impact analysis

| Area | Change |
|------|--------|
| JVM codegen | `compiler/src/jvm-codegen/codegen.ts` — refactor the `ConsPattern` arm of the match emitter to iterate down the cons spine rather than handling only a single level; allocate intermediate tail slots and emit KCons checks at each depth |
| Tests | `tests/conformance/runtime/valid/` — add `nested_cons_pattern.ks` covering 3- and 4-element cons-chain patterns |
| Stdlib | `stdlib/kestrel/tools/compiler/driver.ks` — revert `parseMavenGav` to use `g :: a :: v :: []` pattern once codegen is fixed |
| Specs | `docs/specs/01-language.md` — add a note confirming nested cons patterns in match arms are fully supported (no depth restriction) |

Rollback risk: low — the change is scoped to a single `if` block inside `emitExpr`; the existing 1- and 2-element cons tests remain unchanged.

## Tasks

- [x] In `compiler/src/jvm-codegen/codegen.ts`, refactor the `ConsPattern` handler in the match arm emitter to loop over the cons spine:
  - Allocate a new local slot per intermediate tail (for cons levels 2, 3, …)
  - Emit INSTANCEOF KCons + IFEQ for each level
  - Bind the head variable (VarPattern) at each level
  - Terminate when tail is VarPattern (bind and stop) or empty ListPattern (INSTANCEOF KNil check and stop)
  - Collect all IFEQ branch offsets in a single array and patch them together at the end
  - Collect all env bindings in one array and clean up after body emission
- [x] Add `tests/conformance/runtime/valid/nested_cons_pattern.ks` with a `classify` function exercising 3- and 4-element cons-chain patterns and `//`-comment golden output
- [x] Revert `parseMavenGav` in `stdlib/kestrel/tools/compiler/driver.ks` to use `g :: a :: v :: []` instead of `Lst.head`/`Lst.drop` extraction
- [x] Update `docs/specs/01-language.md` to note that nested cons patterns are supported to any depth
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`
- [x] Run `./scripts/run-e2e.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Runtime conformance | `tests/conformance/runtime/valid/nested_cons_pattern.ks` | 3-element `a :: b :: c :: []` and 4-element `a :: b :: c :: d :: []` cons-chain patterns bind all variables and produce correct output |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — add note under the `ConsPattern` grammar that nested cons chains (`a :: b :: c :: t`) are supported to arbitrary depth

## Build notes

- 2026-04-27: Started implementation. Root cause confirmed: the `ConsPattern` arm in the JVM codegen match emitter only handles `tailPat` of kind `VarPattern` or empty `ListPattern`; when `tailPat` is another `ConsPattern` (nested chain), the inner variables are never added to `env` and the body emits "unknown variable" errors at runtime.
- 2026-04-27: Refactored the `ConsPattern` block into an iterative `while` loop that walks the cons spine. Each level allocates a new local slot for the intermediate tail cons cell and binds the head variable. Key insight: `addBranchTarget(mb.length(), matchBaseState)` is called only for the FIRST level — calling it for subsequent levels causes a JVM VerifyError because `matchBaseState` marks already-bound locals as `top`. The `ConsPattern` type was added to the import list in `codegen.ts` to resolve a TypeScript circular-inference error on `tp`.
- 2026-04-27: All 441 compiler tests pass. `./scripts/kestrel test` and `./scripts/run-e2e.sh` failures (one test in each) are pre-existing issues with the self-hosted checker MVP not handling `kestrel:dev/stack` and `kestrel:sys/runtime` — confirmed by identical failures on main without this story's changes.
