# BUG Logical NOT operator returns operand unchanged

## Description

The logical NOT operator (`!`) returns the operand unchanged instead of negating it. For example:
- `!True` outputs `true` (should be `false`)
- `!False` outputs `false` (should be `true`)
- `if (!False) 100 else 200` yields `200` (should be `100`)

**Root cause:** The lexer did not recognize `!` as an operator. `singleOps` in `tokenize.ts` was `'+-*/%|&<=>'` (missing `!`), so `!` was skipped and `!True` was parsed as `True`. Fix: add `!` to singleOps. Also added constant-folding for `!True`→False, `!False`→True in codegen.

**Affected tests (hidden during e2e tidying):**
- `logical_not.ks` — in-file expected `//` comments were updated to match wrong VM behaviour
- `unary_mixed.ks` — uses `!(3 > 5)` and `!(False | False)`; in-file expected comments were updated to match wrong VM behaviour


## Tasks

- [x] Determine what the correct binary code is, given the bytecode ISA, for the lines "print(!True)" and "print(!False)".
- [x] Create a test to show that the lines "print(!True)" and "print(!False)" create the correct binary code.  This must be a permanent test and should fall within the compiler's unit tests.  If the correct binary code is not being produced then fix the compiler.
- [x] If the compiled code is correct, then run the binary code and confirm that it has the expected output.  If not, then fix the VM.
- [x] Restore correct expected output in `tests/e2e/scenarios/logical_not.ks` (the `//` comment under each `print`): `false`, `true`, `true`, `false`, `true`, `100`
- [x] Restore correct expected output in `tests/e2e/scenarios/unary_mixed.ks` (the `//` comment under each `print`): `5`, `-16`, `-15`, `true`, `-100`
- [x] Run `./scripts/run-e2e.sh` — all 26 scenarios pass with correct semantics

## Acceptance Criteria

- [x] The logical_not.ks tests are expecting the correct results
- [x] All the unit and e2e tests pass
