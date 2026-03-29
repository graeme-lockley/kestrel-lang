# Namespace Imports (`import * as M`)


## Sequence: 34
## Former ID: 80
## Priority: 80 (Medium)

## Summary

Namespace imports (`import * as M from "..."`) are specified in spec 07 &sect;2.3 and parsed by the parser into `NamespaceImport` AST nodes. Implementation is complete: type checker, codegen, and module linker all support namespace imports. `M.length(s)` style qualified access works.

## Acceptance Criteria

- [x] **compile-file.ts**: When a `NamespaceImport` is encountered, resolve the specifier and compile the dependency. Collect ALL exported names from the dependency's `.kti` file.
- [x] **Type checker**: Register the namespace name (`M`) in the type environment as a namespace/module type. When `M.name` is encountered (FieldExpr on an IdentExpr that resolves to a namespace), look up `name` in the namespace's exported bindings and return its type.
- [x] **Codegen**: For `M.length(s)`, resolve `M.length` to the imported function index at compile time (same as a named import would), and emit the appropriate CALL instruction.
- [x] The namespace name must be an UPPER_IDENT (spec 07 &sect;2.3).
- [x] The namespace name must be unique in the module (no two `import * as M` with different specifiers).
- [x] Kestrel test: `import * as Str from "kestrel:string"` then `Str.length("hello")`.
- [x] Typecheck invalid: accessing a name that doesn't exist on the namespace. The missing name can be a val, var, fun, type alias, or type name (e.g. `Lib.NonExistentType`). *Note: Calling exported ADT constructors via the namespace (e.g. `Lib.PubNum(42)`) was not in scope; see backlog story for namespace constructor access.*

## Tasks

- [x] Add 'namespace' kind to InternalType and update type system (internal.ts, unify.ts)
- [x] Validate namespace name is UPPER_IDENT in parser
- [x] Handle NamespaceImport in compile-file.ts (collect exports, build namespace type, namespaceFuncIds, uniqueness)
- [x] Handle namespace FieldExpr in type checker
- [x] Handle namespace access in codegen (CallExpr and FieldExpr)
- [x] Write tests (Kestrel unit, compiler integration, compiler unit, type error)
- [x] Update specs (07-modules.md, verify 01-language.md)
- [x] Run full test suite

## Spec References

- 07-modules &sect;2.3 (Namespace import semantics)
- 01-language &sect;3.1 (ImportDecl grammar)
