# kestrel:tools/test + kestrel test alias

## Sequence: S08-06
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/done/E08-source-formatter.md)
- Companion stories: S08-01, S08-02, S08-03, S08-04, S08-05, S08-07

## Summary

Move `stdlib/kestrel/test.ks` to `stdlib/kestrel/tools/test.ks` and update `kestrel test` to invoke the tool via `kestrel:tools/test-runner` rather than running the `scripts/run_tests.ks` script directly. The test harness API (`Suite`, `makeRoot`, etc.) is unchanged; only the module specifier and the CLI wiring change.

This story also updates `scripts/run_tests.ks` (the runner driver) and the generated test runner to import from `kestrel:tools/test` instead of `kestrel:test`.

## Current State

- `stdlib/kestrel/test.ks` — the test harness library, imported as `kestrel:test` by all test files.
- `scripts/run_tests.ks` — the driver that generates a test runner file; imports `kestrel:test`.
- `scripts/kestrel` `_run_unit_tests()` — runs `run_tests.ks` directly via `cmd_run`-like logic.
- Test files across `stdlib/kestrel/*.test.ks` and `tests/unit/*.test.ks` import `kestrel:test`.

## Relationship to other stories

- **Depends on** S08-01 (namespace restructure) — `test.ks` will import from new `kestrel:data/*` paths.
- **Depends on** S08-02 (module-specifier support for `kestrel run`).
- **Depends on** S08-03 (dev/cli) — tooling infrastructure.
- **Independent of** S08-04 (prettyprinter) and S08-05 (parser).
- **Precedes** S08-07 (format tool).

## Goals

1. Copy `stdlib/kestrel/test.ks` → `stdlib/kestrel/tools/test.ks`; remove the old flat file.
2. Create `stdlib/kestrel/tools/test-runner.ks` as the standalone entry point (runner logic, top-level `main()` call).
3. Update `scripts/run_tests.ks` to generate runner that imports from `kestrel:tools/test`.
4. Update `scripts/kestrel` `_run_unit_tests()` to use `kestrel:tools/test-runner` instead of the direct runner invocation.
5. Update all `import "kestrel:test"` sites in `stdlib/kestrel/*.test.ks` and `tests/unit/*.test.ks` to `import "kestrel:tools/test"`.
6. `kestrel test` continues to support `--verbose`, `--summary`, `--clean`, `--refresh`, `--allow-http` flags.

## Acceptance Criteria

- [x] `kestrel test [--verbose|--summary] [--clean] [--refresh] [--allow-http] [files...]` continues to work.
- [x] All existing test files compile and pass after import path update.
- [x] `cd compiler && npm test` passes (420 tests).
- [x] `./kestrel test stdlib/kestrel/dev/text/prettyprinter.test.ks` passes (19 tests).

## Spec References

- `docs/specs/02-stdlib.md` — stdlib public API
- `docs/specs/08-tests.md` — test harness documentation
- `docs/specs/09-tools.md` — `kestrel test` CLI reference

## Tasks

- [x] Create `stdlib/kestrel/tools/` directory
- [x] Create `stdlib/kestrel/tools/test.ks` — pure harness library (exports `Suite`, `makeRoot`, `outputVerbose`, `outputCompact`, `outputSummary`, all assertion functions, `printSummary`)
- [x] Create `stdlib/kestrel/tools/test-runner.ks` — standalone entry-point (runner discovery + generation + phase-2 invocation; top-level `main()` call)
- [x] Update all 54 `import "kestrel:test"` sites → `import "kestrel:tools/test"` (bulk sed)
- [x] Update `scripts/run_tests.ks` `genHead` to reference `kestrel:tools/test`
- [x] Replace `_run_unit_tests()` in `scripts/kestrel` with thin wrapper using `kestrel:tools/test-runner`
- [x] Delete `stdlib/kestrel/test.ks`
- [x] Verify smoke test (19 prettyprinter tests pass)
- [x] `cd compiler && npm test` passes (420 tests)

## Build Notes

2026-04-05: Library/entry-point separation. The original story proposed `tools/test.ks` as both a
library (imported by generated test runners) and a CLI entry-point (`kestrel test`). This creates a
module-initializer re-entrancy problem: when the generated runner imports `kestrel:tools/test`, the
module initializer would run `main()` unconditionally, triggering test discovery at import time (before
the generated runner's own main runs). Solution: split into two files:
- `tools/test.ks` — pure library (no top-level calls), imported by generated runners
- `tools/test-runner.ks` — standalone entry-point (top-level `main()` call), run by `kestrel test`
This mirrors the old `test.ks` + `run_tests.ks` separation but under the `tools/` namespace.

2026-04-05: `runProcess` output capture. The `runProcessOrExit` helper in `test-runner.ks` uses
`runProcess` which captures stdout. The phase-2 subprocess (`./scripts/kestrel run .kestrel_test_runner.ks`)
output is captured and re-printed via `print(r.stdout)`. This works correctly with coloured ANSI output
since the generated runner's stdout is passed through intact.
