# Fix JVM codegen variable binding for nested cons-chain patterns

## Sequence: S17-14
## Tier: 6
## Former ID: (none)

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

- [ ] A Kestrel `match` expression with a 3-element cons-chain pattern (`a :: b :: c :: []`) compiles without error and all three bindings are accessible in the arm body.
- [ ] A 4-element cons-chain pattern (`a :: b :: c :: d :: []`) also works correctly.
- [ ] Existing 2-element cons tests remain passing.
- [ ] A new conformance or unit test explicitly covers 3- and 4-element cons-chain bindings.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — pattern matching

## Risks / Notes

- The `parseMavenGav` workaround in `driver.ks` can be reverted once fixed, but is not
  load-bearing — reverting is cosmetic/cleanup.
- The bug may be in how the codegen walks the cons spine and assigns local variable slots,
  or in how it builds the `visiting` / variable-map stack for nested patterns.
- Only confirmed for cons-list patterns; other nested constructor patterns (e.g. `Some(Some(x))`)
  may or may not be affected — worth checking while fixing.
