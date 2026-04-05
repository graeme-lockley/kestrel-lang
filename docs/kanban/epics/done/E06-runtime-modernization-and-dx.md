# Epic E06: Runtime Modernization and DX

## Status

Done

## Summary

Tracks cleanup and modernization work spanning runtime semantics and developer experience improvements. All stories are complete. The original S06-02 scope (live spinner with in-place TTY update) was revised by joint decision: the spinner was dropped in favour of a simpler, more robust harness that includes `asyncGroup` for async assertions, virtual-thread interrupt-on-cancel for async leak elimination, a two-phase test runner for incremental output streaming, and an async-in-flight diagnostic in `printSummary`.

## Stories

1. [S06-01-vm-spread-instruction.md](../../done/S06-01-vm-spread-instruction.md) ✓ — Verified SPREAD opcode coverage (archival)
2. [S06-04-vm-float-constant-loading-and-arithmetic.md](../../done/S06-04-vm-float-constant-loading-and-arithmetic.md) ✓ — Verified JVM float constant/arithmetic (archival)
3. [S06-03-int-64-bit-jvm-native-representation.md](../../done/S06-03-int-64-bit-jvm-native-representation.md) ✓ — Migrated Int to 64-bit JVM-native semantics
4. [S06-06-task-race-cancel-losing-tasks-only.md](../../done/S06-06-task-race-cancel-losing-tasks-only.md) ✓ — Fixed Task.race to only cancel losing tasks
5. [S06-07-async-quiescence-timeout.md](../../done/S06-07-async-quiescence-timeout.md) ✓ — Configurable quiescence timeout
6. [S06-08-task-race-empty-list-kestrel-exception.md](../../done/S06-08-task-race-empty-list-kestrel-exception.md) ✓ — Catchable Kestrel exception for Task.race([])
7. [S06-09-unwrap-failure-cycle-detection.md](../../done/S06-09-unwrap-failure-cycle-detection.md) ✓ — Depth limit in KTask.unwrapFailure
8. [S06-10-async-cancellation-spec.md](../../done/S06-10-async-cancellation-spec.md) ✓ — Documented async cancellation semantics
9. [S06-11-async-edge-case-test-coverage.md](../../done/S06-11-async-edge-case-test-coverage.md) ✓ — Cross-module async, concurrent failure, cancel-propagation tests
10. [S06-02-compact-suite-live-spinner-output.md](../../done/S06-02-compact-suite-live-spinner-output.md) ✓ — Stable multi-mode test harness with asyncGroup, async leak fixes, and two-phase runner

## Dependencies

- S06-03 depends on JVM-only pivot (stories 55-58 done).
- S06-10 should follow S06-06 through S06-09 (spec reflects post-fix behavior).
- S06-11 depends on S06-06 through S06-09 (tests validate the fixes).

## Epic Completion Criteria

- [x] S06-01 is closed as verified (SPREAD covered in E2E/unit tests).
- [x] S06-04 is verified for JVM float constant and arithmetic correctness.
- [x] S06-03 is done with 64-bit Int semantics fully aligned in runtime, docs, and tests.
- [x] S06-06 through S06-09 are done (async correctness batch: cancel semantics, quiescence timeout, empty-list exception, unwrapFailure depth limit).
- [x] S06-10 is done with cancellation semantics documented in 01-language.md, 02-stdlib.md, and 06-typesystem.md.
- [x] S06-11 is done with tests for cross-module async, concurrent failure, cancel propagation, and Task.race edge cases.
- [x] S06-02 is done: suite-first output in all three modes; `asyncGroup` for async assertions; virtual-thread interrupt-on-cancel eliminates async task leaks; two-phase `exec` runner for incremental output; `printSummary` async-in-flight diagnostic.
