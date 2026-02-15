# VM: Add test fixtures for loader and execution

## Description

IMPLEMENTATION_PLAN Phase 0.3 and 4.1: add hand-crafted or compiler-generated .kbc fixtures under `vm/test/fixtures/` for loader and execution tests. The load.zig test references `test/fixtures/empty.kbc` but no such file exists in the repo.

## Acceptance Criteria

- [ ] Create `vm/test/fixtures/` (or equivalent path used by Zig tests)
- [ ] Add minimal .kbc (e.g. empty.kbc with single RET)
- [ ] Add fixture with LOAD_CONST + RET for constant-load test
- [ ] Loader unit tests load fixtures and assert structure
- [ ] Execution integration test runs fixture and checks result
