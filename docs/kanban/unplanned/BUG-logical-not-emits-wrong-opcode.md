# BUG Logical NOT operator returns operand unchanged

## Description

The logical NOT operator (`!`) returns the operand unchanged instead of negating it. For example:
- `!True` outputs `true` (should be `false`)
- `!False` outputs `false` (should be `true`)
- `if (!False) 100 else 200` yields `200` (should be `100`)

**Root cause:** TBD. The compiler emits `emitEq()` (x == False) which is correct per spec; the VM produces inverted results. Bug may be in VM comparison operand order or constant loading. Requires investigation.

**Affected tests (hidden during e2e tidying):**
- `logical_not.ks` — in-file expected `//` comments were updated to match wrong VM behaviour
- `unary_mixed.ks` — uses `!(3 > 5)` and `!(False | False)`; in-file expected comments were updated to match wrong VM behaviour

## Acceptance Criteria

- [ ] Identify and fix root cause (compiler or VM)
- [ ] Restore correct expected output in `tests/e2e/scenarios/logical_not.ks` (the `//` comment under each `print`): `false`, `true`, `true`, `false`, `true`, `100`
- [ ] Restore correct expected output in `tests/e2e/scenarios/unary_mixed.ks` (the `//` comment under each `print`): `5`, `-16`, `-15`, `true`, `-100`
- [ ] Run `./scripts/run-e2e.sh` — all 26 scenarios pass with correct semantics
