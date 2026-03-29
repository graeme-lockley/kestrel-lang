# E2E negative scenarios

Programs here must **not** succeed end-to-end: **`node compiler/dist/cli.js <file>.ks -o …`** should fail **or** compilation succeeds and **`vm/zig-out/bin/kestrel`** exits non-zero.

**Conventions**

- Start with a `//` comment stating **expected phase** (`compile` vs `runtime`) and the failure kind.
- For runtime cases that must show an uncaught-style stderr diagnostic (stack trace with ` at file:line`, operand stack overflow lines, or the VM’s call-depth message), add a line containing **`E2E_EXPECT_STACK_TRACE`** in a top comment (see `scripts/run-e2e.sh`).

**Scenarios**

| File | Phase | Intent |
|------|--------|--------|
| `compile_syntax_error.ks` | compile | Malformed expression |
| `compile_type_mismatch.ks` | compile | Type error |
| `compile_unknown_import.ks` | compile | Missing `kestrel:` module |
| `compile_nonexhaustive_match.ks` | compile | Non-exhaustive `match` |
| `compile_duplicate_export.ks` | compile | Duplicate export via `_fixtures/` re-exports |
| `uncaught_throw.ks` | runtime | Uncaught `throw` + stderr contract |
| `runtime_exit_one.ks` | runtime | `exit(1)` |
| `runtime_divide_by_zero.ks` | runtime | Uncaught `DivideByZero` |
| `runtime_stack_overflow.ks` | runtime | Call-frame limit (non-tail recursion) |
| `runtime_catch_no_match_rethrow.ks` | runtime | Catch arm mismatch → rethrow (01 §4) + stderr contract |

Positive scenarios (stdout goldens) live in `../positive/`.
