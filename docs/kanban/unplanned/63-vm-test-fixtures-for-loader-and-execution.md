# VM: Test fixtures for loader and execution

## Sequence: 63
## Tier: Subset of VM testing (often folded into sequence 13)
## Former ID: 29

## Summary

Provide minimal, checked-in `.kbc` fixtures (or equivalent) so Zig tests can load bytecode and assert loader behaviour and simple execution without going through the full TypeScript compiler pipeline. This unblocks incremental VM development and fixes broken tests that reference missing files.

## Current State

- `load.zig` (or similar) may reference a path such as `test/fixtures/empty.kbc`; the path and file must exist in-repo for CI.
- Broader opcode and GC tests belong under sequence **13** (VM unit and integration tests); this story is the **smallest slice**: fixtures + loader smoke tests + one execution smoke test.

## Relationship to other stories

- **Sequence 13** (VM unit and integration tests) should subsume most of this work. Treat **62** (this story) as optional if **13** lands first with fixtures included; otherwise implement **62** first as a stepping stone.

## Acceptance Criteria

- [ ] Create a stable directory for VM test fixtures (e.g. `vm/test/fixtures/`) documented in `vm/README` or build files.
- [ ] Add minimal `.kbc`: valid header, single function, body ends with RET (or documented minimal instruction sequence).
- [ ] Add a second fixture: LOAD_CONST + RET (or compiler-generated equivalent) to verify constant load path.
- [ ] Loader test: load each fixture, assert magic, version, and that code section is non-empty where expected.
- [ ] Execution test (optional but ideal): run minimal fixture in a test harness and assert stack/result or exit code.
- [ ] Document how to regenerate fixtures from the compiler if hand-maintained bytes drift.

## Spec References

- 03-bytecode-format (file layout, sections)
- 08-tests §2.4 (bytecode / VM testing expectations)
