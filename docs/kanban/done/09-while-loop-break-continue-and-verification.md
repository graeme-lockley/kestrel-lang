# While loop control flow (`break` / `continue`) and verification

## Sequence: 09
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 05

## Summary

Complete `while` usability by adding `break` and `continue` plus robust validation around loop-control correctness. This story ensures practical loop authoring patterns and prevents malformed control flow.

## Motivation

- Core `while` without loop-control statements is limited for real programs.
- `break`/`continue` semantics are easy to miscompile without explicit structure and tests.
- Strong diagnostics are needed for misuse outside loops.

## Current State

- **Done:** `break` and `continue` are keywords, block statements, typechecked with `loopDepth`, VM and JVM lower nearest-enclosing `while`; conformance + `tests/unit/while.test.ks` cover runtime and invalid cases; specs 01, 04, 06, 10 updated.

## Design

- Add `break` and `continue` as loop-control statements.
- Enforce context rules: both are only valid inside loop bodies.
- Define interaction with nested loops, `if`, and `match` inside loop bodies.
- Ensure control-flow lowering targets the correct loop labels in nested scenarios.

## Acceptance Criteria

- [x] Lexer/parser support `break` and `continue`.
- [x] AST nodes for loop-control statements and source spans.
- [x] Type checker/semantic pass reports clear diagnostics when used outside loops.
- [x] Codegen (VM and JVM) lowers `break` to loop-exit jump and `continue` to loop-condition jump.
- [x] Nested-loop behavior is correct (`break`/`continue` affect nearest enclosing loop).
- [x] Add conformance tests for valid and invalid uses.
- [x] Update specs for syntax, static constraints, and runtime behavior.

## Test Expectations

- [x] Runtime tests: `break` exits early based on condition.
- [x] Runtime tests: `continue` skips remaining body and reevaluates condition.
- [x] Runtime tests: nested loops verify nearest-loop targeting.
- [x] Typecheck/conformance tests: `break`/`continue` outside loops are compile-time errors.

## Spec References

- 01-language (control-flow grammar and semantics)
- 06-typesystem (static validity constraints for loop-control statements)
- 04-bytecode-isa (jump targets for break/continue lowering)
- 10-compile-diagnostics (diagnostic codes/messages for invalid loop-control usage)

## Tasks

- [x] Lexer keywords + AST `BreakStmt` / `ContinueStmt` + `parseBlock`
- [x] Typecheck `loopDepth` + `type:break_outside_loop` / `type:continue_outside_loop`
- [x] Bytecode + JVM codegen (loop stack) + `compile-file` lambda count
- [x] Vitest (parse, lexer, typecheck integration) + conformance `.ks` + `while.test.ks`
- [x] Specs 01, 04, 06, 10
- [x] `npm test`, `./scripts/kestrel test`, `zig build test`, `./scripts/run-e2e.sh`
