# Simplify bash cmd_test to match cmd_fmt

## Sequence: S11-04
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E11 Pure-Kestrel Test Runner](../epics/unplanned/E11-pure-kestrel-test-runner.md)

## Summary

Replace `_run_unit_tests()` and the current `cmd_test()` implementation in `scripts/kestrel` with a three-line form identical in structure to `cmd_fmt()`: `ensure_tools`, a compiler-build check, and `KESTREL_BIN="$ROOT/kestrel" exec "$ROOT/kestrel" run "kestrel:tools/test-runner" "$@"`. The `_run_unit_tests` function is deleted entirely.

## Current State

`cmd_test` calls `ensure_tools`, `build_compiler_jvm` if needed, then delegates to `_run_unit_tests`. `_run_unit_tests` has ~50 lines of bash that separate compiler flags from runner args, compile the runner module manually, and launch it via raw `java -cp … MainClass "" "" "$ROOT" …`. `cmd_fmt` is three lines by contrast.

## Relationship to other stories

- Depends on **S11-03** (new test-runner.ks must be in place first).
- Terminal story in the epic.

## Goals

1. `_run_unit_tests` is removed from `scripts/kestrel`.
2. `cmd_test` is three lines: `ensure_tools`, build check, `exec`.
3. `KESTREL_BIN` env var is set before `exec` so `test-runner.ks` can find the binary.
4. All existing flags (`--verbose`, `--summary`, `--generate`, `--clean`, `--refresh`, `--allow-http`) pass through `"$@"` to `test-runner.ks`.

## Acceptance Criteria

- `./kestrel test` passes the full test suite.
- `./kestrel test --verbose` and `./kestrel test --summary` work.
- `cmd_test` in `scripts/kestrel` has exactly the structure described above.
- `_run_unit_tests` is not present anywhere in `scripts/kestrel`.
- Benchmark: wall-clock time on a warm cache is recorded in Build notes.

## Spec References

- `docs/specs/09-tools.md`

## Risks / Notes

- All compiler flags (`--clean`, `--refresh`, `--allow-http`) are now passed directly to `./kestrel run`, which handles them in `cmd_run`. `test-runner.ks` reads them from `proc.args` and re-passes them to the inner subprocess.
