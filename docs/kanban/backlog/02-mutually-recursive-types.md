# Mutually Recursive and Self-Recursive Types

## Priority: 02 (Critical)

## Summary

Self-recursive types (e.g., `type Tree = Leaf(Int) | Node(Tree, Tree)`) and mutually recursive types (e.g., `type Stmt` referencing `Expr` and `type Expr` referencing `Stmt`) are essential for representing tree structures, ASTs, and most non-trivial data models. The compiler must use a two-pass approach for type declarations within a module so that forward references resolve correctly.

## Dependencies

- Story 01 (User-Defined ADTs) is a prerequisite. This story extends ADT support to handle self-referential and mutually-referential type definitions.

## Design

The standard approach for recursive types in an ML-family language:

### Two-pass type registration

All `type` declarations in a module (or block) are processed in two passes:

1. **Forward declaration pass**: Before checking any type body, register all type names in the environment with placeholder types (fresh type variables or opaque name markers). This makes every type name available for reference by every other type body.

2. **Definition pass**: Process each type body. Self-references (`Tree` inside `Node(Tree, Tree)`) and mutual references (`TypeB` inside `AB(TypeB)` where `TypeB` is declared later) resolve to the placeholders, which are then unified or replaced with the actual type.

This is analogous to how top-level functions already work in Kestrel (all function names are in scope for all function bodies, regardless of declaration order).

### Self-recursive example

```
type Tree = Leaf(Int) | Node(Tree, Tree)

fun depth(t: Tree): Int = match (t) {
  Leaf(_) => 1
  Node(l, r) => {
    val ld = depth(l)
    val rd = depth(r)
    if (ld > rd) ld + 1 else rd + 1
  }
}
```

### Mutually recursive example

```
type Expr = Lit(Int) | Add(Expr, Expr) | IfExpr(BoolExpr, Expr, Expr)
type BoolExpr = BTrue | BFalse | Not(BoolExpr) | Eq(Expr, Expr)
```

Here `Expr` references `BoolExpr` and `BoolExpr` references `Expr`. Both must be in scope for each other's body. Declaration order must not matter.

### Occurs check

Standard HM unification includes an occurs check to prevent infinite types (`T = List<T>`). For ADT self-references, the recursion is **guarded by a constructor** and is structurally well-founded -- the occurs check must be relaxed for named ADT type references. The key distinction:

- `type Bad = Bad` -- infinite type, should be rejected (or is meaningless).
- `type Tree = Leaf(Int) | Node(Tree, Tree)` -- valid recursive ADT (recursion is guarded by constructors `Leaf` and `Node`).
- `type Loop = List<Loop>` -- potentially infinite type alias, should be rejected.

The rule: self-reference through an ADT constructor is valid; self-reference through a type alias is infinite and should be rejected.

### Bytecode representation

No special bytecode encoding needed. A recursive type's ADT table entry references the same `adt_id` that the type itself defines. Constructor payloads that reference the same or another ADT just use the corresponding `type_index` in the type table. The VM doesn't need to know about recursion -- it only sees constructor tags and payload slots.

## Acceptance Criteria

- [ ] **Self-recursive ADT**: `type Tree = Leaf(Int) | Node(Tree, Tree)` compiles and runs.
- [ ] **Construction**: `Node(Leaf(1), Leaf(2))` type-checks and emits correct CONSTRUCT instructions.
- [ ] **Pattern matching**: `match (tree) { Leaf(v) => v; Node(l, r) => ... }` works with exhaustiveness checking.
- [ ] **Mutually recursive types**: `type A = AA(Int) | AB(B)` and `type B = BA(Int) | BB(A)` where both reference each other -- both compile correctly regardless of declaration order.
- [ ] **Recursive type in function signature**: `fun depth(t: Tree): Int = ...` type-checks.
- [ ] **Infinite type alias rejected**: `type Bad = Bad` or `type Loop = List<Loop>` produces a type error.
- [ ] **Two-pass registration**: The type checker uses a forward declaration pass so all type names are available in all type bodies.
- [ ] E2E test: binary tree with construction, pattern matching, and recursive traversal.
- [ ] E2E test: mutually recursive types with cross-referencing constructors.
- [ ] Kestrel unit test covering self-recursive and mutually recursive ADTs.

## Spec References

- 01-language &sect;3.1 (TypeDecl; top-level recursion note should be extended to types)
- 06-typesystem &sect;3 (Unification with occurs check -- must be relaxed for named ADT recursion)
- 06-typesystem &sect;5 (Match exhaustiveness on recursive ADTs)
