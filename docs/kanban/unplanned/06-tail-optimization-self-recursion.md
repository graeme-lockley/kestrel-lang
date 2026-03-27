# Tail optimization for self-recursive functions

## Sequence: 06
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (unplanned)

## Summary

Implement tail-call optimization (TCO) for direct self-recursive calls so common accumulator-style algorithms do not grow the call stack. This addresses stack overflows for patterns like tail-recursive loops that should run in constant stack space.

## Motivation

- The VM currently consumes one call frame per recursive call.
- Users emulate loops with recursion today because there is no `while`.
- Self-tail-recursive code should be safe and efficient even before broader control-flow features land.

## Current State

- No guaranteed tail-call optimization path in compiler lowering or VM call handling.
- Tail-recursive functions can overflow the stack on large input sizes.
- Specs do not define required behavior for tail-position calls.

## Design

- Scope this story to **direct self calls in tail position only**.
- Detect tail position in the compiler for function bodies and branch tails.
- Lower eligible self-tail calls to a jump-style loop form that rebinds parameters without allocating a new frame.
- Preserve source-level semantics (evaluation order, side effects, and diagnostics).

## Acceptance Criteria

- [ ] Tail-position analysis identifies direct self calls in function tail positions.
- [ ] Codegen lowers eligible self-tail calls without creating additional call frames.
- [ ] Non-tail self recursion remains normal recursive calls.
- [ ] Behavior is identical to non-optimized execution for observable results and side effects.
- [ ] Add runtime tests with large iteration counts that previously overflowed the stack and now complete.
- [ ] Add negative tests ensuring non-tail recursion still overflows (or otherwise remains unoptimized).
- [ ] Update relevant specs to define the optimization guarantee and scope.

## Test Expectations

- [ ] Kestrel unit tests: accumulator-style factorial/sum implemented with tail recursion over large bounds.
- [ ] Kestrel unit tests: branch-tail cases (tail calls in both `if` arms) optimize correctly.
- [ ] Compiler tests: tail-position detector covers nested blocks and match branches.

## Spec References

- 01-language (function evaluation semantics; no user-visible semantic changes)
- 04-bytecode-isa (if lowering introduces or reuses specific jump/call behavior)
- 05-runtime-model (call-frame behavior under optimization)
- 06-typesystem (no typing changes expected; note as optimization-only)
