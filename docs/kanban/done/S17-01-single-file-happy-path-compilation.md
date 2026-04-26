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

- [x] `Driver.compileFile` successfully compiles a single-file Kestrel program with no imports.
- [x] `.class` files are written to the directory specified by `opts.outDir`.
- [x] `compileFile` returns `ok=True` for valid source.
- [x] `compileFile` returns `ok=False` when source cannot be parsed (even without full diagnostics).
- [x] `stdlib/kestrel/tools/compiler/driver.test.ks` has a test verifying the happy-path.
- [x] `cd compiler && npm run build && npm test` passes.
- [x] `./scripts/kestrel test` passes.

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

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib driver | Replace stub `compileFile` in `stdlib/kestrel/tools/compiler/driver.ks` with real lex→parse→typecheck→codegen→write pipeline. Add `classNameForPath` helper. |
| Stdlib imports | Add imports for `Lex`, `Par`, `TC` (typecheck), `Codegen`, `Fs`, `Char`, `Dict`, `Lst`, `Str` in driver.ks. |
| Kestrel tests | Extend `driver.test.ks` with a happy-path test that compiles a minimal single-file program and verifies `ok=True`. |
| Spec refs | No spec change; this implements what was already described. |

## Tasks

- [x] Add imports to `driver.ks`: `Lex`, `Par` (parser), `TC` (typecheck), `Codegen` (jvmCodegen), `Fs`, `Char`, `Dict`, `Lst`, `Str`
- [x] Implement `classNameForPath(path: String): String` in `driver.ks` (matches `classNameForPath` in TS compiler)
- [x] Rewrite `compileFile` to: read source with `Fs.readText`; lex with `Lex.lex`; parse with `Par.parseFromList`; typecheck with `TC.typecheck`; codegen with `Codegen.jvmCodegen`; write classes with `Fs.writeBytes` after `Fs.mkdirAll`
- [x] Handle parse failure: return `{ ok = False, diagnostics = [] }` when parse returns `Err`
- [x] Handle file-read failure: return `{ ok = False, diagnostics = [diag(...readError...)] }`
- [x] Handle typecheck failure: return `{ ok = False, diagnostics = [] }` when `tc.ok = False` (full diagnostic surface in S17-02)
- [x] Add happy-path test in `driver.test.ks`: compile a valid single-file program, assert `ok=True`
- [x] Add failure test: compile a parse-invalid program, assert `ok=False`
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/tools/compiler/driver.test.ks` | Happy path: `compileFile` on `"export fun id(x: Int): Int = x"` → `ok=True` |
| Kestrel harness | `stdlib/kestrel/tools/compiler/driver.test.ks` | Failure path: `compileFile` on unparseable source → `ok=False` |

## Documentation and specs to update

- [x] `docs/specs/11-bootstrap.md` — no change needed for this story; mark reviewed

## Build notes

- 2026-04-26: Started implementation. Exploring `driver.ks` stub, codegen API, FS API, typecheck API before writing code.
- 2026-04-26: Implemented `classNameForPath` using `Str.mapChars` + `Chr.isAlphaNum`, mirroring the TS compiler logic.
- 2026-04-26: Implemented `writeAllClasses` as a recursive async helper; needed to bind recursive calls to typed variables before `await` to avoid type inference failures (pattern from `listDirAllLoop` in fs.ks).
- 2026-04-26: `writeAllClasses` also needed to call `Fs.mkdirAll` for each class file's parent directory since class names include path segments.
- 2026-04-26: Tests updated to use `asyncGroup` from `kestrel:dev/test`; source and output dirs kept separate to avoid path collisions.
- 2026-04-26: All 17 driver tests pass; 1867 total Kestrel tests pass; 440 TypeScript tests pass.
