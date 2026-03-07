# Generic Anonymous Functions (Lambdas)

## Priority: MEDIUM

## Summary

Add support for generic type parameters on anonymous functions (lambda expressions):

```kestrel
val identity = <T>(x: T) => x
val makePair = <T>(a: T, b: T) => (a, b)
```

## Current State

Currently fails to parse:
```
val f = <T>(x: T) => x
            ^ Expected expression
```

## Changes Required

### Parser (`parser/parse.ts`)
- Add optional `<TypeParamList>` after `\` in `parseLambdaExpr`
- Similar to how it works for function declarations

### AST (`ast/nodes.ts`)
- Add optional `typeParams?: string[]` to `LambdaExpr` node

### Type Checker (`typecheck/check.ts`)
- Register type parameters in lambda scope
- Handle type parameter inference at call sites
- Similar to how generic functions are handled

### Codegen (`codegen/codegen.ts`)
- May need runtime representation for generic lambdas
- Likely works similarly to generic functions

## Acceptance Criteria

- [ ] Parse `<T>(x: T) => x` successfully
- [ ] Parse `<T, U>(f: (T) => U, x: T) => f(x)` (multiple type params)
- [ ] Type check generic lambda expressions
- [ ] Call generic lambdas with inferred type arguments
- [ ] Tests: Add generic lambda tests to unit tests
- [ ] Docs: Update all relevant docs in docs/spec

## Example Usage After

```kestrel
val identity = <T>(x: T) => x
val x = identity(42)           // x: Int = 42 (type inferred)

val makePair = <T>(a: T, b: T) => (a, b)
val p = makePair(1, 2)         // p: (Int, Int) = (1, 2)

// With type annotation
val safeCast = <T, U>(x: T) => x as U
```
