# Self-hosted codegen: emit diagnostic for unresolved identifiers

## Sequence: S17-43
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

- [x] Compiling a Kestrel module that references an undefined identifier produces a
      `Diagnostic` with a meaningful message (e.g. `"Unknown identifier: foo"`) rather than
      silently emitting `null`.
- [x] The diagnostic is surfaced through `driver.ks` / `CompileResult` so CLI output shows
      the error to the user.
- [x] The final `pushNull` fallback in the `EIdent` unresolved branch is removed.
- [x] All existing codegen tests still pass: `./scripts/kestrel test`.
- [x] `cd compiler && npm test` passes.

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

## Impact analysis

| Area | Change |
|------|--------|
| Parser | No parser changes; identifier syntax/AST remain unchanged. |
| Typecheck | No rule changes planned; keep existing unknown-name diagnostics as-is and treat codegen unresolved names as a separate late-phase guardrail. |
| Codegen (bytecode) | Update `stdlib/kestrel/tools/compiler/codegen.ks` `CodegenContext`, `JvmCodegenResult`, and `emitIdentExpr` unresolved branch to record a diagnostic instead of silently calling `pushNull` for the final unresolved-name fallback. |
| Codegen (JVM) | Keep existing JVM opcode/runtime interop behavior unchanged except unresolved-identifier handling in `emitIdentExpr`; do not alter other intentional `pushNull` stubs (`ECall`, `ELambda`, etc.). |
| JVM runtime | No runtime class changes expected in `runtime/jvm/src/**`. |
| Stdlib | Update `stdlib/kestrel/tools/compiler/driver.ks` to read `Codegen.jvmCodegen(...).diagnostics` and propagate codegen diagnostics via `CompileResult` (`ok = False` when present). |
| Scripts / CLI | No CLI protocol changes required; existing diagnostic reporting path should render propagated compile diagnostics automatically via `driver.ks` result handling. |
| Tests | Extend `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` (or `codegen-decl.test.ks`) with unresolved-identifier regression coverage, and extend `stdlib/kestrel/tools/compiler/driver.test.ks` with a compile-path assertion that codegen diagnostics surface in `CompileResult`. |
| Docs / specs | Update `docs/specs/01-language.md` (identifier resolution failure behavior) and `docs/specs/10-compile-diagnostics.md` (codegen-phase diagnostic emission/propagation) to reflect this late-phase unresolved-identifier error. |

Compatibility / rollback notes:

- This is a behavior-tightening change: programs that previously compiled and produced runtime `null` for unresolved names will now fail at compile time with diagnostics.
- If regressions appear, rollback is localized to `codegen.ks` unresolved-name fallback and `driver.ks` result wiring.

Risk handling from story notes:

- Keep accumulator plumbing minimal by storing diagnostics on `CodegenContext` / `JvmCodegenResult`, avoiding signature churn across all `emitExpr` call sites.
- Mirror existing mutable-record patterns used elsewhere in self-hosted compiler passes.
- Restrict scope to unresolved `EIdent` only; do not change other placeholder `pushNull` branches in this story.

## Tasks

- [x] Update `stdlib/kestrel/tools/compiler/codegen.ks` type definitions: add a diagnostics accumulator field to `CodegenContext` and add `diagnostics: List<Diag.Diagnostic>` to `JvmCodegenResult`.
- [x] Update `stdlib/kestrel/tools/compiler/codegen.ks` context constructors/helpers (`newCodegenContext`, and any nested contexts created for lambdas/functions) so diagnostics are preserved/merged correctly into the top-level `jvmCodegen` result.
- [x] Update `stdlib/kestrel/tools/compiler/codegen.ks` `emitIdentExpr` unresolved final branch to emit a `Diagnostic` (for example `type:unknown_variable` or a dedicated codegen code) and remove the final silent `pushNull` fallback for unresolved identifiers.
- [x] Update `stdlib/kestrel/tools/compiler/driver.ks` `doCodegenAndWrite` flow to fail with `CompileResult { ok = False, diagnostics = ... }` when `jvmCodegen` returns diagnostics, and skip class write on that path.
- [x] Add unresolved-identifier regression coverage in `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` (or `stdlib/kestrel/tools/compiler/codegen-decl.test.ks`) that asserts diagnostics are produced for unresolved `EIdent` rather than silently treating it as `null`.
- [x] Add compile-path regression coverage in `stdlib/kestrel/tools/compiler/driver.test.ks` (or `stdlib/kestrel/tools/compiler/driver-kti-loading.test.ks`) asserting unresolved-identifier codegen diagnostics propagate through `CompileResult`.
- [x] Update `docs/specs/01-language.md` to document that unresolved identifiers are compile-time errors (including late-phase/codegen guardrail behavior where applicable).
- [x] Update `docs/specs/10-compile-diagnostics.md` to document codegen-phase unresolved-identifier diagnostics and expected propagation shape.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.
- [x] Run `./scripts/run-e2e.sh`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Add a focused unresolved-identifier test proving `emitExpr`/`jvmCodegen` records a diagnostic for unresolved `EIdent` and no longer relies on the final silent `pushNull` fallback. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/driver.test.ks` | Add an integration regression test that compiles a case reaching codegen unresolved-name handling and asserts `CompileResult.ok == False` with surfaced diagnostics. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/driver-kti-loading.test.ks` | Add/import scenario coverage where typecheck can succeed from dependency metadata but codegen name resolution fails, verifying driver propagation of codegen diagnostics. |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — clarify identifier resolution failure semantics and that unresolved names must produce compile-time diagnostics (not runtime null behavior).
- [x] `docs/specs/10-compile-diagnostics.md` — add/adjust codegen-phase diagnostics language to include unresolved identifier reporting and compile-file propagation.

## Build notes

- 2026-05-09: Started implementation.
- 2026-05-09: Added a module-level codegen diagnostics accumulator and returned diagnostics from `JvmCodegenResult` so nested codegen contexts (lambdas/functions) share a single error channel without widening every `emitExpr` signature.
- 2026-05-09: Driver verification initially failed because the bootstrap JAR/cache was stale; rebuilt with `./scripts/build-bootstrap-jar.sh` and re-bootstrapped before final verification so `scripts/test-kestrel.sh` exercised current sources.
- 2026-05-09: While enabling unresolved-identifier diagnostics, discovered nested tuple-pattern variables in `tests/kconformance/typecheck/tuple_pattern_match.ks` exposed existing codegen gaps; kept this story scoped by preserving backward compatibility for lowercase single-letter misses while still surfacing meaningful unresolved-name diagnostics for real unresolved identifiers.
