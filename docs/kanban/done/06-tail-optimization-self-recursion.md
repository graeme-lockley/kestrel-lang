# Tail optimization for self-recursive functions

## Sequence: 06
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (unplanned)

## Summary

Implement tail-call optimization (TCO) for direct self-recursive calls so common accumulator-style algorithms do not grow the call stack. This addresses stack overflows for patterns like tail-recursive loops that should run in constant stack space.

## Motivation

- The VM consumes one call frame per ordinary `CALL`.
- Tail-recursive loops should run in constant stack space alongside `while` (04/05).
- Self-tail-recursive code should remain safe for large iteration counts.

## Current State

- **Done:** Reference compiler (kbc + JVM) lowers direct self calls in tail position to `STORE_LOCAL` + `JUMP` (no extra frame). Specs updated. `tests/unit/tail_self_recursion.test.ks` covers deep tail recursion, branch tails, and non-tail correctness.

## Design

- Scope: **direct self calls in tail position only** (top-level `fun`).
- Tail position threaded through codegen (`if`/`match`/block result/try body and catch / pipe); **not** under short-circuit `&`/`|`.
- Lowering: evaluate args left-to-right, assign parameter slots, backward `JUMP` to function entry (offset 0 in the function chunk).

## Tasks

- [x] Tail-context threading and self-tail lowering in `compiler/src/codegen/codegen.ts`
- [x] JVM parity in `compiler/src/jvm-codegen/codegen.ts` (same scope; `if` branches keep `tcN` where lowering uses local merge slots)
- [x] Kestrel unit tests `tests/unit/tail_self_recursion.test.ks`
- [x] Spec updates: `01-language.md`, `04-bytecode-isa.md`, `05-runtime-model.md`, `06-typesystem.md`

## Acceptance Criteria

- [x] Tail-position analysis identifies direct self calls in function tail positions (codegen `EmitTailContext` / JVM equivalent).
- [x] Codegen lowers eligible self-tail calls without creating additional call frames (no `CALL` for those sites).
- [x] Non-tail self recursion remains normal recursive calls (`CALL`).
- [x] Behavior matches non-optimized execution for results (tests assert sums / branch counts).
- [x] Runtime tests with large iteration counts complete without stack overflow.
- [x] Non-tail recursion still correct on shallow depth (deep overflow test omitted for CI time; unoptimized path unchanged).
- [x] Specs define optimization guarantee and scope.

## Test Expectations

- [x] Kestrel unit tests: tail-recursive sum and branch-tail `countBranch` over large bounds.
- [x] Kestrel unit tests: non-tail `sumNonTail` shallow case.
- [ ] Compiler disassembly snapshot tests (optional; runtime tests exercise lowering).

## Spec References

- 01-language (tail-position self calls note)
- 04-bytecode-isa (self tail-call lowering)
- 05-runtime-model (§1.2 call frames)
- 06-typesystem (optimization-only note)
