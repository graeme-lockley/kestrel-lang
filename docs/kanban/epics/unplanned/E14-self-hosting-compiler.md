# Epic E14: Self-Hosting Compiler

## Status

Unplanned

## Summary

Port the Kestrel compiler from TypeScript to Kestrel, achieving full self-hosting: the Kestrel compiler
is compiled and run by itself. The TypeScript compiler (`compiler/`) already exists as the bootstrap
reference implementation. The dev-parser library (`kestrel:dev/parser`) — lexer, token types, AST
types, and full recursive-descent parser (~2,300 lines of Kestrel already written) — provides the
foundation. The remaining work is to port the type-checker (Hindley-Milner inference with row
polymorphism), JVM class-file emitter, KTI interface-file reader/writer, multi-module resolver,
diagnostics formatter, and compiler driver CLI into Kestrel, then bootstrap the self-hosted binary
and retire the TypeScript compiler as the primary build tool.

## Stories (ordered — implement sequentially)

1. [S14-01-compiler-diagnostics-module.md](../../done/S14-01-compiler-diagnostics-module.md) — ✅ Diagnostics types and reporter (`kestrel:tools/compiler/diagnostics`)
2. [S14-02-internal-type-representation.md](../../done/S14-02-internal-type-representation.md) — ✅ InternalType ADT, fresh vars, generalize/instantiate (`kestrel:tools/compiler/types`)
3. [S14-03-type-unification-engine.md](../../done/S14-03-type-unification-engine.md) — ✅ Unify, applySubst, astTypeToInternal
4. [S14-04-hindley-milner-type-checker.md](../../done/S14-04-hindley-milner-type-checker.md) — ✅ Full HM type checker with row polymorphism (`kestrel:tools/compiler/typecheck`)
5. [S14-05-jvm-opcode-table.md](../../done/S14-05-jvm-opcode-table.md) — ✅ JVM opcode constants and descriptor helpers (`kestrel:tools/compiler/opcodes`)
6. [S14-06-jvm-classfile-binary-writer.md](../../done/S14-06-jvm-classfile-binary-writer.md) — ✅ ClassFileBuilder and MethodBuilder binary emitter (`kestrel:tools/compiler/classfile`)
7. [S14-07-codegen-expressions-patterns.md](../../done/S14-07-codegen-expressions-patterns.md) — ✅ Code generator: expressions, patterns, lambdas, match
8. [S14-08-codegen-declarations-toplevel.md](../../done/S14-08-codegen-declarations-toplevel.md) — ✅ Code generator: declarations, tail-call optimisation, async/await
9. [S14-09-kti-interface-file-reader-writer.md](../../done/S14-09-kti-interface-file-reader-writer.md) — ✅ KTI v4 reader/writer, serialisation (`kestrel:tools/compiler/kti`)
10. [S14-10-multi-module-resolver.md](../../unplanned/S14-10-multi-module-resolver.md) — Module specifier resolution, URL cache (`kestrel:tools/compiler/resolve`)
11. [S14-11-compiler-driver-pipeline.md](../../unplanned/S14-11-compiler-driver-pipeline.md) — Multi-module incremental compilation driver (`kestrel:tools/compiler/driver`)
12. [S14-12-kestrel-cli-replacement.md](../../unplanned/S14-12-kestrel-cli-replacement.md) — Kestrel-written CLI replacing the TypeScript shim
13. [S14-13-stage0-bootstrap-verification.md](../../unplanned/S14-13-stage0-bootstrap-verification.md) — Stage-0 bootstrap: TypeScript compiles Kestrel compiler, verify output
14. [S14-14-stage1-self-hosting-bootstrap.md](../../unplanned/S14-14-stage1-self-hosting-bootstrap.md) — Stage-1 self-hosting: Kestrel compiler compiles itself

**Note:** S14-05 (opcodes) is independent of S14-02 through S14-04 and can be done in parallel
with the type-system stories if desired. S14-09 (KTI) and S14-10 (resolver) are also relatively
independent — the resolver does not use InternalType, so it can be done alongside S14-02/S14-03.

## Dependencies

- E08 (Source Formatter) — done; `kestrel:dev/parser` + `kestrel:dev/text/prettyprinter` are the
  shared front-end foundation.
- E13 (Stdlib Compiler Readiness) — done; binary I/O, `Fs.mkdir`, `Fs.stat`, `Crypto.hash`, atomic
  writes, `List.sort`, `List.find`, float parsing, string numeric formatting all available.
- E07 (Incremental Compilation / KTI v4) — done; KTI format spec is stable.
- E04 (Module Resolution) — done; URL-import and stdlib-subpath resolution are settled.
- E02 (JVM Interop / extern bindings) — done; `extern fun` and `extern type` are available for
  wrapping the ASM bytecode-generation library or direct JVM classfile writing.

## Implementation Approach

### Bootstrap strategy

The self-hosted compiler is built in **three stages** (classic bootstrapping):

