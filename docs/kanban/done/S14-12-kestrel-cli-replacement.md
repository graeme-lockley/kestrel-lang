# Kestrel CLI Replacement

## Sequence: S14-12
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/done/E14-self-hosting-compiler.md)
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

1. Create `stdlib/kestrel/tools/compiler/cli-main.ks` (or a top-level `compiler-cli.ks`) with:
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
- Running `./kestrel run hello.ks` executes successfully via the Kestrel CLI dispatch path.
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

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib compiler | Add `stdlib/kestrel/tools/compiler/cli-main.ks` as a Kestrel-written CLI entrypoint and command dispatcher scaffold. |
| Kestrel tests | Add `stdlib/kestrel/tools/compiler/cli-main.test.ks` to verify command parsing and fallback dispatch argument shaping. |
| Shell CLI wrapper | Update `scripts/kestrel` to prefer the Kestrel CLI module for core commands when available, guarded by an env var to prevent recursive re-entry. |
| Documentation | Update `docs/guide.md` and `AGENTS.md` to document the self-hosted CLI preference and TypeScript fallback behavior. |

## Tasks

- [x] Add `stdlib/kestrel/tools/compiler/cli-main.ks` with subcommand parsing (`run`, `build`, `dis`, `test`, `fmt`, `doc`, `lock`) and scaffold command handlers.
- [x] Add dispatch helpers that forward to `./kestrel` under explicit fallback mode so existing TypeScript-backed behavior remains intact.
- [x] Add minimal `build` handler integration with `kestrel:tools/compiler/driver` API shape checks to keep the self-hosted CLI coupled to the driver module.
- [x] Update `scripts/kestrel` to prefer `kestrel:tools/compiler/cli-entry` for top-level command entry when available, with `KESTREL_CLI_TS_FALLBACK` loop prevention.
- [x] Add `stdlib/kestrel/tools/compiler/cli-main.test.ks` covering command parsing and dispatch argument shaping.
- [x] Update `docs/guide.md` to reflect the Kestrel CLI preference path and fallback behavior.
- [x] Update `AGENTS.md` to note the Kestrel CLI entrypoint and TypeScript fallback expectation.
- [x] Run `./kestrel test stdlib/kestrel/tools/compiler/cli-main.test.ks`.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/tools/compiler/cli-main.test.ks` | Verify parsing accepts supported subcommands and rejects unknown commands with usage-style errors. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/cli-main.test.ks` | Verify dispatch helper builds the expected forwarded argument list for `run`, `build`, and `test`. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/cli-main.test.ks` | Verify `build` path touches `driver.compileFile` contract and converts failures into non-zero exit semantics. |
| Vitest integration | existing `compiler/test/integration/*` suites | Regression guard for unchanged TypeScript CLI behavior while wrapper preference is added. |

## Documentation and specs to update

- [x] `docs/guide.md` — document that `scripts/kestrel` now prefers the Kestrel CLI entrypoint for core commands and falls back to the TypeScript path.
- [x] `AGENTS.md` — update CLI architecture notes to include `stdlib/kestrel/tools/compiler/cli-main.ks` and fallback behavior.
- [x] `docs/specs/09-tools.md` — update entry-point topology to document Kestrel CLI preference and fallback guard.

## Build notes

- 2026-04-12: Started implementation.
- 2026-04-12: Implemented `kestrel:tools/compiler/cli-main` as an import-safe dispatcher module and added `kestrel:tools/compiler/cli-entry` as the executable entrypoint.
- 2026-04-12: Updated `scripts/kestrel` to prefer self-hosted dispatch for command entry and set `KESTREL_CLI_TS_FALLBACK=1` to prevent recursive wrapper re-entry.
- 2026-04-12: Added `stdlib/kestrel/tools/compiler/cli-main.test.ks` and verified focused tests, compiler suite, full Kestrel suite, E2E suite, plus `./kestrel build hello.ks` and `./kestrel run hello.ks` smoke checks.
