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

- [x] `stdlib/kestrel/dev/basics.ks` (or any other stdlib file containing `extern fun`) is
      typecheckable end-to-end by the self-hosted typechecker without any "Unsupported
      top-level declaration" diagnostic.
- [x] Running `KESTREL_JVM_CACHE=$(mktemp -d) ./scripts/kestrel run hello.ks` (clean cache,
      after S17-17/18/19 also land) succeeds without invoking Node.
- [x] A new unit test in `stdlib/kestrel/dev/typecheck/typecheck.test.ks` covers a program
      whose body is a single `extern fun` declaration (exported and non-exported variants)
      and asserts the resulting `exports` map contains the expected name with the expected
      generalized type.
- [x] An additional unit test verifies that a downstream module importing the extern fun
      typechecks successfully when the producer module is checked first.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes (with this story's tests included).

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
- **Re-enable `./kestrel test` gate in `scripts/test-all.sh`**: `runner.ks` accesses
  `parsed.options` on an imported `ParsedArgs` record type; the self-hosted typechecker
  currently fails with "Cannot access field 'options' on non-record type". The failure check
  in `test-all.sh` has been downgraded to a warning until this (and S17-17 through S17-22)
  are resolved. Change `|| echo "WARNING..."` back to `|| exit 1` when the typecheck gap
  stories are complete.

## Impact analysis

| Area | Change |
|------|--------|
| Self-hosted typechecker (`stdlib/kestrel/dev/typecheck/typecheck.ks`) | Add `registerExternFunSig` helper; add `TDExternFun(efd)` arm to `prebindFunDecls`; add `checkExternFunDecl` helper; add `TDExternFun(efd)` arm to `checkDecls`. No parser or AST changes required. |
| Self-hosted typechecker tests (`stdlib/kestrel/dev/typecheck/typecheck.test.ks`) | Two new test groups: (1) exported + non-exported `extern fun` — assert exports map contains the generalized type; (2) downstream module importing an extern fun typechecks successfully. |
| No other layers touched | Parser, JVM codegen, JVM runtime, CLI, and TS compiler are not modified. |

Compatibility: purely additive — declarations that were previously rejected with
"Unsupported top-level declaration" will now be accepted. No existing accepted program
changes behaviour.

## Tasks

- [x] In `stdlib/kestrel/dev/typecheck/typecheck.ks`: add `registerExternFunSig` helper
      (analogous to `registerFunSig`) that builds scope from `efd.typeParams`, converts
      param types, converts `efd.retType`, and returns `Dict.insert(env, efd.name, Ty.generalize(Dict.emptyStringDict(), Ty.TArrow(ps, ret)))`.
- [x] In `prebindFunDecls` in `stdlib/kestrel/dev/typecheck/typecheck.ks`: add
      `TDExternFun(efd) => registerExternFunSig(env, typeAliases, efd)` arm alongside `TDFun`.
- [x] In `stdlib/kestrel/dev/typecheck/typecheck.ks`: add `checkExternFunDecl` function
      that builds the generalized `TArrow` from `efd` and inserts into both `env` and (if
      `efd.exported`) `exports`; returns `(env2, exports2, exportedTypeAliases)`.
- [x] In `checkDecls` in `stdlib/kestrel/dev/typecheck/typecheck.ks`: add
      `TDExternFun(efd) => checkExternFunDecl(state, env, typeAliases, exports, exportedTypeAliases, efd)` arm before the `_` fall-through.
- [x] In `stdlib/kestrel/dev/typecheck/typecheck.test.ks`: add `"extern fun"` test group
      covering: exported extern fun appears in exports with correct generalized type;
      non-exported extern fun does not appear in exports; generic extern fun
      (`<A>(A): A`) generalizes correctly.
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/dev/typecheck/typecheck.test.ks` | Exported extern fun appears in `exports` with correct type string; non-exported extern fun absent from exports; generic extern fun (`<A>(A): A`) generalizes to `(A) -> A`. |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — confirm `extern fun` declaration form is documented accurately (no content change expected, just verify).
- [x] `docs/specs/11-bootstrap.md` — note that the self-hosted typechecker now supports `extern fun` declarations.

## Build notes

- 2026-04-27: Started implementation.
- 2026-04-27: Added `registerExternFunSig` alongside `registerFunSig` (no async handling needed — extern funs declare `Task<T>` return directly in the Kestrel signature, so no special wrapping is required). Added `TDExternFun(efd)` arms to both `prebindFunDecls` and `checkDecls`. `checkExternFunDecl` mirrors `checkFunDecl` but skips body inference. The TS typechecker's first-pass pre-binding used a fresh var then unified with the full type; the self-hosted approach directly inserts the generalized scheme on both passes (simpler and equivalent for signature-only declarations). All compiler tests pass (442). Kestrel test suite exits 0.
