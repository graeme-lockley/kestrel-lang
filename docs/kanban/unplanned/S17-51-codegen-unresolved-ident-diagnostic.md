# Self-hosted codegen: emit diagnostic for unresolved identifiers

## Sequence: S17-51
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-25 (EIdent resolution), S17-02 (diagnostic propagation)

## Summary

When `emitExpr` in `codegen.ks` encounters an `EIdent` name that cannot be resolved
through any of the 9 resolution steps (local slot, global val/var, global fun, imported
val/var, imported fun, `None`, `Nil`, user nullary ADT ctor), it currently falls through
to `pushNull` as a silent fallback. This means an invalid identifier compiles without
error and produces a `null` at runtime, causing unpredictable failures rather than a clear
compile-time diagnostic.

The TS reference compiler (`compiler/src/jvm-codegen/codegen.ts`) throws an internal error
for this case. The self-hosted codegen needs an equivalent mechanism: accumulate a
`Diagnostic` record and surface it through `jvmCodegen`'s return value so the driver can
report it to the user.

## Current State

`codegen.ks` `EIdent` arm (line ~818): after all 9 resolution paths fail, the code calls
`pushNull(ctx)`. There is no diagnostic accumulation mechanism anywhere in the self-hosted
codegen pass. `jvmCodegen` currently returns `CodegenResult` (classes dict), with no
error channel.

## Relationship to other stories

- **Depends on**: S17-25 (establishes the 9-step `EIdent` resolution chain where the final
  `pushNull` fallback lives).
- **Depends on**: S17-02 (diagnostic type and `CompileResult` error channel already exist;
  this story wires the codegen pass into that channel).
- **Completes**: the acceptance criterion in S17-25 that was marked PARTIAL — "unresolved
  identifier name produces a compile error diagnostic".
- **No hard ordering against**: S17-26 through S17-38 (other expression forms) — can be
  delivered independently or bundled with a later expression story.

## Goals

1. Add a diagnostic accumulator to `CodegenContext` (a mutable list or equivalent) so any
   arm of `emitExpr` can record an error without aborting compilation immediately.
2. Change `jvmCodegen`'s return type to carry accumulated diagnostics alongside the classes
   dict (or return an error result when any diagnostics are present).
3. Replace the final `pushNull` fallback in the `EIdent` arm with a call that records an
   "unresolved identifier" diagnostic.
4. Update `driver.ks` to inspect the diagnostics returned by `jvmCodegen` and surface them
   through `CompileResult` (consistent with how typecheck diagnostics are handled).
5. Add a unit test that compiles a module containing an unknown identifier and asserts that
   a diagnostic (not a runtime null) is produced.

## Acceptance Criteria

- [ ] Compiling a Kestrel module that references an undefined identifier produces a
      `Diagnostic` with a meaningful message (e.g. `"Unknown identifier: foo"`) rather than
      silently emitting `null`.
- [ ] The diagnostic is surfaced through `driver.ks` / `CompileResult` so CLI output shows
      the error to the user.
- [ ] The final `pushNull` fallback in the `EIdent` unresolved branch is removed.
- [ ] All existing codegen tests still pass: `./scripts/kestrel test`.
- [ ] `cd compiler && npm test` passes.

## Spec References

- `docs/specs/01-language.md` — identifier scoping and name resolution
- `docs/specs/10-compile-diagnostics.md` — diagnostic format and propagation rules

## Risks / Notes

- The diagnostic accumulator design must not require large changes to every `emitExpr` call
  site — prefer a field on `CodegenContext` that is checked once at the end of `jvmCodegen`.
- Kestrel does not have mutable references in the usual sense; the accumulator may need to
  use a `var` field on the context record or be threaded explicitly. Mirror whichever pattern
  is already established in the self-hosted typecheck pass.
- The `pushNull` fallback for other stubs (e.g. `ECall`, `ELambda`) is intentional pending
  those stories — only the `EIdent` unresolved branch should be changed here.
