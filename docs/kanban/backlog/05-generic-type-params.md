# Generic Type Parameters on Type Declarations

## Priority: 05 (High)

## Summary

Currently, user-defined ADTs cannot have type parameters, which limits their usefulness. Users must write `type Opt = None | Some(Int)` instead of the more general `type Opt<T> = None | Some(T)`.

This story adds syntax for generic type parameters on `type` declarations:

```
type Opt<T> = None | Some(T)
type Tree<T> = Leaf(T) | Node(Tree<T>, Tree<T>)
type Result<T, E> = Ok(T) | Err(E)
```

## Current State

The parser currently expects `type NAME = ...` but fails when seeing `<` after the type name:
```
type Opt<T> = ...
           ^ Expected lparen, got <
```

## Changes Required

### Parser (`parser/parse.ts`)
- Add support for optional `<TypeParamList>` after type name in `parseTypeDecl`
- The TypeParamList parsing should be similar to the existing one for functions (if any)

### AST (`ast/nodes.ts`)
- Add optional `typeParams?: string[]` to `TypeDecl` node
- Add optional type parameter support in `ADTBody` constructors if needed

### Type Checker (`typecheck/check.ts`)
- Register type parameters in the type environment when processing generic ADTs
- Use type parameters when unifying constructor payload types

### Codegen (`codegen/codegen.ts`)
- Handle generic ADTs in the ADT table - may need runtime representation changes

## Acceptance Criteria

- [ ] Parse `type Opt<T> = None | Some(T)` successfully
- [ ] Parse `type Tree<T> = Leaf(T) | Node(Tree<T>, Tree<T>)` (recursive generic)
- [ ] Parse `type Result<T, E> = Ok(T) | Err(E)` (multiple type params)
- [ ] Type check generic ADT declarations
- [ ] Match on generic ADT values works correctly
- [ ] Tests: Update `tests/unit/adts.test.ks` to use generic syntax

## Example Usage After

```kestrel
type Opt<T> = None | Some(T)

fun unwrap<T>(o: Opt<T>, default: T): T = match (o) {
  None => default
  Some(x) => x
}

val x = unwrap(Some(42), 0)        // x: Int = 42
val y = unwrap(Some("hi"), "")     // y: String = "hi"
val z = unwrap(None, 100)          // z: Int = 100
```
