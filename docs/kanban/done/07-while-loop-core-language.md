# While loop core language support

## Sequence: 07
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 04

## Summary

Add a first-class `while` loop to the language so iterative algorithms can run without recursion. This directly reduces stack-overflow pressure by replacing recursion-as-loop patterns with explicit iteration.

## Motivation

- Users currently write recursion to model simple loops.
- Without TCO everywhere, recursion-based loops can overflow the stack.
- A native `while` improves clarity and performance for stateful iteration.

## Current State

- Implemented: `while` keyword, `WhileExpr` AST, parser, typecheck (`Bool` condition, `Unit` result), VM and JVM codegen, tests, and spec updates (01, 04, 05, 06).

## Design

- Syntax: `while (Expr) Block` (exact delimiter choices to align with existing grammar style).
- Condition must type-check as `Bool`.
- Loop expression/statement result is `Unit`.
- Runtime semantics: evaluate condition before each iteration; execute body while true.

## Acceptance Criteria

- [x] Lexer recognizes `while` keyword.
- [x] Parser adds `while` statement/expression form in appropriate block positions.
- [x] AST includes a loop node with condition and body.
- [x] Type checker enforces boolean condition and `Unit` result behavior.
- [x] Codegen (VM and JVM) lowers to condition-check + back-edge jump structure.
- [x] Add end-to-end tests showing recursion-based loops can be rewritten as `while` without stack growth.
- [x] Update specs for grammar, typing, and runtime semantics.

## Test Expectations

- [x] Parser tests for valid/invalid `while` forms.
- [x] Typecheck tests for non-boolean condition errors.
- [x] Runtime tests: counting loops, zero-iteration loops, and nested loops.
- [x] Runtime tests: large iteration counts complete without stack overflow.

## Spec References

- 01-language (statement/expression grammar and semantics)
- 06-typesystem (condition typing and loop result type)
- 04-bytecode-isa (jump layout for loop lowering)
- 05-runtime-model (execution model for iterative control flow)

## Tasks

- [x] Lexer keyword `while`, AST `WhileExpr`, parser `while (Expr) Block`
- [x] Typecheck: condition `Bool`, expression type `Unit`
- [x] Bytecode + JVM codegen with discard of body value
- [x] Tests: Vitest parse, typecheck conformance, `tests/unit/while.test.ks`, runtime conformance
- [x] Specs: 01, 04, 05, 06 updated
- [x] Full verification: `npm test`, `./scripts/kestrel test`, VM/Zig, e2e
