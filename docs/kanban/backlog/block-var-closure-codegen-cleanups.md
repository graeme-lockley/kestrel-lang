# Block var and closure codegen cleanups

## Description

Per `docs/REVIEW_block_var_codegen.md`, the BlockExpr codegen in `compiler/src/codegen/codegen.ts` has workarounds and fragile patterns that should be cleaned up: (1) placeholder entries (`\x00_0`, etc.) used to pad `blockEnv` so the next slot index skips reserved closure slots—prefer an explicit “next block-local slot” variable instead of deriving from `blockEnv.size`; (2) magic number `2` for `blockLocalStart` when inside a capturing closure—derive from actual closure layout or a shared constant; (3) optional: add discard after SET_FIELD when `needsDiscard` and target is a record field, for consistency and to avoid unnecessary stack growth; (4) document that `blockEnv` may contain internal keys (`$discard`, padding) not from the AST.

## Acceptance Criteria

- [ ] Replace placeholder padding loop with explicit next-block-slot tracking (e.g. `nextBlockSlot` variable); use it for `$discard` and each VarStmt/ValStmt; remove `\x00_*` map entries
- [ ] Replace magic `2` for `blockLocalStart` with a value derived from closure layout (e.g. 1 + number of lambda params when in capturing closure) or a named constant used by both LambdaExpr and BlockExpr
- [ ] (Optional) After SET_FIELD for record-field assignment, when `needsDiscard` is true, store result in `$discard` for consistency with ExprStmt and ident assignment
- [ ] Add a short comment that `blockEnv` may contain internal keys (`$discard`, etc.) not from the AST
- [ ] Existing tests (block var, closure, assignment) still pass