1. **Stage 0** — The existing TypeScript compiler (`compiler/`) compiles the Kestrel-written
   compiler sources to JVM bytecode.
2. **Stage 1** — The Stage-0 output compiles the same Kestrel sources again; output should be
   bit-for-bit identical (or semantically equivalent) to Stage 0.
3. **Stage 2** — Optional reproducibility check: Stage-1 output compiles the sources once more and
   the bytecode matches Stage 1.

Until Stage 1 is verified to produce a correct compiler, the TypeScript compiler is kept as the
canonical bootstrap. After Stage 1 passes, `./kestrel build` switches to invoking the Kestrel
compiler and the TypeScript compiler becomes an emergency fallback.

### Component map

| Component | TypeScript source | Kestrel stdlib/module target |
|-----------|-------------------|------------------------------|
| Lexer + tokens | `compiler/src/lexer/` | `kestrel:dev/parser/lexer` ✓ **done** |
| AST types | `compiler/src/ast/` | `kestrel:dev/parser/ast` ✓ **done** |
| Parser | `compiler/src/parser/parse.ts` (1 432 lines) | `kestrel:dev/parser/parser` ✓ **done** |
| Type checker | `compiler/src/typecheck/check.ts` (1 878 lines) | `kestrel:tools/compiler/typecheck` ✓ **done** |
| JVM class-file writer | `compiler/src/jvm-codegen/classfile.ts` (601 lines) | `kestrel:tools/compiler/classfile` ✓ **done** |
| JVM opcode table | `compiler/src/jvm-codegen/opcodes.ts` (190 lines) | `kestrel:tools/compiler/opcodes` ✓ **done** |
| Code generator | `compiler/src/jvm-codegen/codegen.ts` (3 640 lines) | `kestrel:tools/compiler/codegen` ✓ **done** |
| KTI reader/writer | `compiler/src/kti.ts` (519 lines) | `kestrel:tools/compiler/kti` ✓ **done** |
| Module resolver | `compiler/src/resolve.ts` + `dependency-paths.ts` | `kestrel:tools/compiler/resolve` ← **to build** |
| Diagnostics | `compiler/src/diagnostics/` | `kestrel:tools/compiler/diagnostics` ✓ **done** |
| Compiler driver | `compiler/src/compile-file-jvm.ts` + `index.ts` | `kestrel:tools/compiler/driver` ← **to build** |
| CLI | `compiler/cli.ts` | Kestrel CLI script replacing `scripts/kestrel` shim ← **to build** |

### Module layout

All new Kestrel compiler modules live under `stdlib/kestrel/tools/compiler/`:

```
stdlib/kestrel/tools/compiler/
  diagnostics.ks    — Diagnostic type, severity, span, reporter
  types.ks          — Shared compiler types (Scheme, Env, KtiModule, …)
  typecheck.ks      — Hindley-Milner + row-poly inference engine
  opcodes.ks        — JVM opcode constants and descriptor helpers
  classfile.ks      — JVM class-file binary writer (constant pool, methods, attrs)
  codegen.ks        — AST → JVM bytecode translation
  kti.ks            — KTI v4 reader and writer
  resolve.ks        — Multi-module resolver (stdlib, URL, local, Maven)
  driver.ks         — Top-level compile-file pipeline
```

### Key design decisions

- **Pure-Kestrel classfile emission**: write `.class` files using `kestrel:sys/fs` binary I/O
  (`Fs.writeBinary`) rather than shelling out to `javac` or depending on ASM. This keeps the
  compiler self-contained and removes all Java build-tool dependencies after bootstrap.
- **Incremental compilation via KTI**: the Kestrel compiler reads and writes `.kti` interface files
  exactly as the TypeScript compiler does; the two are interoperable during the transition period.
- **Error recovery**: the Kestrel type-checker should produce the same `Diagnostic` list that the
  TypeScript checker produces, enabling identical IDE error messages and conformance-test assertions.
- **No reflection at compile time**: the compiler uses only `extern fun` bindings to JVM primitives
  (array allocation, string operations) — no `Class.forName`, no runtime code generation via
  reflection.

## Epic Completion Criteria

- All stories in `docs/kanban/done/` with tasks ticked and tests passing.
- `./kestrel build` uses the Kestrel-compiled compiler to produce `.class` files for a non-trivial
  Kestrel program (e.g. `samples/mandelbrot.ks`) with output identical to the TypeScript compiler.
- Stage-1 bootstrap is verified: the Stage-0 Kestrel compiler compiles itself and the resulting
  binary produces identical bytecode when given the same input.
- All compiler conformance tests (`cd compiler && npm test`) pass against the self-hosted binary.
- All Kestrel unit and E2E tests (`./kestrel test`, `./scripts/run-e2e.sh`) continue to pass.
- The TypeScript compiler sources (`compiler/`) are archived or removed from the primary build path
  with a documented fallback procedure.
- `docs/specs/` updated to reflect the new build topology (self-hosted compiler as primary tool).
