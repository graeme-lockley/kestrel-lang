# Epic E06: Runtime Modernization and DX

## Status

Unplanned

## Summary

Tracks cleanup and modernization work spanning runtime semantics and developer experience improvements.

## Stories

- [S06-01-vm-spread-instruction.md](../../unplanned/S06-01-vm-spread-instruction.md)
- [S06-02-compact-suite-live-spinner-output.md](../../unplanned/S06-02-compact-suite-live-spinner-output.md)
- [S06-03-int-64-bit-jvm-native-representation.md](../../unplanned/S06-03-int-64-bit-jvm-native-representation.md)
- [S06-04-vm-float-constant-loading-and-arithmetic.md](../../unplanned/S06-04-vm-float-constant-loading-and-arithmetic.md)
- [S06-05-vm-test-fixtures-for-loader-and-execution.md](../../unplanned/S06-05-vm-test-fixtures-for-loader-and-execution.md)

## Dependencies

- Story S06-03 depends on JVM-only pivot stories 55-58.

## Epic Completion Criteria

- Story S06-03 is done with 64-bit Int semantics fully aligned in docs/tests/runtime.
- Story S06-02 is done with stable test UX behavior across modes.
- Story S06-01 is either closed as verified or merged into an existing done story with cross-link notes.
- Story S06-04 is verified for JVM float constant and arithmetic correctness.
- Story S06-05 is closed with stable JVM loader/execution fixture coverage.
