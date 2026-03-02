# Recursive nested function in test runner

## Description

Per spec 01 §3.8, a nested `fun` with a full type signature may call itself (and other nested functions in the same block). The spec notes a known limitation: “When the same code is run inside the test runner’s closure context, the VM may hit a bus error; this path is under investigation.” Fix the VM or codegen so that recursive nested functions work in the test runner context (and in all execution paths).

## Acceptance Criteria

- [ ] Reproduce: add or identify a test that runs recursive nested `fun` inside the test runner’s closure context and observe the failure (e.g. bus error or incorrect result)
- [ ] Root cause: identify whether the bug is in closure layout, frame setup, or name resolution for recursive calls in lifted/nested context
- [ ] Fix: implement a fix in VM and/or compiler so that recursive nested functions execute correctly in test runner and in normal execution (`./kestrel run`, top-level entry)
- [ ] Add or extend test: recursive nested function (and mutual recursion between nested funs) passes in test runner and in E2E
- [ ] Document: remove or update the “Known limitations” paragraph in 01 §3.8 once fixed
