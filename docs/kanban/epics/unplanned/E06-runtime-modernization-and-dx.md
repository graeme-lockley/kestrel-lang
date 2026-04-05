# Epic E06: Runtime Modernization and DX

## Status

Unplanned

## Summary

Tracks cleanup and modernization work spanning runtime semantics and developer experience improvements.

## Stories

1. [S06-01-vm-spread-instruction.md](../../unplanned/S06-01-vm-spread-instruction.md) — Verify SPREAD opcode coverage, then close (archival)
2. [S06-04-vm-float-constant-loading-and-arithmetic.md](../../unplanned/S06-04-vm-float-constant-loading-and-arithmetic.md) — Verify JVM float constant/arithmetic, then close (archival)
3. [S06-03-int-64-bit-jvm-native-representation.md](../../unplanned/S06-03-int-64-bit-jvm-native-representation.md) — Migrate Int to 64-bit JVM-native semantics
4. [S06-06-task-race-cancel-losing-tasks-only.md](../../unplanned/S06-06-task-race-cancel-losing-tasks-only.md) — Fix Task.race to only cancel losing tasks, not the winner
5. [S06-07-async-quiescence-timeout.md](../../unplanned/S06-07-async-quiescence-timeout.md) — Add configurable timeout to awaitAsyncQuiescence to prevent silent hangs
6. [S06-08-task-race-empty-list-kestrel-exception.md](../../unplanned/S06-08-task-race-empty-list-kestrel-exception.md) — Raise catchable Kestrel exception for Task.race([])
7. [S06-09-unwrap-failure-cycle-detection.md](../../unplanned/S06-09-unwrap-failure-cycle-detection.md) — Add depth limit to KTask.unwrapFailure to prevent infinite loop
8. [S06-10-async-cancellation-spec.md](../../unplanned/S06-10-async-cancellation-spec.md) — Document async cancellation semantics in specs (Cancelled, Task.cancel, Task.all/race edge cases)
9. [S06-11-async-edge-case-test-coverage.md](../../unplanned/S06-11-async-edge-case-test-coverage.md) — Add cross-module async, concurrent failure, and cancel-propagation tests
10. [S06-02-compact-suite-live-spinner-output.md](../../unplanned/S06-02-compact-suite-live-spinner-output.md) — Live spinner and duration output for test suites

## Dependencies

- S06-03 depends on JVM-only pivot (stories 55-58 done).
- S06-10 should follow S06-06 through S06-09 (spec reflects post-fix behavior).
- S06-11 depends on S06-06 through S06-09 (tests validate the fixes).

## Epic Completion Criteria

- S06-01 is closed as verified (SPREAD covered in E2E/unit tests) or merged with an existing done story.
- S06-04 is verified for JVM float constant and arithmetic correctness and closed.
- S06-03 is done with 64-bit Int semantics fully aligned in runtime, docs, and tests.
- S06-06 through S06-09 are done (async correctness batch: cancel semantics, quiescence timeout, empty-list exception, unwrapFailure depth limit).
- S06-10 is done with cancellation semantics documented in 01-language.md, 02-stdlib.md, and 06-typesystem.md.
- S06-11 is done with tests for cross-module async, concurrent failure, cancel propagation, and Task.race edge cases.
- S06-02 is done with stable test UX behavior across all three output modes.
