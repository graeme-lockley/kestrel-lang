# VM: Lazy loading and linking

## Description

Per spec 07 §9, loading must be deferred until **first use**: a dependency’s binary is loaded only when execution actually uses that package (e.g. first call into that module). Cross-module references are by index/offset from the types file; the loader/linker resolves these when the target package’s binary is loaded. This story ensures the VM implements first-use loading and that all cross-module CALLs go through the imported function table and link correctly.

## Acceptance Criteria

- [ ] Loading: dependency .kbc is loaded on first use (e.g. first CALL with fn_id >= function_count that resolves to that import), not at module init
- [ ] Linking: CALL with fn_id in [function_count, function_count + imported_function_count) uses imported function table entry (import_index, function_index); resolve module for import_index, load if needed, then call function at function_index in that module
- [ ] No name-based lookup at load or runtime; all references by offset/index (07 §9)
- [ ] E2E or runtime test: program that conditionally imports/calls another module only when a branch is taken; verify the dependency is not loaded when the branch is not taken (or document if current design loads at init)
