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

✅ **Complete.** Generic type parameters on functions parse, type-check, and execute correctly. Both top-level `fun` and block-level `fun` support `<TypeParamList>`. The spec (`01-language.md`) has been updated with the new `FunDecl` and block `fun` grammar. Unit tests cover identity, swap, first, second, and Option matching.

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

- [x] Parse `fun identity<T>(x: T): T = x` successfully
- [x] Parse `fun map<T, U>(f: (T) -> U, xs: List<T>): List<U>` (multiple type params)
- [x] Type check generic function declarations
- [x] Call generic functions with inferred type arguments
- [x] Works with user-defined ADTs (e.g., `Opt<T>`, `Result<T, E>`)
- [ ] Explicit type arguments at call sites: `identity<Int>(42)` (nice-to-have)
- [x] Tests: Existing test suite covers generic functions

## Tasks

- [x] Update AST: Add typeParams to FunDecl node
- [x] Update AST: Add typeParams to FunStmt node (for block functions)
- [x] Update Parser: Parse type params in parseFunDecl
- [x] Update Parser: Parse type params in block function definitions
- [x] Update Type Checker: Handle type params in FunDecl
- [x] Update Type Checker: Handle type params in block FunStmt
- [x] Fix ADT type param handling in constructor registration
- [x] Test basic generic function (identity)
- [x] Test generic function with multiple type params (map)
- [x] Test generic function with user-defined ADTs (Opt)
- [x] Verify all existing tests still pass

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
