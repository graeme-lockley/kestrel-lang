# Conformance Test Coverage Expansion

## Priority: 34 (Low)

## Summary

Spec 08 defines comprehensive conformance test requirements. The current test suite covers many features but has gaps. This story tracks expanding test coverage to match the spec's requirements across all categories.

## Current State

### Parse conformance (`tests/conformance/parse/`)
- Only 2 valid files, 0 invalid files.
- Spec 08 &sect;2.1 requires "every production in the grammar covered by at least one test."

### Typecheck conformance (`tests/conformance/typecheck/`)
- 17 valid, 13 invalid files. Reasonably good but gaps exist.

### Runtime conformance (`tests/conformance/runtime/`)
- 3 files (async_await, exception, gc_stress).
- Spec 08 &sect;2.4-2.5 requires tests for each instruction, calling convention, tagged values, heap objects.

### Kestrel unit tests (`tests/unit/`)
- 15 test files covering major features. Good coverage but some gaps.

### Gaps
- Parse invalid: no test files.
- No conformance tests for: string interpolation parsing, shebang handling, record vs block disambiguation, pipeline parsing, cons operator precedence.
- No conformance tests for: closure capture semantics (by-value vs by-reference), mutual recursion at block level, export var assignment.
- No runtime conformance for: SPREAD, closure GC, multi-module execution.

## Acceptance Criteria

- [ ] **Parse valid** (at least 10 more): shebang, string interpolation, all operator precedences, record literal, list literal with spread, lambda, nested match, type annotations, generic types, exception declaration.
- [ ] **Parse invalid** (at least 5): unclosed string, missing `=>` in match, unclosed block, reserved word as identifier, invalid integer literal.
- [ ] **Typecheck invalid** (at least 3 more): assignment to immutable field, await in non-async, mutual recursion type mismatch.
- [ ] **Runtime valid** (at least 5 more): SPREAD instruction, closure capture (by-value val, by-reference var), multi-module call, deep recursion, string interpolation at runtime.
- [ ] All new tests pass.

## Spec References

- 08-tests (entire spec, especially &sect;2 test categories and &sect;3.5 coverage goals)
