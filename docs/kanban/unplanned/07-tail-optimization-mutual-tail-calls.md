# Tail optimization for mutual tail calls

## Sequence: 07
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (unplanned)

## Summary

Extend tail-call optimization beyond direct self recursion to support **mutual tail recursion** across functions, enabling constant-stack execution for state machines and alternation patterns expressed as tail calls.

## Motivation

- Many recursive loop encodings use two or more functions calling each other in tail position.
- Optimizing only self recursion still leaves common patterns vulnerable to stack overflow.
- This story completes a practical TCO model for loop-like recursion without changing source syntax.

## Current State

- No guaranteed optimization for mutually tail-recursive calls.
- Mutual recursion grows stack linearly with call count and can overflow.
- Runtime and compiler behavior for tail-call frame reuse across callees is unspecified.

## Design

- Build on self-TCO infrastructure from sequence 27.
- Track tail-position calls to known function targets and support reuse/transfer of frames where safe.
- Define restrictions clearly (e.g. arity agreement, calling convention constraints, closure capture limitations if any).
- Keep this optimization semantic-preserving and optional for non-eligible calls.

## Acceptance Criteria

- [ ] Tail-call analysis marks eligible mutual tail calls.
- [ ] Codegen/runtime executes eligible mutual tail-recursive cycles without unbounded frame growth.
- [ ] Clear fallback path for non-eligible cases uses normal calls.
- [ ] Add stress tests for even/odd, DFA-style, or trampoline-like mutual recursion that previously overflowed.
- [ ] Document any eligibility constraints and diagnostics (if surfaced).
- [ ] Update specs with the supported TCO model and limits.

## Test Expectations

- [ ] Kestrel runtime tests: `even`/`odd` mutual recursion over large inputs completes without stack overflow.
- [ ] Kestrel runtime tests: at least one ineligible mutual recursion case falls back to regular call semantics.
- [ ] Compiler tests: tail-position and eligibility analysis for cross-function edges.

## Spec References

- 01-language (evaluation model remains equivalent)
- 04-bytecode-isa (tail-call lowering details if bytecode representation changes)
- 05-runtime-model (frame reuse/transfer semantics)
- 09-tools (optional: debugging/disassembly visibility for optimized tail calls)
