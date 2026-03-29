# Implementation plan: Audit and update checkboxes


## Sequence: 39
## Former ID: (none)
## Description

The IMPLEMENTATION_PLAN.md deliverables use [ ] and [x] checkboxes. Some are stale: e.g. Phase 2.5 shows [ ] but the type checker is implemented; Phase 4.6 shows [ ] for CALL/record/ADT/GC/exceptions but most are implemented. Audit the plan against the actual codebase and update checkboxes to reflect current state.

## Acceptance Criteria

- [x] Phase 0.5: Tick [x] for compiler build/test, vm build/test, test-all.sh (all exist and work)
- [x] Phase 2.5: Tick [x] if type checker unit/integration/conformance are done; otherwise create story for gaps
- [x] Phase 3.6: Confirm import table emission [x]; resolution [ ] — correct
- [x] Phase 4.6: Tick [x] for CALL, record, ADT, GC, exceptions, async (VM has these); add note for SPREAD [ ] and Float [ ]
- [x] Phase 5.9: Confirm stdlib layout [x]; full implementation [ ] — correct
- [x] Add explicit "Remaining gaps" section listing: SPREAD, Float, import resolution, VM linking, stdlib implementations
