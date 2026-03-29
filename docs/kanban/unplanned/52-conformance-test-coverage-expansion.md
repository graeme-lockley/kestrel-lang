# Conformance Test Coverage Expansion

## Sequence: 52
## Tier: 5 — Test coverage and quality
## Former ID: 19

## Summary

Spec 08 defines comprehensive conformance test requirements. The current test suite covers many features but has gaps. This story tracks expanding test coverage to match the spec's requirements across all categories.

## Current State

### Parse conformance (`tests/conformance/parse/`)
- Only a small number of valid files; few or no invalid files.
- Spec 08 §2.1 requires "every production in the grammar covered by at least one test."

### Typecheck conformance (`tests/conformance/typecheck/`)
- Multiple valid and invalid files; gaps remain.

### Runtime conformance (`tests/conformance/runtime/`)
- Few files (e.g. async_await, exception, gc_stress).
- Spec 08 §2.4-2.5 requires tests for each instruction, calling convention, tagged values, heap objects.

### Kestrel unit tests (`tests/unit/`)
- Many test files covering major features; some gaps.

### Gaps (examples)
- Parse invalid: may have no or few test files.
- Missing conformance for: string interpolation parsing, shebang handling, record vs block disambiguation, pipeline parsing, cons operator precedence.
- Missing conformance for: closure capture semantics (by-value vs by-reference), mutual recursion at block level, export var assignment.
- Missing runtime conformance for: SPREAD, closure GC, multi-module execution.

## Acceptance Criteria

- [ ] **Parse valid** (at least 10 more): shebang, string interpolation, all operator precedences, record literal, list literal with spread, lambda, nested match, type annotations, generic types, exception declaration.
- [ ] **Parse invalid** (at least 5): unclosed string, missing `=>` in match, unclosed block, reserved word as identifier, invalid integer literal.
- [ ] **Typecheck invalid** (at least 3 more): assignment to immutable field, await in non-async, mutual recursion type mismatch.
- [ ] **Runtime valid** (at least 5 more): SPREAD instruction, closure capture (by-value val, by-reference var), multi-module call, deep recursion, string interpolation at runtime.
- [ ] All new tests pass.

## Spec References

- 08-tests (entire spec, especially §2 test categories and §3.5 coverage goals)
