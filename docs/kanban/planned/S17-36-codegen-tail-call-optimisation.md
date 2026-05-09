# Self-hosted codegen: tail-call optimisation (loop-back GOTO)

## Sequence: S17-36
## Tier: 8
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-35, S17-37 through S17-38, S17-44

## Summary

The TS compiler applies self-tail-call optimisation to recursive functions: instead of a
recursive `INVOKESTATIC` + `ARETURN`, the last call to the function itself is replaced with
argument stores followed by a `GOTO` back to the method's start label. Without this
optimisation the self-hosted codegen will produce stack-overflowing recursive programs where
the TS compiler would produce a tight loop.

## Current State

The self-hosted `emitFunDecl` calls `emitTailLoopScaffold` which emits a `GOTO` to a
`loopStart` label and assigns `loopStart` in the method builder — but `emitExpr` never
emits the corresponding back-edge `GOTO`. The scaffold exists but the tail-call detection
and `GOTO` emission are absent.

TS reference:
- Each method starts with a label `loopHead` and a `GOTO loopHead+N` (skip the stores).
- When `emitExpr` detects a tail-position self-call (callee is the current function name
  and we are in a tail context `tailCtx`): store each arg to the corresponding parameter
  slot, `GOTO loopHead`.
- The `subJvmTail` / `JvmEmitTailContext` mechanism tracks whether an expression is in
  tail position through blocks, if-branches, match arms, etc.

## Relationship to other stories

- **Depends on**: S17-27 (`ECall` — tail calls are a special case of call emission).
- **Recommended after**: S17-30 (`EIf`) and S17-32 (`EMatch`) — tail position must be
  propagated through branches and match arms.
- **Recommended after**: the first real execution tranche and basic runtime-negative re-enable.
  TCO matters for parity and deep recursion, but it is not the first gate to remove the temporary
  startup/E2E workarounds.
- **Blocks**: S17-44 (E2E) only indirectly — programs will still run without TCO but will
  stack-overflow on deeply recursive calls.

## Goals

1. Introduce a `TailContext` type (mirroring `JvmEmitTailContext`) and thread it through
   `emitExpr`, `emitBlockStmt`, and `emitBlockStmts`.
2. In `emitFunDecl`, set `tailCtx = TailContext(funcName, paramSlots)` for the body.
3. Propagate tail context through `EBlock` (only the final expression), `EIf` (both arms),
   `EMatch` arms, `ETry` (try body only), and `EWhile` (never tail).
4. In `ECall`, when `tailCtx` is set and the callee is `tailCtx.funcName`:
   - Evaluate each argument.
   - Store each argument to the corresponding parameter slot in reverse order.
   - `GOTO loopHead` (the scaffold label emitted by `emitTailLoopScaffold`).
5. Verify that the `thenArmPushesValue` predicate (used in `EIf`) correctly returns `False`
   for arms that end with a tail call → `GOTO` (no stack value pushed).

## Acceptance Criteria

- [ ] A recursive `fun sum(n, acc)` compiles without stack overflow for `n = 100_000`.
- [ ] A mutually recursive function pair that is NOT self-tail still uses `INVOKESTATIC`
      (mutual tail-call optimisation is out of scope for this story).
- [ ] New conformance tests cover deep self-recursion that would overflow without TCO.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — tail-call semantics (implicit; functions must not overflow
  for tail-recursive patterns)

## Risks / Notes

- The TS compiler's `JvmEmitTailContext` is optional (`| undefined`) and threaded through
  every call to `emitExpr`. The self-hosted version must thread it through the recursive
  `emitExpr` call (currently a single function). Consider adding it as a second parameter
  to `emitExpr` and `emitBlockStmt`.
- Treat this as a later parity/performance tranche unless a restored E2E specifically proves it is
  still blocking. The immediate goal is real execution and honest gating, not early TCO polish.

## Impact analysis

