# JVM Code Generator — Expressions and Patterns

## Sequence: S14-07
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/done/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-03, S14-04, S14-05, S14-06, S14-08, S14-09, S14-10, S14-11, S14-12, S14-13, S14-14

## Summary

Port the first half of `compiler/src/jvm-codegen/codegen.ts` (~3 640 lines) —
focusing on expression emission, literal encoding, arithmetic, comparison, boolean operators,
string building, lambda capture, record construction/access, tuple handling, match/pattern
dispatch, and `try/catch/throw` — to `stdlib/kestrel/tools/compiler/codegen.ks`.

The `codegen.ts` file is the largest single TypeScript source (~3 640 lines); it is split
across S14-07 (expressions + patterns) and S14-08 (function declarations, top-level emit,
tail-call lowering, and async/await transformation).

## Current State

The first logical half of `codegen.ts` (roughly lines 1–1 800) covers:
- `JvmCodegenContext` type — carries ClassFileBuilder, method scopes, local slots
- Expression codegen: `emitExpr(ctx, expr)` dispatching on `expr.kind`
  - Literals: `IntLit`, `FloatLit`, `BoolLit`, `StringLit`, `CharLit`, `UnitLit`
  - Identifiers and variable loads
  - Binary/unary operators
  - String interpolation (StringBuilder sequence)
  - Field access and record construction
  - Tuple construction
  - Lambda / closure capture (`KFunction` wrapping)
  - Match expressions with pattern dispatch
  - `if/then/else`
  - Block expressions (local `let`/`var`/`fun` stmts)
  - `try/catch/throw`
  - Cast (`as` expressions) and `is` narrowing

## Relationship to other stories

- **Depends on**: S14-05 (opcodes), S14-06 (ClassFileBuilder, MethodBuilder), S14-04 (inferred types)
- **Blocks**: S14-08 (codegen declarations depend on the expression emitter)

## Goals

1. Create `stdlib/kestrel/tools/compiler/codegen.ks` with:
   - `CodegenContext` record/opaque type
   - `emitExpr(ctx: CodegenContext, expr: Expr): Unit` with all expression variants
   - Pattern-matching dispatch helpers (`emitMatchArm`, `emitPattern`)
   - Lambda/closure builder helpers
   - Block-statement emitter for inner `let`/`var`/`fun`
   - Import all needed runtime class name constants (RUNTIME, KRECORD, etc.)

## Acceptance Criteria

- `stdlib/kestrel/tools/compiler/codegen.ks` compiles without errors (may export stubs for decl-level
  entry points needed by S14-08).
- Integration-style test: emit representative expression forms into a generated class and verify
  classfile bytes are produced without verifier/serialization failures.
- A test file `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` covers representative expression
  types (literals, arithmetic, match, record access) using the snapshot/golden approach.
- `./kestrel test stdlib/kestrel/tools/compiler/codegen-expr.test.ks` passes.
- `cd compiler && npm test` still passes.

## Spec References

- `compiler/src/jvm-codegen/codegen.ts` (lines 1–~1 800)
- `docs/specs/01-language.md` — all expression forms
- JVM spec §6 (opcode semantics)

## Risks / Notes

- Pattern match dispatch uses `tableswitch`/`lookupswitch` JVM opcodes with backpatch labels;
  this is complex and must be closely coordinated with the `MethodBuilder` from S14-06.
- Lambda capture requires allocating slots for captured variables and wrapping in `KFunction`;
  the exact slot accounting must replicate the TypeScript logic exactly.
- String interpolation emits a sequence of `StringBuilder.append` calls; ensure each segment
  type (Int, Bool, String) coerces correctly.
- `is`-narrowing side-channel (NarrowingByIsExpr WeakMap in TS) was noted in S14-04; the
  codegen must use the same annotation mechanism chosen in that story.
- This story is large (~1 800 lines of logic); proceed expression-kind by expression-kind.

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib compiler | Add `stdlib/kestrel/tools/compiler/codegen.ks` with expression/pattern emitter core, JVM runtime symbol constants, closure helpers, and block/match/try emission used by S14-08 decl-level emit. |
| Stdlib compiler deps | Integrate with `kestrel:tools/compiler/classfile`, `kestrel:tools/compiler/opcodes`, and `kestrel:tools/compiler/typecheck` inferred-type accessors for expression-level JVM emission decisions. |
| Kestrel tests | Add `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` for literal/binary/record/tuple/match expression emission and bytecode-shape smoke checks. |
| TypeScript regression guard | Keep `compiler/test/unit/jvm-codegen.test.ts` and integration suites passing unchanged while self-hosted codegen lands in parallel. |
| Specs/docs | Review `docs/specs/01-language.md` expression semantics against emitted JVM behaviour; update only if implementation reveals a spec mismatch. |

## Tasks

- [x] Create `stdlib/kestrel/tools/compiler/codegen.ks` with base `CodegenContext` shape, runtime class constants, and expression-entry APIs shared by S14-08.
- [x] Implement a compileable MVP `emitExpr` slice for core forms (`ELit`, `EIdent`, `EUnary`, `EBinary`, `EIf`, `EBlock`) using `MethodBuilder` emit primitives from S14-06.
- [x] Implement MVP structured-expression handlers for record/tuple/field/list/template and expression-list traversal.
- [x] Implement initial pattern/match helpers (`emitPattern`, `emitMatchArm`) and match-arm emission scaffold for S14-08 follow-on work.
- [x] Implement MVP lambda and try/throw/is emission placeholders so the expression dispatcher covers all current AST variants.
- [x] Add `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` covering literals, arithmetic/comparison, record+field access, tuple, lambda call, and simple `match` emission.
- [x] Run `NODE_OPTIONS='--max-old-space-size=8192' ./kestrel test stdlib/kestrel/tools/compiler/codegen-expr.test.ks`.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Verify expression emitter handles representative forms (`ELit`, `EBinary`, `EIf`, `EBlock`) and produces non-empty classfile output for each fixture. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Verify record/tuple construction and field read paths emit bytecode that executes correctly for a small fixture program. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Verify `match` + pattern dispatch compiles and executes for a simple ADT/List case, guarding branch-target/backpatch behaviour. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Verify lambda capture path emits executable closure bytecode for captured locals. |
| Vitest unit | `compiler/test/unit/jvm-codegen.test.ts` (existing) | Regression guard: bootstrap JVM codegen behaviour remains unchanged while self-hosted emitter is introduced. |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — reviewed expression-form semantics (`match`, lambda capture, try/catch/throw, field access, interpolation); no spec change was required for the MVP emission scaffold in this story.

## Build notes

- 2026-04-12: Started implementation.
- 2026-04-12: Landed an MVP self-hosted expression emitter scaffold in `kestrel:tools/compiler/codegen` that covers all current AST expression variants with compile-safe placeholder bytecode where full parity is deferred to S14-08.
- 2026-04-12: Added `codegen-expr.test.ks` to validate classfile emission across representative expression families and guard against verifier/serialization regressions.
