# VM Lazy Loading and Linking per Spec 07 &sect;9

## Priority: 65 (Medium)

## Summary

Spec 07 &sect;9 requires that dependencies are loaded on **first use**, not eagerly at startup. The VM should load a dependency's `.kbc` only when execution first calls into that module. This allows optional/conditional dependencies and avoids unnecessary initialization.

## Current State

- The VM (`exec.zig`) implements lazy loading: dependencies are loaded only on first CALL to an imported function; module initializer runs once at load time; unused imports are never loaded; path cache prevents reloading.
- Specs 03 and 07 updated; E2E positive test added for lazy loading.

## Tasks

- [x] Create E2E test fixtures (lazy_side_a.ks, lazy_side_b.ks) and positive scenario (lazy_loading.ks + .expected)
- [x] Extend run-e2e.sh for positive tests with stdout matching
- [x] Update spec 03: n_globals in §6.1, skip distance formulas
- [x] Update spec 07 §9 and §2.4: load on first use, caching, side-effect import semantics
- [x] Run all tests (compiler, VM, unit, E2E)

## Acceptance Criteria

- [x] Dependencies are loaded only on first CALL to an imported function from that dependency.
- [x] Module initialization (entry point code) runs exactly once, at load time.
- [x] A module that is imported but never called is never loaded.
- [x] Cross-module CALL resolution uses indices from the imported function table (03 &sect;6.6), not name lookup.
- [x] Loaded modules are cached so that repeated calls don't reload.
- [x] E2E test: program imports two modules but only calls into one; verify only one is loaded (e.g., the unused module's side effects don't occur).
- [x] **Documentation**: Update all relevent specification documents allowing the decisions and formats and rationale to be well communicated and understood.

## Spec References

- 07-modules &sect;9 (Loading deferred until first use; no name-based lookup at runtime)
- 03-bytecode-format &sect;6.6 (Imported function table: import_index + function_index)
