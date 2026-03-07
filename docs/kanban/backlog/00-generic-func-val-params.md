# Generic Type Parameters on Functions and Values

## Priority: HIGH (complements generic type parameters on ADTs)

## Summary

Add support for generic type parameters on function and value declarations, enabling polymorphic functions and values:

```
fun identity<T>(x: T): T = x
fun map<T, U>(f: (T) -> U, xs: List<T>): List<U> = ...

val makePair<T>(a: T, b: T): (T, T) = (a, b)
```

## Current State

Currently fails to parse:
```
fun identity<T>(x: T): T = x
               ^ Expected lparen, got <
```

## Changes Required

### Parser (`parser/parse.ts`)
- Add optional `<TypeParamList>` after function name in `parseFunDecl`
- Similar to how it would work for type declarations

### AST (`ast/nodes.ts`)
- Add optional `typeParams?: string[]` to `FunDecl` node
- Add optional `typeParams?: string[]` to `ValDecl` node if needed

### Type Checker (`typecheck/check.ts`)
- Register type parameters in the type environment (similar to let-bound polymorphism)
- Handle type parameter scoping properly
- Support type argument inference at call sites

### Codegen (`codegen/codegen.ts`)
- May need runtime representation changes for generic functions (monomorphization or passing type tags)

## Acceptance Criteria

- [ ] Parse `fun identity<T>(x: T): T = x` successfully
- [ ] Parse `fun map<T, U>(f: (T) -> U, xs: List<T>): List<U>` (multiple type params)
- [ ] Type check generic function declarations
- [ ] Call generic functions with inferred type arguments
- [ ] Explicit type arguments at call sites: `identity<Int>(42)`
- [ ] Tests: Add generic function tests to `tests/unit/functions.test.ks`

## Example Usage After

```kestrel
fun identity<T>(x: T): T = x

val x = identity(42)           // x: Int = 42 (type inferred)
val y = identity<Int>(42)       // explicit type argument

fun map<T, U>(f: (T) -> U, xs: List<T>): List<U> = match (xs) {
  [] => []
  h :: t => f(h) :: map(f, t)
}

val nums = [1, 2, 3]
val doubled = map((x) => x * 2, nums)  // [2, 4, 6]
```

## Relationship to Other Stories

This story depends on `00-generic-type-params.md` (generic ADTs) because:
- Generic functions should work with generic ADTs
- Example: `fun unwrap<T>(o: Opt<T>): T` requires both features

After both stories, users can write idiomatic functional code:
```kestrel
type Opt<T> = None | Some(T)

fun mapOpt<T, U>(o: Opt<T>, f: (T) -> U): Opt<U> = match (o) {
  None => None
  Some(x) => Some(f(x))
}
```
