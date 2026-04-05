# kestrel:tools/test + kestrel test alias

## Sequence: S08-06
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/unplanned/E08-source-formatter.md)
- Companion stories: S08-01, S08-02, S08-03, S08-04, S08-05, S08-07

## Summary

Move `stdlib/kestrel/test.ks` to `stdlib/kestrel/tools/test.ks` and update `kestrel test` to invoke the tool via `./kestrel run kestrel:tools/test [args...]` rather than running the `scripts/run_tests.ks` script directly. The test harness API (`Suite`, `makeRoot`, `test:expect`, etc.) is unchanged; only the module specifier and the CLI wiring change.

This story also updates `scripts/run_tests.ks` (the runner driver) and the generated test runner to import from `kestrel:tools/test` instead of `kestrel:test`.

## Current State

- `stdlib/kestrel/test.ks` — the test harness library, imported as `kestrel:test` by all test files.
- `scripts/run_tests.ks` — the driver that generates a test runner file; imports `kestrel:test`.
- `scripts/kestrel` `_run_unit_tests()` — runs `run_tests.ks` directly via `cmd_run`-like logic.
- Test files across `stdlib/kestrel/*.test.ks` and `tests/unit/*.test.ks` import `kestrel:test`.

## Relationship to other stories

- **Depends on** S08-01 (namespace restructure) — `test.ks` will import from new `kestrel:data/*` paths.
- **Depends on** S08-02 (module-specifier support for `kestrel run`).
- **Depends on** S08-03 (dev/cli) — `tools/test.ks` uses `Cli.run` with its `CliSpec`.
- **Independent of** S08-04 (prettyprinter) and S08-05 (parser).
- **Precedes** S08-07 (format tool).

## Goals

1. Copy `stdlib/kestrel/test.ks` → `stdlib/kestrel/tools/test.ks`; remove the old flat file.
2. Add a `CliSpec` to `tools/test.ks` and export `main : List<String> -> Task<Int>` using `Cli.run`.
3. Update `scripts/run_tests.ks` to import from `kestrel:tools/test`.
4. Update `scripts/kestrel` `_run_unit_tests()` to use `./kestrel run kestrel:tools/test` instead of the direct runner invocation.
5. Update all `import "kestrel:test"` sites in `stdlib/kestrel/*.test.ks` and `tests/unit/*.test.ks` to `import "kestrel:tools/test"`.
6. `kestrel test` continues to support `--verbose`, `--summary`, `--clean`, `--refresh`, `--allow-http` flags.

## Acceptance Criteria

- `./kestrel run kestrel:tools/test` runs the test suite identically to the current `kestrel test`.
- `./kestrel run kestrel:tools/test --help` prints the auto-generated help from `CliSpec`.
- `kestrel test [--verbose|--summary] [--clean] [--refresh] [--allow-http] [files...]` continues to work.
- All existing test files compile and pass after import path update.
- `cd compiler && npm test` passes.
- `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/02-stdlib.md` — stdlib public API
- `docs/specs/08-tests.md` — test harness documentation
- `docs/specs/09-tools.md` — `kestrel test` CLI reference

## Risks / Notes

- The current `_run_unit_tests()` is ~40 lines of bash with two compile phases (generate runner, run runner). After this story it should become a thin wrapper calling `cmd_run_module "kestrel:tools/test"`. Ensure the `--generate` flag (used to produce the `.kestrel_test_runner.ks` output) still works.
- Generated test runner files (`scripts/run_tests.ks`) import `kestrel:test`; these must be updated.
- The `asyncTasksInFlight` import from `kestrel:task`/`kestrel:sys/task` in `test.ks` must be updated too (covered by S08-01, but confirm).
