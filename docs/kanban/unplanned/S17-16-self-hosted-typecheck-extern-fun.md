# Self-hosted typecheck for `extern fun` declarations

## Sequence: S17-16
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-17, S17-18, S17-19, S17-20, S17-21, S17-22 (sibling gap-closure stories), S17-23 (E2E)

## Summary

Teach the self-hosted typechecker (`stdlib/kestrel/dev/typecheck/typecheck.ks`) to accept,
prebind, and check `extern fun` declarations. Today the `_` arm of `checkDecls` rejects
`TDExternFun` with the diagnostic "Unsupported top-level declaration in self-hosted checker
MVP", and `prebindFunDecls` ignores it as well. As a result the self-hosted checker cannot
typecheck **any** stdlib module from source — every primitive library (`data/string`,
`data/list`, `io/fs`, `io/process`, etc.) declares its primitives as `extern fun`.

## Current State

`stdlib/kestrel/dev/parser/ast.ks` defines `TDExternFun(ExternFunDecl)`. The parser produces
these nodes correctly. The bootstrap TypeScript typechecker handles them. The self-hosted
typechecker:

- `prebindFunDecls` (≈ line 813) only matches `TDFun(fd)`; ignores `TDExternFun`.
- `checkDecls` (≈ line 952) does not have a `TDExternFun` arm and falls through to the `_`
  diagnostic at line 960.

Because the stdlib `.kti` files happen to be on disk (written by the bootstrap TS compiler),
the self-hosted compiler can today *use* extern functions through KTI imports, but it cannot
*recompile* the modules that declare them. `--clean` immediately exposes this gap.

## Relationship to other stories

- **Depends on**: nothing in this epic (parser + AST already support extern fun).
- **Blocks**: S17-23 (E2E validation). Without this story the self-hosted compiler cannot
  rebuild stdlib modules from scratch when the JVM cache is empty.
- **Companion**: S17-17 (extern type), S17-18 (extern import), S17-19 (exception),
  S17-20 (re-exports), S17-21 (top-level assign), S17-22 (cross-module ctor exhaustiveness)
  together close every "Unsupported top-level declaration" diagnostic raised by the MVP.

## Goals

1. Add a `TDExternFun(efd)` arm to `prebindFunDecls` so the function name and its declared
   signature are bound in the environment before expression checking begins.
2. Add a `TDExternFun(efd)` arm to `checkDecls` that:
   - converts the declared parameter and return AstTypes into `InternalType` via
     `FA.astTypeToInternalWithScope`,
   - generalizes the resulting `TArrow` over its declared type parameters,
   - inserts the binding into both `env` and (if `exported`) `exports`.
3. There is no body to check, so no inference is required — only signature registration.
4. Ensure exported extern function signatures appear in the resulting `TypecheckResult.exports`
   and therefore in the emitted KTI file.

## Acceptance Criteria

- [ ] `stdlib/kestrel/dev/basics.ks` (or any other stdlib file containing `extern fun`) is
      typecheckable end-to-end by the self-hosted typechecker without any "Unsupported
      top-level declaration" diagnostic.
- [ ] Running `KESTREL_JVM_CACHE=$(mktemp -d) ./scripts/kestrel run hello.ks` (clean cache,
      after S17-17/18/19 also land) succeeds without invoking Node.
- [ ] A new unit test in `stdlib/kestrel/dev/typecheck/typecheck.test.ks` covers a program
      whose body is a single `extern fun` declaration (exported and non-exported variants)
      and asserts the resulting `exports` map contains the expected name with the expected
      generalized type.
- [ ] An additional unit test verifies that a downstream module importing the extern fun
      typechecks successfully when the producer module is checked first.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes (with this story's tests included).

## Spec References

- `docs/specs/01-language.md` — `extern fun` declaration form
- `docs/specs/06-typesystem.md` — generalization of declared signatures
- `docs/specs/11-bootstrap.md` — self-hosted compiler responsibilities

## Risks / Notes

- The TS typechecker handles overload-style externs in some cases; verify whether the parser
  produces multiple `ExternFunDecl` nodes for an overloaded primitive or a single one with
  alternative signatures, and mirror the same treatment.
- Async externs (e.g. file I/O primitives) declare `: Task<T>` return types directly in the
  signature; no special handling is required because `TArrow` already accepts a `TApp("Task",
  [_])` as its codomain.
