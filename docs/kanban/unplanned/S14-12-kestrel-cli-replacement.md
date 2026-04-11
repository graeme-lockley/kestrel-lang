# Kestrel CLI Replacement

## Sequence: S14-12
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-03, S14-04, S14-05, S14-06, S14-07, S14-08, S14-09, S14-10, S14-11, S14-13, S14-14

## Summary

Replace the Bash `scripts/kestrel` shim CLI (which currently shells out to Node.js to run
`compiler/cli.ts`) with a Kestrel-written CLI that invokes the self-hosted compiler driver
(S14-11). The new CLI is itself a Kestrel program compiled by the self-hosted compiler,
completing the self-hosting loop for the entry point.

Covers porting `compiler/cli.ts` (~size varies) to a Kestrel CLI program, and updating
`scripts/kestrel` to invoke the compiled Kestrel CLI binary instead of the TypeScript compiler.

## Current State

`scripts/kestrel` is a Bash script that:
1. Checks for `compiler/dist/cli.js` (the TypeScript-compiled CLI).
2. Falls back to `npx ts-node` if not built.
3. Passes all arguments through to the Node.js CLI.

`compiler/cli.ts` provides sub-commands: `run`, `build`, `dis`, `test`, `fmt`, `lock`.

## Relationship to other stories

- **Depends on**: S14-11 (compiler driver), `kestrel:dev/cli` (argument parsing)
- **Blocks**: S14-13 (bootstrap verification uses the updated CLI to invoke the Kestrel compiler)

## Goals

1. Create `stdlib/kestrel/compiler/cli-main.ks` (or a top-level `compiler-cli.ks`) with:
   - Argument parsing using `kestrel:dev/cli` or a hand-rolled `Args` parser
   - `run <file> [args...]` — compile and execute a Kestrel program
   - `build [file]` — compile to `.class` files (calls `compileFile` from driver)
   - `dis [--verbose|--code-only] <file>` — disassemble bytecode
   - `test [--verbose|--summary] [--clean] [--refresh] [--allow-http] [files...]` — run test suite
   - `fmt [--stdin] [file]` — format a source file (calls formatter from `kestrel:dev/parser`)
   - `lock <lockfile>` — update the URL lockfile
2. Update `scripts/kestrel` to prefer invoking the Kestrel-compiled CLI binary when available,
   falling back to the TypeScript compiler.
3. Update `AGENTS.md` and `docs/guide.md` to reflect the new build topology.

## Acceptance Criteria

- Running `./kestrel build hello.ks` successfully compiles `hello.ks` using the Kestrel CLI.
- Running `./kestrel run hello.ks` executes it and prints `Hello, World!`.
- Running `./kestrel test` runs the full test suite and reports results.
- The TypeScript compiler fallback path still works.
- `cd compiler && npm test` still passes.
- `./scripts/run-e2e.sh` passes.

## Spec References

- `compiler/cli.ts`
- `scripts/kestrel`
- `docs/specs/09-tools.md` — CLI command specification

## Risks / Notes

- The Kestrel CLI is itself compiled by the self-hosted compiler; this creates a chicken-and-egg
  situation for the first build. The bootstrap process (S14-13) must handle building the CLI
  using the TypeScript compiler (Stage 0) before the CLI can build itself.
- `dis` (disassembler) may depend on a separate disassembler module; if not yet ported, stub it
  out and note the dependency.
- The `test` sub-command orchestrates test runner logic currently in `scripts/run_tests.ks`;
  that script should remain as-is and be invoked by the new CLI, not replaced.
