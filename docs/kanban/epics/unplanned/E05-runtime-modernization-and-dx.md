# Epic E05: Runtime Modernization and DX

## Status

Unplanned

## Summary

Tracks cleanup and modernization work spanning runtime semantics and developer experience improvements.

## Stories

- [S05-01-vm-spread-instruction.md](../../unplanned/S05-01-vm-spread-instruction.md)
- [S05-02-compact-suite-live-spinner-output.md](../../unplanned/S05-02-compact-suite-live-spinner-output.md)
- [S05-03-int-64-bit-jvm-native-representation.md](../../unplanned/S05-03-int-64-bit-jvm-native-representation.md)
- [S05-04-vm-float-constant-loading-and-arithmetic.md](../../unplanned/S05-04-vm-float-constant-loading-and-arithmetic.md)
- [S05-05-vm-test-fixtures-for-loader-and-execution.md](../../unplanned/S05-05-vm-test-fixtures-for-loader-and-execution.md)

## Dependencies

- Story S05-03 depends on JVM-only pivot stories 55-58.

## Epic Completion Criteria

- Story S05-03 is done with 64-bit Int semantics fully aligned in docs/tests/runtime.
- Story S05-02 is done with stable test UX behavior across modes.
- Story S05-01 is either closed as verified or merged into an existing done story with cross-link notes.
- Story S05-04 is verified for JVM float constant and arithmetic correctness.
- Story S05-05 is closed with stable JVM loader/execution fixture coverage.
