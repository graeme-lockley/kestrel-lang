# Re-export Conflict Checking

## Priority: 19 (Medium)

## Summary

Spec 07 &sect;3.3 requires that when two exports introduce the same name from different sources, a compile error is reported. The current implementation may not fully enforce this -- particularly for `export * from` which can silently re-export conflicting names.

## Current State

- `compile-file.ts` resolves imports and builds export sets.
- Basic name collision detection exists for same-module declarations.
- `export * from "./a"` and `export * from "./b"` where both export `foo` may not be detected as a conflict.
- Re-export with rename (`export { foo as bar } from "./a"`) likely works for simple cases.
- No test coverage for re-export conflicts.

## Acceptance Criteria

- [ ] `export * from` builds the full export set tracking source per name.
- [ ] When two different sources produce the same export name, report a compile error with both sources.
- [ ] Same name re-exported from the same source (e.g., `export * from "./m"` and `export { x } from "./m"`) is allowed (not a conflict).
- [ ] Recursive re-exports: if A re-exports all of B and B re-exports all of C, the full transitive set is computed.
- [ ] Conformance test: two `export *` with conflicting names produces error.
- [ ] Conformance test: renamed re-export resolves conflict.

## Spec References

- 07-modules &sect;3.3 (Export conflicts)
- 07-modules &sect;3.4 (Definition of export set algorithm)
