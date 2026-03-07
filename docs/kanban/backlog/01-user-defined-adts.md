# User-Defined Algebraic Data Types (ADTs)

## Priority: 01 (Critical)

## Summary

User-defined ADTs are a core language feature (spec 01: "Algebraic data types", spec 06 &sect;1: "ADT: user-defined via `type` with constructors") but are **completely unimplemented**. The `type` declaration is currently treated as a type alias only. All ADT support (List, Option, Result, Value) is hardcoded. This blocks users from defining any custom sum types, which is fundamental to idiomatic Kestrel.

## Design Decisions

### Constructor Syntax

Constructors take **positional arguments** in parentheses, consistent with Kestrel's function call syntax `f(x)`:

```
type Option = None | Some(Int)
type Tree = Leaf(Int) | Node(Tree, Tree)
type Color = Red | Green | Blue
```

- **No-payload constructor**: `Red`, `None` -- no parentheses.
- **Single-payload constructor**: `Some(10)`, `Leaf(42)` -- parenthesized value.
- **Multi-payload constructor**: `Node(left, right)` -- multiple positional args.
- **Record as payload**: If you want named fields, pass a record: `MkPerson({ name = "Alice", age = 30 })`.

Constructors are functions: `Some : (Int) -> Option`, `Node : (Tree, Tree) -> Tree`, `Red : Color`.

### Patterns

Pattern matching uses the same parenthesized syntax:

```
match (opt) {
  None => 0
  Some(x) => x
}

match (tree) {
  Leaf(v) => v
  Node(l, r) => size(l) + size(r)
}
```

### Grammar

```
TypeDecl     ::= [ "export" | "opaque" ] "type" UPPER_IDENT [ "<" TypeParamList ">" ] "=" TypeBody
TypeBody     ::= Type                                    /* type alias */
               | Constructor { "|" Constructor }         /* ADT definition */
Constructor  ::= UPPER_IDENT [ "(" TypeList ")" ]        /* 0 or more positional payload types */
TypeParamList ::= UPPER_IDENT { "," UPPER_IDENT }
```

Detection heuristic: if the RHS starts with an UPPER_IDENT that is NOT a known type name (or is followed by `|`), treat it as an ADT definition. Otherwise treat it as a type alias.

## Current State

### Every layer needs work:

**AST (`ast/nodes.ts`):**
- `TypeDecl` has only `name` and `type` -- no constructors array, no type parameters.
- No `ADTDecl` or `ConstructorDef` AST node exists.

**Parser (`parser/parse.ts`):**
- `type Foo = <Type>` parses the RHS as a type expression only.
- No syntax for `Constructor(Type, ...)` in the type position.

**Type Checker (`typecheck/check.ts`):**
- `TypeDecl` is stored as a simple type alias.
- Constructors registered only for 4 hardcoded built-ins (Option, Result, List, Value).
- Exhaustiveness checking uses a hardcoded `requiredSets` map.
- `bindPattern` for `ConstructorPattern` only handles hardcoded types.

**Codegen (`codegen/codegen.ts`):**
- ADT table has exactly 4 entries (List=0, Option=1, Result=2, Value=3), never appended to.
- `getBuiltinConstructor()` returns `null` for unknown constructor names.
- `getMatchConfig()` returns `null` for unknown ADT types.
- `TypeDecl` is completely skipped during codegen.

## Acceptance Criteria

### AST
- [ ] New AST node for ADT declarations with: `name`, optional `typeParams`, `constructors: { name: string, params: Type[] }[]`, and `visibility: 'local' | 'opaque' | 'export'`.
- [ ] Parser produces ADT node for multi-constructor type declarations.
- [ ] Parser still produces TypeDecl for simple type aliases.

### Parser
- [ ] Parse `type Color = Red | Green | Blue` -- 3 no-payload constructors.
- [ ] Parse `type Option = None | Some(T)` -- mixed nullary and unary constructors.
- [ ] Parse `type Tree = Leaf(Int) | Node(Tree, Tree)` -- multi-arg constructors.
- [ ] Parse `type Pair = MkPair(Int, String)` -- single constructor with multiple positional args.
- [ ] Parse `export type Color = Red | Green | Blue` -- exported ADT.

### Type Checker
- [ ] Register each constructor as a function in the type environment:
  - `Red : Color` (nullary -- a constant of type Color)
  - `Some : (T) -> Option<T>` (unary -- a function)
  - `Node : (Tree, Tree) -> Tree` (multi-arg -- a function)
- [ ] Build a **constructor registry** (not hardcoded) mapping ADT name -> list of constructor names + arities.
- [ ] Exhaustiveness checking uses the constructor registry instead of hardcoded `requiredSets`.
- [ ] `bindPattern` for `ConstructorPattern` looks up the constructor in the registry to determine payload count and types.
- [ ] Type inference: `match (x) { Red => ... }` infers `x` has type `Color`.

### Codegen
- [ ] Append user-defined ADTs to the `adts` table (after the built-in ones).
- [ ] Rename `getBuiltinConstructor` to `getConstructor` and extend to look up user-defined constructors.
- [ ] Emit `CONSTRUCT` for user-defined constructors with correct `adt_id`, `ctor` (index), and `arity`.
- [ ] Extend `getMatchConfig` to generate jump tables for user-defined ADTs.
- [ ] `compilePattern` handles user-defined constructor patterns with positional field binding via GET_FIELD by index.

### Tests
- [ ] Parse test: multi-constructor ADT with various payload arities.
- [ ] Typecheck valid: construct and match on user-defined ADT.
- [ ] Typecheck invalid: non-exhaustive match on user-defined ADT.
- [ ] E2E test: define ADT, construct values, match, print results.
- [ ] Kestrel unit test: `tests/unit/adts.test.ks` with custom ADTs.

## Spec References

- 01-language &sect;3.1 (TypeDecl grammar -- needs update)
- 03-bytecode-format &sect;10 (ADT table)
- 04-bytecode-isa &sect;1.7 (CONSTRUCT, MATCH)
- 05-runtime-model &sect;2 (ADT heap objects)
- 06-typesystem &sect;1, &sect;5 (ADT types, exhaustiveness)
