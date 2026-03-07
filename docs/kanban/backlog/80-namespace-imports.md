# Namespace Imports (`import * as M`)

## Priority: 80 (Medium)

## Summary

Namespace imports (`import * as M from "..."`) are specified in spec 07 &sect;2.3 and parsed by the parser into `NamespaceImport` AST nodes, but are not functional. The type checker, codegen, and module linker (`compile-file.ts`) all ignore namespace imports. This means `M.length(s)` style qualified access doesn't work.

## Current State

- **Parser** (`parse.ts` lines 124-130): Parses `import * as M from "spec"` into a `NamespaceImport` node with `name` and `spec` fields. Working.
- **AST** (`nodes.ts` lines 24-28): `NamespaceImport` interface defined.
- **Type checker** (`check.ts`): No awareness of namespace imports. `M.name` would be treated as field access on a variable `M`, which doesn't exist -> type error.
- **Codegen** (`codegen.ts`): No handling for namespace imports or qualified access.
- **compile-file.ts**: `getRequestedImports()` only handles `NamedImport`. `NamespaceImport` is silently skipped (lines 106-111, 310, 334).

## Acceptance Criteria

- [ ] **compile-file.ts**: When a `NamespaceImport` is encountered, resolve the specifier and compile the dependency. Collect ALL exported names from the dependency's `.kti` file.
- [ ] **Type checker**: Register the namespace name (`M`) in the type environment as a namespace/module type. When `M.name` is encountered (FieldExpr on an IdentExpr that resolves to a namespace), look up `name` in the namespace's exported bindings and return its type.
- [ ] **Codegen**: For `M.length(s)`, resolve `M.length` to the imported function index at compile time (same as a named import would), and emit the appropriate CALL instruction.
- [ ] The namespace name must be an UPPER_IDENT (spec 07 &sect;2.3).
- [ ] The namespace name must be unique in the module (no two `import * as M` with different specifiers).
- [ ] Kestrel test: `import * as Str from "kestrel:string"` then `Str.length("hello")`.
- [ ] Typecheck invalid: accessing a name that doesn't exist on the namespace.

## Spec References

- 07-modules &sect;2.3 (Namespace import semantics)
- 01-language &sect;3.1 (ImportDecl grammar)
