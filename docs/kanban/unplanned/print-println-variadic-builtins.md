# print / println — variadic built-ins

## Description

Add `print` and `println` as built-in primitives with variadic, space-separated output.

**Semantics:**
- **`print(a, b, ...)`** — Print each value separated by spaces, **no** trailing newline.
- **`println(a, b, ...)`** — Print each value separated by spaces, **with** trailing newline.

**Breaking change:** Current `print(x)` adds a newline; under the new design, `print(x)` would not, and `println(x)` would. Existing call sites that rely on a newline must be updated to `println`.

**Spec note:** The `print` in **02-stdlib** (`kestrel:stack`) is for stack traces and is a different feature. The spec will need to distinguish built-in `print`/`println` from the stdlib module.

## Acceptance Criteria

- [ ] Specs (02 and language spec) updated to define `print` and `println` built-ins
- [ ] Compiler: typecheck and codegen for variadic `print` and `println`; new primitive IDs
- [ ] VM: primitives that pop N values, format with space separation, optional trailing newline
- [ ] E2E tests updated to use `println(...)` where a newline is expected (or accommodate new behaviour)
