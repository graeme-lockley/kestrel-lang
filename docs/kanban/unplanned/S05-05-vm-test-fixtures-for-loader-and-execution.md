# JVM: Test fixtures for loader and execution

## Sequence: S05-05
## Tier: Subset of runtime testing (often folded into sequence 13)
## Former ID: 29

## Epic

- Epic: [E05 Runtime Modernization and DX](../epics/unplanned/E05-runtime-modernization-and-dx.md)
- Companion stories: S05-01, S05-04

## Summary

Provide minimal, checked-in `.kbc` fixtures (or equivalent) so JVM runtime tests can load bytecode and assert loader behaviour and simple execution without going through the full TypeScript compiler pipeline. This unblocks incremental JVM runtime development and fixes broken tests that reference missing files.

## Current State

- The JVM runtime loader may reference a path such as `test/fixtures/empty.kbc`; the path and file must exist in-repo for CI.
- Broader opcode and execution tests belong under sequence **13** (runtime unit and integration tests); this story is the **smallest slice**: fixtures + loader smoke tests + one execution smoke test.

## Relationship to other stories

- **Sequence 13** (runtime unit and integration tests) should subsume most of this work. Treat **66** (this story) as optional if **13** lands first with fixtures included; otherwise implement **66** first as a stepping stone.

## Acceptance Criteria

- [ ] Create a stable directory for JVM runtime test fixtures (e.g. `runtime/jvm/test/fixtures/`) documented in build files.
- [ ] Add minimal `.kbc`: valid header, single function, body ends with RET (or documented minimal instruction sequence).
- [ ] Add a second fixture: LOAD_CONST + RET (or compiler-generated equivalent) to verify constant load path.
- [ ] Loader test: load each fixture, assert magic, version, and that code section is non-empty where expected.
- [ ] Execution test (optional but ideal): run minimal fixture in a test harness and assert stack/result or exit code.
- [ ] Document how to regenerate fixtures from the compiler if hand-maintained bytes drift.

## Spec References

- 03-bytecode-format (file layout, sections)
- 08-tests §2.4 (bytecode / runtime testing expectations)
