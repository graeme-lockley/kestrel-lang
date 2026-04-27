# Self-hosted codegen: `ELambda` — closure class generation and free variable capture

## Sequence: S17-35
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-34, S17-36 through S17-38, S17-42

## Summary

`ELambda` in the self-hosted codegen pushes `null`. No lambda class is created, no closure
is formed. Any Kestrel program that uses a lambda expression (which includes all uses of
`Lst.map`, `Lst.filter`, `Dict.insert`, higher-order functions, and the entire test
framework) produces `null` at the lambda site.

## Current State

```kestrel
ELambda(_async, _tp, _params, _body) => pushNull(ctx)
```

TS reference: lambdas are compiled in two passes:
1. **Collection pass** (`collectLambdas`, ~200 lines): walks the AST, discovers all lambda
   expressions and local `fun` statements, computes free variables for each, assigns each
   a unique integer id, and builds `LambdaInfo` records.
2. **Emit pass** (`buildLambdaClass` / `buildAsyncLambdaPayloadClass`, ~100 lines each):
   for each lambda, emits a separate JVM class (`OuterClass$lambda_N`) that:
   - Captures free variables in an `Object[]` env field (if capturing).
   - Has a single `invoke(Object[])Object` (or `run()Object` for async) method.
   - The method body is emitted by a recursive `emitExpr` call with a free-var env.
3. **Usage site**: at the `ELambda` node, emit `NEW Lambda$N; DUP; INVOKESPECIAL <init>;`
   (if non-capturing) or `NEW Lambda$N; DUP; <build env array>; INVOKESPECIAL <init>(...);`
   (if capturing).

## Relationship to other stories

- **Depends on**: S17-27 (`ECall` — the lambda's `invoke` method also emits calls),
  S17-30/S17-32 (EIf/EMatch — lambda bodies can contain branches and matches).
- **Blocks**: S17-42 (E2E). Higher-order functions and the entire functional stdlib depend
  on lambdas.

## Goals

1. Implement a `collectLambdas` pass (or equivalent) that discovers all `ELambda` nodes
   and `SFun` statements, computes `freeVars`, and assigns unique ids.
2. For each lambda id, emit a `<ModuleName>$lambda_<id>` class file with an `invoke`
   method.
3. At each `ELambda` usage site: emit `NEW; DUP; <env array if capturing>; INVOKESPECIAL`.
4. Inside a capturing lambda body, resolve free vars from `env[i]` instead of `ALOAD`.
5. Handle `SFun` (local `fun` statements) that reference each other (mutual recursion via
   a `KRecord` slot).
6. Async lambdas (see S17-34 for async scaffolding): emit `KAsyncLambda` subclasses.

## Acceptance Criteria

- [ ] `Lst.map([1,2,3], (x) => x + 1)` compiles and produces `[2,3,4]`.
- [ ] A capturing lambda `val f = (y) => x + y` (capturing `x`) compiles correctly and
      returns `x + y` at the call site.
- [ ] A local recursive `fun fact(n) = if (n <= 1) 1 else n * fact(n-1)` inside a block
      compiles and returns the correct value.
- [ ] Mutually recursive local `fun` stmts inside a block work via the KRecord scheme.
- [ ] New codegen unit tests cover non-capturing lambda, capturing lambda, and local fun.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — lambda expressions and local fun statements

## Risks / Notes

- This is the most complex remaining codegen story. Lambda class generation requires a
  recursive invocation of the emitter with a different local scope. Refactoring `emitExpr`
  to be re-entrant (accepting scope maps as parameters) may be necessary.
- The TS reference uses a `Map<Expr, number>` to identify lambda nodes. The self-hosted
  version needs a comparable identity scheme — possibly using list indices or a mutable
  counter threaded through the AST walk.
