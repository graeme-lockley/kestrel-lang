# JVM Code Generator — Declarations and Top-Level Emit

## Sequence: S14-08
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-03, S14-04, S14-05, S14-06, S14-07, S14-09, S14-10, S14-11, S14-12, S14-13, S14-14

## Summary

Port the second half of `compiler/src/jvm-codegen/codegen.ts` (roughly lines 1 800–3 640) —
covering function declarations, tail-call optimisation (self and mutual), async/await
transformation to `KTask`, ADT constructor generation, `extern fun` dispatch, `val`/`var`
initialisation, exception declarations, and the top-level `jvmCodegen(program)` entry point —
completing the code generator in `stdlib/kestrel/compiler/codegen.ks`.

## Current State

The second logical half of `codegen.ts` covers:
- `emitFunDecl` — emit static method for a `fun` declaration; handle closures
- Direct self-tail-call lowering (GOTO loop-head)
- Mutual-tail-call dispatch (state-machine loop)
- Async/await transformation to KTask.andThen chains
- ADT constructor class generation (one inner class per constructor)
- `extern fun` binding dispatch (JVM method call, field load, constructor)
- `val`/`var` declaration initialisation and getter/setter statics
- `exception` declaration (outer KException subclass)
- `jvmCodegen(program, …): JvmCodegenResult` — iterates all top-level decls and produces
  a `Map<className, ByteArray>` of class files

## Relationship to other stories

- **Depends on**: S14-07 (emitExpr and the shared CodegenContext)
- **Blocks**: S14-11 (driver calls `jvmCodegen`)

## Goals

1. Complete `stdlib/kestrel/compiler/codegen.ks` by adding:
   - `emitFunDecl(ctx, decl: FunDecl): Unit`
   - Tail-call loop transformation helpers
   - Async `emitAsyncFun` that wraps in `KTask.andThen`
   - ADT constructor class emitter
   - `emitExternFun(ctx, decl: ExternFunDecl): Unit`
   - `emitVal`, `emitVar` top-level initialisation
   - `emitException(ctx, decl: ExceptionDecl): Unit`
   - `jvmCodegen(prog: Program, typedNodes: TypeAnnotations, meta: CodegenMeta): JvmCodegenResult`
   - `JvmCodegenResult` record: `{ classes: Dict<String, ByteArray> }`

## Acceptance Criteria

- `stdlib/kestrel/compiler/codegen.ks` (both halves combined) compiles without errors.
- Integration test: compile a Kestrel program with a recursive function through the self-hosted
  codegen and confirm the tail-call loop replaces recursion (verify with `javap -c` output).
- A test file `stdlib/kestrel/compiler/codegen-decl.test.ks` covers:
  - A `fun` declaration producing a static method
  - A tail-recursive function emits a GOTO loop (no stack overflow on deep recursion)
  - An async `fun` compiles without error
  - An ADT constructor class is emitted for a simple type
- `./kestrel test stdlib/kestrel/compiler/codegen-decl.test.ks` passes.
- `cd compiler && npm test` still passes.

## Spec References

- `compiler/src/jvm-codegen/codegen.ts` (lines ~1 800–3 640)
- `docs/specs/01-language.md` — function declarations and tail-call spec
- JVM spec §4 (class-file structure for inner classes)

## Risks / Notes

- Mutual-tail-call state machines allocate extra local slots; the slot accounting must be
  identical to the TypeScript compiler so bootstrap-produced bytecode matches.
- Async transformation generates deeply nested lambdas; the KTask.andThen pattern must use
  the same KFunction wrapping the TypeScript compiler emits.
- ADT constructors generate inner classes whose names contain `$`; confirm the classfile writer
  correctly handles `$` in class and method names.
- `extern fun` dispatch has several sub-cases (static call, instance call, field load,
  constructor); each must be covered by unit tests before the story closes.
