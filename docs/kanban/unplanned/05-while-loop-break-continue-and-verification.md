# While loop control flow (`break` / `continue`) and verification

## Sequence: 05
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (unplanned)

## Summary

Complete `while` usability by adding `break` and `continue` plus robust validation around loop-control correctness. This story ensures practical loop authoring patterns and prevents malformed control flow.

## Motivation

- Core `while` without loop-control statements is limited for real programs.
- `break`/`continue` semantics are easy to miscompile without explicit structure and tests.
- Strong diagnostics are needed for misuse outside loops.

## Current State

- No loop-control keywords or grammar.
- No typecheck/semantic validation for loop-control context.
- No VM/JVM lowering rules for loop exits and iteration skips.

## Design

- Add `break` and `continue` as loop-control statements.
- Enforce context rules: both are only valid inside loop bodies.
- Define interaction with nested loops, `if`, and `match` inside loop bodies.
- Ensure control-flow lowering targets the correct loop labels in nested scenarios.

## Acceptance Criteria

- [ ] Lexer/parser support `break` and `continue`.
- [ ] AST nodes for loop-control statements and source spans.
- [ ] Type checker/semantic pass reports clear diagnostics when used outside loops.
- [ ] Codegen (VM and JVM) lowers `break` to loop-exit jump and `continue` to loop-condition jump.
- [ ] Nested-loop behavior is correct (`break`/`continue` affect nearest enclosing loop).
- [ ] Add conformance tests for valid and invalid uses.
- [ ] Update specs for syntax, static constraints, and runtime behavior.

## Test Expectations

- [ ] Runtime tests: `break` exits early based on condition.
- [ ] Runtime tests: `continue` skips remaining body and reevaluates condition.
- [ ] Runtime tests: nested loops verify nearest-loop targeting.
- [ ] Typecheck/conformance tests: `break`/`continue` outside loops are compile-time errors.

## Spec References

- 01-language (control-flow grammar and semantics)
- 06-typesystem (static validity constraints for loop-control statements)
- 04-bytecode-isa (jump targets for break/continue lowering)
- 10-compile-diagnostics (diagnostic codes/messages for invalid loop-control usage)
