# VM Lazy Loading and Linking per Spec 07 &sect;9

## Priority: 65 (Medium)

## Summary

Spec 07 &sect;9 requires that dependencies are loaded on **first use**, not eagerly at startup. The VM should load a dependency's `.kbc` only when execution first calls into that module. This allows optional/conditional dependencies and avoids unnecessary initialization.

## Current State

- The VM (`exec.zig`) supports multi-module execution with an `imported_modules` cache.
- Dependencies appear to be resolved when CALL targets an imported function (fn_id >= function_count).
- However, the exact loading semantics (eager vs. lazy) need verification and may not match the spec's "first use" requirement.
- Module initialization (running the module's entry point code) timing is unclear.

## Acceptance Criteria

- [ ] Dependencies are loaded only on first CALL to an imported function from that dependency.
- [ ] Module initialization (entry point code) runs exactly once, at load time.
- [ ] A module that is imported but never called is never loaded.
- [ ] Cross-module CALL resolution uses indices from the imported function table (03 &sect;6.6), not name lookup.
- [ ] Loaded modules are cached so that repeated calls don't reload.
- [ ] E2E test: program imports two modules but only calls into one; verify only one is loaded (e.g., the unused module's side effects don't occur).

## Spec References

- 07-modules &sect;9 (Loading deferred until first use; no name-based lookup at runtime)
- 03-bytecode-format &sect;6.6 (Imported function table: import_index + function_index)
