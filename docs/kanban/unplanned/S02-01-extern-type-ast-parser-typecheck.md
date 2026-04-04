# `extern type` — AST Node, Parser, and Typecheck

## Sequence: S02-01
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/unplanned/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-02, S02-03, S02-04, S02-05, S02-06, S02-07, S02-08, S02-09, S02-10, S02-11, S02-12, S02-13

## Summary

Introduce `extern type` as a new top-level declaration that binds a named Kestrel type to a Java class descriptor. The declaration is opaque to importers — callers see only the Kestrel name, never the underlying Java class. This story covers only the frontend: AST node, parser rule, and typecheck pass. Codegen for `extern type` is trivially a no-op (the type is erased at the JVM level), so no codegen changes are needed here.

## Current State

- `compiler/src/ast/nodes.ts` has no `ExternTypeDecl` node. `TopLevelDecl` is the union `FunDecl | TypeDecl | ExceptionDecl | ExportDecl | ValDecl | VarDecl`.
- `compiler/src/parser/parse.ts` has no `extern` keyword handling. `parseTopLevelDecl` dispatches on `fun`, `async`, `type`, `opaque`, `val`, `var`, `exception`, and `export`. The token `extern` would currently fail to parse.
- `compiler/src/typecheck/check.ts` has no logic for `ExternTypeDecl`. The typecheck pass processes `TypeDecl` nodes, registering the type name and any alias or ADT body in its internal type environment.
- There is no `extern` token/keyword defined in `compiler/src/lexer/`. Adding it requires checking whether the lexer already recognises `extern` as an identifier or needs a new keyword definition.

## Relationship to other stories

- **Blocks S02-02** (`extern fun`): `extern fun` declarations reference `extern type` names as parameter and return types. Without `ExternTypeDecl` registered in the typecheck environment, `extern fun` signatures that reference `JHashMap` or similar names cannot be resolved.
- **Blocks S02-11** (dict rewrite): the dict rewrite requires `extern type JHashMap = jvm("java.util.HashMap")` to be well-formed.
- **Independent of S02-04 through S02-10** (migrations): migration stories use `jvm("kestrel.runtime.KRuntime#...")` descriptors which do not require any `extern type` in the stdlib (the parameters are all Kestrel primitives or built-in ADTs).

## Goals

1. `ExternTypeDecl` AST node with fields `name: string`, `typeParams?: string[]`, `jvmClass: string` (the string inside `jvm("...")`), and `visibility: 'local' | 'opaque' | 'export'`.
2. Lexer: `extern` keyword token (or verify the lexer already produces it as an identifier and the parser dispatches on identifier value).
3. Parser: `extern type Foo = jvm("fully.qualified.Class")` and `extern opaque type Foo = jvm("...")` and `export extern type Foo = jvm("...")` syntactic forms.
4. Typecheck pass: register the name as an opaque type alias in the environment. Within the module itself, the name is usable as a type in `extern fun` signatures. From outside the module, it behaves the same as any other exported opaque type.
5. Typecheck pass: reject duplicate `extern type` names and names that clash with existing type declarations.

## Acceptance Criteria

- [ ] `ExternTypeDecl` node is defined in `compiler/src/ast/nodes.ts` and included in the `TopLevelDecl` union.
- [ ] Parser parses `extern type HashMap = jvm("java.util.HashMap")` and `export extern type HashMap = jvm("java.util.HashMap")` without error.
- [ ] Parser rejects `extern type HashMap` (missing `= jvm(...)`) with a meaningful error.
- [ ] Parser rejects `extern type HashMap = "some-string"` (missing `jvm(...)` wrapper) with a meaningful error.
- [ ] Typecheck registers the name in the type environment so it can be used as a type in `extern fun` declarations within the same file.
- [ ] `ExternTypeDecl` with `visibility === 'export'` is included in the exported type surface (visible to importers as an opaque type).
- [ ] Typecheck error on duplicate `extern type` declaration in the same module.
- [ ] `cd compiler && npm test` passes.
- [ ] A parse-conformance test exists for `extern type` syntax.
- [ ] A typecheck-conformance test exists that verifies `extern type` names are accepted in type positions.

## Spec References

- `docs/specs/01-language.md` — add `extern type` to the declarations section.
- `docs/specs/06-typesystem.md` — note that `extern type` produces an opaque nominal type whose JVM representation is known to the compiler.

## Risks / Notes

- **`extern` as keyword vs. contextual keyword**: Adding `extern` as a full reserved keyword is simpler but is a breaking change if any existing Kestrel code uses `extern` as an identifier. The safer approach is to treat `extern` as a contextual keyword (only meaningful at the start of a declaration). Most languages do this. Check the test corpus for any `extern` usage before deciding.
- **JVM class descriptor format**: `jvm("fully.qualified.ClassName")` uses dot-separated class names (Java source form). The codegen must convert to internal JVM form (`fully/qualified/ClassName`) when emitting bytecode. Establish this conversion helper early (it will be reused by S02-02).
- **Type parameters**: `extern type JList<E> = jvm("java.util.List")` — type params on `extern type` are purely a Kestrel-side construct (Java erases them). The typecheck simply creates a generic alias. Codegen always maps to the raw JVM class regardless. Explicitly test this to avoid confusion.
- **No body typecheck needed**: Unlike `TypeDecl`, an `extern type` has no body to typecheck — the `jvm("...")` string is an opaque annotation for the codegen layer. Typecheck only validates form (valid string literal) and registers the name.
