# Self-hosted codegen: `EIs` type narrowing, `ENever`, and codegen metadata (`JvmCodegenOptions`)

## Sequence: S17-38
## Tier: 8
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-37, S17-44

## Summary

Three remaining codegen gaps:

1. **`EIs` type-narrowing**: the self-hosted codegen always emits `True`, ignoring the
   tested type. The TS reference emits `INSTANCEOF TypeClass; ... IFEQ false; pushTrue`.
2. **`ENever`**: correctly emits `null` (acceptable stub since `never` expressions are
   unreachable by construction, but should emit `ATHROW` with an assertion error in debug
   builds to catch miscompilation).
3. **`JvmCodegenOptions`**: the TS reference's `jvmCodegen` accepts an options object that
   carries imported-name resolution tables (class names, arities, var sets, etc.) built from
   the KTI codegenMeta section. The self-hosted `jvmCodegen` currently accepts no options,
   so the driver cannot pass cross-module import information to the code generator. This is
   a prerequisite for correct `EIdent` and `ECall` resolution for imported names (S17-25,
   S17-27).

## Current State

- `EIs(e, _t)`: `{ emitExpr(ctx, e); pop; pushBoolBoxed(ctx, True) }` — always `True`.
- `ENever`: `pushNull(ctx)`.
- `jvmCodegen(moduleName, prog)`: no options parameter; `CodegenContext` has no import maps.
- `codegenMeta` in the KTI format records function arities and class names but is never read
  back and passed to `jvmCodegen`.

## Relationship to other stories

- **Depends on**: S17-24..S17-27 should be done first to make the options maps useful.
- `JvmCodegenOptions` extension is a **prerequisite** for S17-25 and S17-27 to have access
  to the import metadata built from KTI codegenMeta. If those stories are implemented
  before this one, they must use placeholder empty maps and be revisited.
- **Implement early sub-slice**: the `JvmCodegenOptions` part should land with or immediately
   adjacent to the S17-25 + S17-27 execution tranche, even if the `EIs` and `ENever` parts remain
   later in the roadmap sequence.
- **Blocks**: S17-44 (E2E) for programs using `is` type narrowing or cross-module import
  resolution.

## Goals

1. **`EIs(e, t)`**: emit `e`; `INSTANCEOF <jvm class for t>`; `IFEQ falseLabel`;
   `GETSTATIC Boolean.TRUE; GOTO end; falseLabel: GETSTATIC Boolean.FALSE; end:`.
2. **`ENever`**: keep `pushNull` for now (unreachable; acceptable) but add a comment noting
   it should emit `ATHROW` with an `AssertionError` in future.
3. **`JvmCodegenOptions`**: add an `options` parameter to `jvmCodegen` carrying:
   - `importedNameToClass: Dict<String, String>` — imported fun name → JVM class.
   - `importedFunArities: Dict<String, Int>` — imported fun name → arity.
   - `importedValVarToClass: Dict<String, String>` — imported val/var → class.
   - `importedVarNames: List<String>` — imported `var` names (need unboxing).
   - `importedNameToOriginal: Dict<String, String>` — local alias → original name.
4. Update `driver.ks` to build these maps from the loaded KTI `codegenMeta` sections and
   pass them to `jvmCodegen`.

## Acceptance Criteria

- [x] `x is String` evaluates to `True` when `x` is a String and `False` otherwise.
- [x] `x is Int` evaluates correctly for integer values.
- [x] After this story, S17-25 and S17-27 can use `options.importedNameToClass` to resolve
      cross-module identifiers and calls; regression tests for imported name resolution pass.
- [x] New codegen unit tests cover `EIs` for each primitive type.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — `is` type-narrowing expression
- `docs/specs/06-typesystem.md` — runtime type tests

## Risks / Notes

- The JVM class name for Kestrel's primitive types (`Int` → `java/lang/Long`, `Float` →
  `java/lang/Double`, `Bool` → `java/lang/Boolean`, `String` → `java/lang/String`, etc.)
  must match the boxing scheme used by the rest of codegen. Cross-check with TS
  `javaTypeNameToDescriptor`.
- Because this story mixes "import metadata plumb-through" with the narrower `EIs` / `ENever`
   work, it may be implemented in two commits inside one story: first the options plumbing needed
   by S17-25/S17-27, then the remaining `EIs` semantics.

## Impact analysis

| Area | Change |
|------|--------|
| Parser | No parser grammar changes are expected; `is` syntax already parses to `EIs`. |
| Typecheck | No new typing rules are expected; `is` narrowing behavior is already implemented. Confirm inferred-type access used by codegen is sufficient for tested primitive/object cases. |
| Codegen (bytecode) | No `.kbc` backend work in this story. |
| JVM codegen | Update `stdlib/kestrel/tools/compiler/codegen.ks` `emitExpr` arm for `EIs` to emit real `INSTANCEOF`/branching Boolean production instead of unconditional `True`; keep `ENever` as unreachable placeholder with explicit TODO comment for future `ATHROW` assertion mode. |
| JVM runtime | No runtime API changes expected; implementation should rely on JVM `INSTANCEOF` and existing boxed/runtime classes only. |
| Stdlib | `stdlib/kestrel/tools/compiler/driver.ks` already passes `JvmCodegenOptions` maps into `Codegen.buildModuleContext`; validate this path stays intact and remove any stale assumptions from this story's implementation notes if needed. |
| Scripts / CLI | No CLI behavior change; no script updates expected for this slice. |
| Tests | Extend self-hosted codegen tests in `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` for `EIs` opcode patterns and `ENever` behavior; add self-hosted conformance runtime coverage in `tests/kconformance/runtime/valid/` for `x is String` / `x is Int`. |
| Docs / specs | Update `specs/01-language.md` and `specs/06-typesystem.md` only if implementation details or constraints need clarification after parity alignment (especially runtime `is` behavior expectations). |