| Area | Change |
|------|--------|
| Parser | No parser changes expected. Tail-call optimization is a backend lowering over existing AST forms (`ECall`, `EIf`, `EMatch`, `EBlock`, `ETry`, `EWhile`). |
| Typecheck | No typechecker rule changes expected. Tail position is a codegen concept, not a type-system change. |
| Codegen (bytecode) | No TypeScript JVM codegen changes expected for this story; TS remains reference behavior for parity checks. |
| Codegen (JVM, self-hosted) | Update `stdlib/kestrel/tools/compiler/codegen.ks` to introduce a tail-context carrier, thread it through `emitExpr` and helper flows, and lower eligible self-tail calls to argument stores plus `GOTO` back-edge to the existing loop scaffold label. Update `thenArmPushesValue` handling so tail-lowered then-arms are treated as non-value-pushing control transfer. |
| JVM runtime | No runtime API changes expected (`runtime/jvm/src/**`). Behavior change is in compiler output shape (looping bytecode instead of recursive static call for direct self-tail calls). |
| Stdlib | Compiler stdlib module `kestrel:tools/compiler/codegen` changes only. No user-facing stdlib API additions/removals. |
| Scripts / CLI | No CLI command-shape changes expected. Keep `scripts/test-kestrel.sh` gating notes aligned with this story as part of S17-36/S17-37/S17-38 tranche tracking (no script logic change required in this story unless validation proves otherwise). |
| Tests | Extend self-hosted codegen unit coverage in `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` for tail-self lowering and mutual-recursion fallback. Add self-hosted runtime conformance case under `tests/kconformance/runtime/valid/` for deep tail recursion that would overflow without lowering. |
| Docs / specs | Verify `docs/specs/01-language.md` tail-position semantics remain accurate; update wording only if needed to clarify self-tail recursion non-overflow expectation as an implementation guarantee for top-level tail calls. |
| Compatibility / rollback risk | Medium-low compatibility risk: code shape changes are internal to generated bytecode; source semantics are unchanged. Main risk is incorrect tail-context propagation causing wrong control flow or verifier issues. Rollback path is localized to `codegen.ks` tail-context plumbing and `ECall` lowering branch. |

## Tasks

- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks`, add a tail-context representation (for current function name + parameter slots + loop head target) and thread it through `emitExpr` plus helper entry points that currently recurse (`emitIfExpr`, `emitMatchExpr`, `emitETry`, `emitBlockStmts` / `EBlock`, and any shared helper that re-invokes `emitExpr`).
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks` `emitFunDecl`, initialize tail context for the function body (both sync body and async payload body) using the scaffold label created by `emitTailLoopScaffold` and the function's parameter slot mapping.
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks`, encode tail-position propagation rules: final expression of `EBlock` is tail, both `EIf` arms are tail when parent is tail, each `EMatch` arm body is tail when parent is tail, `ETry` body remains tail while handlers are non-tail unless proven equivalent, and `EWhile` never propagates tail context.
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks` `emitCallExpr`, add direct self-tail fast path: when callee resolves to current function in active tail context and arity matches, emit argument evaluation, right-to-left stores to parameter slots, and `GOTO` loop head; otherwise keep existing `INVOKESTATIC` / indirect call behavior.
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks`, update `thenArmPushesValue` (and any call sites in if-lowering) so then-arms ending in a tail-lowered jump are treated as non-value-pushing, avoiding unreachable `ASTORE`/join-bytecode patterns.
- [ ] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`, add/extend opcode-level tests that assert: (1) self-tail call lowering emits `GOTO` back-edge and parameter stores rather than `INVOKESTATIC`; (2) mutual recursion path still emits `INVOKESTATIC` (out-of-scope for this story); (3) `if` then-arm bookkeeping remains verifier-safe when tail-lowered.
- [ ] Add `tests/kconformance/runtime/valid/tail_self_recursion.ks` (or equivalent name) to validate deep self-tail recursion (`n >= 100000`) executes successfully with stable expected output and does not stack overflow.
- [ ] Add `tests/kconformance/runtime/valid/tail_mutual_fallback.ks` (or equivalent name) to validate mutually recursive behavior remains semantically correct without introducing accidental mutual-TCO lowering in this story.
- [ ] Run `./scripts/test-kestrel.sh` to validate the self-hosted `k*` corpora after adding new `tests/kconformance` cases.
- [ ] Run `cd compiler && npm run build && npm test`.
- [ ] Run `./scripts/kestrel test`.
- [ ] Run `./scripts/run-e2e.sh` (user-visible codegen behavior change).

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel unit (self-hosted compiler) | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Verify self-tail lowering in bytecode shape: direct self-tail call lowers to argument stores + `GOTO` loop head (no direct `INVOKESTATIC` in the optimized path), while non-self/mutual recursion remains `INVOKESTATIC`. Add guard for `thenArmPushesValue` interaction to prevent unreachable branch-store patterns. |
| Self-hosted runtime conformance | `tests/kconformance/runtime/valid/tail_self_recursion.ks` | Happy path: deep self-tail recursion (e.g., accumulator sum/count) completes and prints expected values. Regression guard: branch-structured tail recursion still loops correctly. |
| Self-hosted runtime conformance | `tests/kconformance/runtime/valid/tail_mutual_fallback.ks` | Boundary/negative-scope guard: mutually recursive functions remain correct without requiring mutual-TCO. Note: JVM opcode-shape assertions for `INVOKESTATIC` vs `GOTO` remain in `codegen-expr.test.ks`; runtime conformance checks observable behavior only. |

## Documentation and specs to update

- [ ] `docs/specs/01-language.md` — review tail-position/top-level tail-call wording and update only if clarification is needed to match implemented self-tail behavior and explicit non-goal for mutual TCO in this story.
