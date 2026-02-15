# Add runtime conformance tests

## Description

IMPLEMENTATION_PLAN Testing Summary: `tests/conformance/runtime/` for VM behaviour verification. The plan references runtime scenarios (e.g. bytecode that throws and catches, GC stress). Currently conformance has parse/ and typecheck/ only; no runtime/ folder.

## Acceptance Criteria

- [ ] Create `tests/conformance/runtime/` layout
- [ ] Add scenarios for: exception throw/catch, GC stress, async/await (when supported)
- [ ] Integrate into test harness (test-all.sh or run-e2e) so runtime conformance runs
- [ ] Per spec 08: runtime conformance validates VM behaviour per 05
