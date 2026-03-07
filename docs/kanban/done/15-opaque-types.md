# Opaque Types

## Priority: 15 (Critical)

## Summary

Introduce `opaque` as a type visibility qualifier. Types in Kestrel have three visibility levels:

1. **Local** (no qualifier): Type and constructors visible only within the declaring module.
2. **Opaque** (`opaque type`): The type **name** is exported (importers can use it in signatures and hold values of the type), but the **structure is hidden** (importers cannot construct values, destructure, or pattern-match). The declaring module has full access.
3. **Export** (`export type`): Both the type name **and** constructors/structure are exported. Importers can construct values and pattern-match on them.

This applies to both ADT definitions and type aliases.

## Dependencies

- Story 01 (User-Defined ADTs) should be done first so that opaque has something meaningful to hide.

## Design

### Syntax

```
// Local: only this module can use Color, Red, Green, Blue
type Color = Red | Green | Blue

// Opaque: importers can use Token in signatures but cannot construct or match
opaque type Token = Num(Int) | Op(String) | Eof

// Export: importers get full access to Shape and its constructors
export type Shape = Circle(Float) | Square(Float)

// Opaque type alias: importers see UserId as abstract, cannot use it as Int
opaque type UserId = Int

// Opaque record alias: importers see Config but cannot access fields
opaque type Config = { host: String, port: Int }
```

### Keyword

`opaque` is a new keyword added to the reserved words list (spec 01 &sect;2.4).

### Grammar

```
TypeDecl ::= [ "export" | "opaque" ] "type" UPPER_IDENT [ "<" TypeParamList ">" ] "=" TypeBody
```

The `opaque` keyword precedes `type` in the same position as `export`.

### Semantics

**Within the declaring module:**
- Full access. The module can construct values, pattern-match on constructors, access record fields, use the type alias's underlying type. No restrictions.

**For importers:**
- **Opaque ADT**: The type name is available (`Token`). Constructor names are NOT available. Attempting to use `Num(42)` or `match (t) { Num(n) => ... }` is a compile error ("constructor `Num` is not exported" or "cannot pattern-match on opaque type `Token`").
- **Opaque type alias**: The type name is available (`UserId`). The underlying type is NOT visible. A `UserId` value cannot be used as an `Int` (no implicit unwrapping). The module must provide explicit conversion functions (e.g., `export fun toInt(id: UserId): Int = ...`).
- **Opaque record alias**: The type name is available (`Config`). Field access is NOT available from outside. The module must provide accessor functions.

### Types file (.kti) representation

The `.kti` file for an opaque type exports the **name** and a **placeholder type** (e.g., `{ kind: "opaque", name: "Token" }`) instead of the full structure. This prevents consuming compilers from seeing the internal representation. Exported types include the full structure.

### Bytecode

No bytecode changes needed. Opaque is purely a compile-time visibility restriction. The ADT table, constructor tags, and heap layout are identical for opaque and exported types. The VM doesn't distinguish them.

## Acceptance Criteria

### Lexer/Parser
- [ ] Add `opaque` as a keyword.
- [ ] Parse `opaque type Foo = ...` producing an AST node with `visibility: 'opaque'`.
- [ ] Parse error if both `export` and `opaque` are used together.

### Type Checker
- [ ] Within the declaring module, opaque types have full access (construct, destructure, match).
- [ ] When type-checking an importing module:
  - Opaque ADT constructors are not in scope.
  - Pattern matching on an opaque ADT produces a type error.
  - Opaque type alias's underlying type is not visible (the type unifies only with itself).
  - Opaque record alias fields are not accessible.
- [ ] Error messages clearly state "type `X` is opaque; constructors are not accessible from this module" or similar.

### Types File / Module System
- [ ] `.kti` file distinguishes `export`, `opaque`, and `local` types.
- [ ] Opaque types in `.kti` include the type name but not the internal structure.
- [ ] Importing module receives the opaque marker and enforces restrictions.

### Tests
- [ ] Kestrel test: module A declares `opaque type Token = ...`, module B imports `Token`, uses it in signatures, but cannot construct or match.
- [ ] Kestrel test: module A declares `opaque type UserId = Int`, module B cannot treat a `UserId` as `Int`.
- [ ] Typecheck invalid: attempt to pattern-match on an opaque type from another module.
- [ ] Typecheck valid: declaring module can freely construct and match opaque types.

## Spec References

- 01-language &sect;2.4 (Keywords -- add `opaque`)
- 01-language &sect;3.1 (TypeDecl grammar -- add `opaque` qualifier)
- 06-typesystem (new section needed for opaque type checking rules)
- 07-modules &sect;3 (Exports: opaque types export name only)
- 07-modules &sect;5 (Types file: opaque type representation)
