# Single-file happy-path compilation in driver

## Sequence: S17-01
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-02, S17-03, S17-04, S17-05, S17-06, S17-07, S17-08, S17-09, S17-10, S17-11, S17-12, S17-13

## Summary

Implement the core single-file compilation pipeline in `Driver.compileFile` so that reading,
lexing, parsing, typechecking (no imports), running `jvmCodegen`, and writing `.class` files to
`outDir` all work end-to-end. `compileFile` returns `ok=True` for valid source. No KTI, no
incremental, no dependency resolution yet.

## Current State

`stdlib/kestrel/tools/compiler/driver.ks` contains a stub `compileFile` that only validates
that `entryPath` is non-empty and returns `ok=True`. No actual lexing, parsing, typechecking,
or code generation is performed.

The individual pieces needed:
- `kestrel:dev/parser/lexer` — `lex` function
- `kestrel:dev/parser/parser` — `parseFromList`
- `kestrel:dev/typecheck/typecheck` — `typecheck` function
- `kestrel:tools/compiler/codegen` — `jvmCodegen`
- `kestrel:io/fs` — `readFile`, `writeBytes`, `mkdir`

## Relationship to other stories

- **Blocks**: S17-02 (adds error propagation to the pipeline), S17-03 (adds KTI write)
- **No dependencies**: This is the first story in the epic.

## Goals

1. Read source text from `entryPath` using `Fs.readFile`.
2. Lex the source using `Lex.lex`.
3. Parse the token list using `parseFromList` — if parse fails, return `ok=False` (diagnostic
   surface added in S17-02; for now a placeholder diagnostics list is acceptable).
4. Typecheck the parsed program with no import bindings using `typecheck`.
5. Run `jvmCodegen` on the typed program to produce class-file byte arrays.
6. Write each `.class` file to `outDir` using `Fs.writeBytes` (creating `outDir` with `Fs.mkdir`
   if needed).
7. `compileFile` returns `{ ok = True, diagnostics = [] }` on success.

## Acceptance Criteria

- [ ] `Driver.compileFile` successfully compiles a single-file Kestrel program with no imports.
- [ ] `.class` files are written to the directory specified by `opts.outDir`.
- [ ] `compileFile` returns `ok=True` for valid source.
- [ ] `compileFile` returns `ok=False` when source cannot be parsed (even without full diagnostics).
- [ ] `stdlib/kestrel/tools/compiler/driver.test.ks` has a test verifying the happy-path.
- [ ] `cd compiler && npm run build && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — incremental compilation and KTI freshness
- `docs/specs/11-bootstrap.md` — self-hosted compiler pipeline

## Risks / Notes

- `typecheck` requires a `DependencyExportSnapshot` (import bindings from dependencies); pass an
  empty map for the no-imports case.
- `jvmCodegen` returns a list of `(className, bytes)` pairs; iterate and write each.
- `outDir` may not exist yet; use `Fs.mkdir` with recursive flag if available, or create
  parent directories step by step.
- The `Fs.writeBytes` function must accept a `List<Int>` (bytes); verify the signature matches
  what `jvmCodegen` produces.
