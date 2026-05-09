# Fix self-hosted codegen StackMapTable generation

## Sequence: S17-52
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)

## Summary

The self-hosted JVM codegen produces invalid StackMapTable attributes in compiled `.class` files,
causing VerifyError and ClassFormatError when the JVM attempts to load and execute the compiled
bytecode. This blocks all self-hosted runtime validation and must be fixed before any runtime
corpus expansion (S17-51) can proceed.

## Current State

- Self-hosted codegen (`stdlib/kestrel/tools/compiler/codegen.ks`) emits bytecode that fails
  JVM verification during class loading.
- Error patterns: `VerifyError: Expecting a stackmap frame at branch target`, `ClassFormatError: StackMapTable format error`.
- All 17 files in `tests/kconformance/runtime/valid/` fail to execute via `./kestrel-self run`.
- Failures occur in both simple programs (if/while control flow) and complex programs (async, closures).
- TS JVM codegen (`compiler/src/jvm-codegen/codegen.ts`) produces valid bytecode; the bug is
  specific to the self-hosted implementation.

## Relationship to other stories

- Blocks: S17-51 (corpus expansion — depends on valid runtime execution).
- Related: S17-36 (tail-call opt), S17-37 (global init), S17-38 (is/never/options codegen).
  Each of these may reveal or interact with StackMapTable generation issues.

## Goals

1. Identify the root cause of StackMapTable generation defects in the self-hosted codegen.
2. Fix the self-hosted StackMapTable emission to match TS codegen behaviour.
3. Restore `./kestrel-self run` execution to pass-rate parity with `./kestrel run` on the
   same input programs.
4. Verify all 17 runtime conformance files compile and execute successfully.

## Acceptance Criteria

- [ ] All 17 files in `tests/kconformance/runtime/valid/` execute successfully via `./kestrel-self run --clean <file>` with exit code 0.
- [ ] Runtime output matches expected `// =>` golden assertions for each file (if present).
- [ ] `./scripts/test-kestrel.sh` runtime tier exits 0.
- [ ] No new ClassFormatError or VerifyError during JVM class loading for self-hosted compiled code.
- [ ] TS JVM codegen parity maintained: TS and self-hosted produce functionally equivalent bytecode
      for the same input programs.

## Spec References

- `docs/specs/11-bootstrap.md` (bootstrap and runtime artifact expectations).
- `docs/specs/08-tests.md` (runtime conformance execution model).

## Risks / Notes

- StackMapTable is a complex JVM verification requirement; fixes may require careful bytecode
  inspection and comparison between TS and self-hosted emitters.
- The bug may be in stackmap frame computation, branch target tracking, or stackmap attribute
  serialization.
- Some failures may reveal upstream type-inference or codegen logic issues (e.g. incorrect
  branch target calculation due to wrong instruction sizing).
