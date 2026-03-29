# Add runtime conformance tests


## Sequence: 43
## Former ID: (none)
## Description

IMPLEMENTATION_PLAN Testing Summary: `tests/conformance/runtime/` for VM behaviour verification. The plan references runtime scenarios (e.g. bytecode that throws and catches, GC stress). Currently conformance has parse/ and typecheck/ only; no runtime/ folder.

## Acceptance Criteria

- [x] Create `tests/conformance/runtime/` layout
- [x] Add scenarios for: exception throw/catch, GC stress, async/await (when supported)
- [x] Integrate into test harness (test-all.sh or run-e2e) so runtime conformance runs
- [x] Per spec 08: runtime conformance validates VM behaviour per 05

## Tasks

- [x] Create `tests/conformance/runtime/` with README and `valid/` subdir (spec 08 §2.4, §2.5)
- [x] Add `valid/gc_stress.ks`, `valid/exception_throw_catch.ks`, `valid/async_await.ks`
- [x] Extend `scripts/run-e2e.sh` to run runtime conformance (same // expected stdout convention)
- [x] Verify `scripts/test-all.sh` runs runtime conformance via run-e2e.sh