Compatibility and rollback notes:

- This is a behavior fix in the self-hosted JVM codegen path; it should only affect self-hosted output semantics for `is` expressions and should move behavior toward TS parity.
- Rollback is low risk: revert `EIs` emission and related tests if regressions surface, while keeping already-landed import metadata plumbing intact.
- Risk retained from unplanned notes: primitive-to-JVM class mapping must exactly match existing boxing conventions (`Int`/`Long`, `Float`/`Double`, `Bool`/`Boolean`, `String`/`String`) to avoid false positives/negatives in `INSTANCEOF` checks.

## Tasks

- [x] In `stdlib/kestrel/tools/compiler/codegen.ks`, replace the `EIs(e, _t)` placeholder emission in `emitExpr` with JVM parity logic: emit subject expr, `INSTANCEOF <target class>`, `IFEQ` false label, `GETSTATIC Boolean.TRUE`, `GOTO` end, false label `GETSTATIC Boolean.FALSE`.
- [x] In `stdlib/kestrel/tools/compiler/codegen.ks`, add/adjust helper mapping for tested AST types to JVM internal class names used by `EIs` emission (cover at least `Int`, `Float`, `Bool`, `String`, and constructor/object cases already represented by current codegen data structures).
- [x] In `stdlib/kestrel/tools/compiler/codegen.ks`, keep `ENever` as non-throwing unreachable placeholder but add an explicit comment/TODO documenting planned future debug-mode `ATHROW AssertionError` behavior.
- [x] In `stdlib/kestrel/tools/compiler/driver.ks`, verify `JvmCodegenOptions` plumbing remains complete for imported-name maps (`importedNameToClass`, `importedFunArities`, `importedValVarToClass`, `importedVarNames`, `importedNameToOriginal`) and adjust only if any key is missing for downstream `EIdent`/`ECall` parity.
- [x] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`, add unit-style bytecode assertions for `EIs` on representative primitive/object shapes to confirm `INSTANCEOF` + branch + boxed Boolean emission (not unconditional `True`).
- [x] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`, add regression assertions for `ENever` emission to document current placeholder behavior and guard against accidental regressions.
- [x] Add self-hosted runtime conformance tests under `tests/kconformance/runtime/valid/` validating `x is String` and `x is Int` true/false paths in executable programs.
- [x] Run `./scripts/test-kestrel.sh`.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.
- [x] Run `./scripts/run-e2e.sh`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel compiler unit (self-hosted) | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Assert `EIs` no longer compiles to unconditional `True`; verify emitted bytecode includes `INSTANCEOF` + conditional branch + `Boolean.TRUE`/`Boolean.FALSE` paths for primitive/object test cases. |
| Kestrel compiler unit (self-hosted) | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Assert `ENever` remains explicit placeholder behavior (current non-throwing path) with a regression guard documenting future throw-upgrade intent. |
| Kestrel conformance runtime (self-hosted corpus) | `tests/kconformance/runtime/valid/is_string_runtime.ks` | End-to-end runtime assertion: `x is String` yields `True` for strings and `False` for non-strings. |
| Kestrel conformance runtime (self-hosted corpus) | `tests/kconformance/runtime/valid/is_int_runtime.ks` | End-to-end runtime assertion: `x is Int` yields `True` for integer values and `False` for non-integer values. |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — verify/clarify `is` runtime truth paragraph to match emitted JVM behavior and tested primitive/object cases.
- [x] `docs/specs/06-typesystem.md` — verify/clarify narrowing/runtime type-test notes to reflect implemented backend parity assumptions.

## Build notes

- 2026-05-09: Started implementation.
- 2026-05-09: Impact-analysis drift: `JvmCodegenOptions` plumbing in `driver.ks`/`codegen.ks` was already present from earlier stories, so this story focuses on `EIs` JVM emission parity, `ENever` documentation, and regression coverage.
- 2026-05-09: `EIs` now uses direct JVM class tests from AST types; unknown/unmappable tested types intentionally default to `False` instead of crashing codegen.
- 2026-05-09: The planned docs checklist used `specs/...` paths, but this repo stores authoritative specs in `docs/specs/...`; updated checklist paths while applying the spec edits.
- 2026-05-09: First draft of the new kconformance runtime tests used explicit union annotations on `val` bindings and failed under `scripts/test-kestrel.sh`; switched to inference-only bindings to keep the runtime assertion focused on `is` behavior.
- 2026-05-09: Inference-only bindings still failed because `b is T` became an impossible narrow on monomorphic locals; final runtime tests route through union-typed function parameters to validate both true and false paths legally.
