# Self-hosted typecheck for `exception` declarations

## Sequence: S17-19
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-16, S17-17, S17-18, S17-20, S17-21, S17-22, S17-23

## Summary

Teach the self-hosted typechecker to accept `exception` declarations (`TDException`). The
self-hosted codegen already handles `TDException`, but the typechecker rejects them with
"Unsupported top-level declaration in self-hosted checker MVP". This blocks any stdlib module
that declares its own exception types (including the canonical patterns documented in the
`throw` / `try` sections of the language spec).

## Current State

- AST: `TDException(ExceptionDecl)` is defined in `stdlib/kestrel/dev/parser/ast.ks`.
- Codegen: `stdlib/kestrel/tools/compiler/codegen.ks` already has a `TDException(exnDecl)`
  arm (around line 213).
- Typechecker: no arm in `prebindTypeDecls` or `checkDecls` (line 960 fall-through).

## Relationship to other stories

- **Depends on**: nothing in this epic.
- **Blocks**: S17-23 (E2E) for any stdlib file declaring exceptions.
- **Companion**: S17-16, S17-17, S17-18, S17-20, S17-21, S17-22.

## Goals

1. Extend `prebindTypeDecls` to register the exception name as a type whose constructor takes
   the declared field types and returns the new exception type (analogous to ADT registration).
2. Add a `TDException(exn)` arm to `checkDecls` that:
   - registers the exception's constructor signature in `env` (and `exports` if exported),
   - registers the type itself in `exportedTypeAliases`/`exportedTypeVisibility` so importing
     modules can refer to it.
3. Verify that `throw FooException(...)` and `try { ... } catch (FooException(x))` patterns
   typecheck against locally and import-defined exception types.

## Acceptance Criteria

- [ ] A program containing `exception MyError(message: String)` typechecks under the
      self-hosted checker with no diagnostics.
- [ ] A `try { ... } catch (MyError(m)) { ... }` block typechecks correctly, with `m` bound
      to `String` in the handler.
- [ ] An exported exception is consumable by an importing module via KTI.
- [ ] A new unit test in `typecheck.test.ks` covers exported and non-exported exception
      declarations, throw expressions, and catch patterns.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — `exception`, `throw`, `try` semantics
- `docs/specs/06-typesystem.md` — how exception types interact with inference

## Risks / Notes

- The catch-pattern type rule must resolve the binding type correctly (the existing `ETry`
  inference uses pattern matching machinery; verify it composes with import-defined exception
  constructors after S17-22).
- Cross-check with TS reference (`compiler/src/typecheck/check.ts`) to mirror the constructor
  generalization scheme.
