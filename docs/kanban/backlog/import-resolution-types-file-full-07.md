# Import resolution and types file (full 07)

## Description

Spec 07 defines module resolution (path, stdlib, URL), types file (`.kti`) format with export entries and offsets, and deterministic resolution. The implementation plan marked “Import resolution (path/stdlib/URL, multi-file compile) — deferred”; import table emission and basic path/stdlib resolution exist. This story is to complete 07: ensure every distinct specifier is resolved to an artifact using the types file from dependencies so that importers get static indices (function_index, setter_index for vars) without recompiling the dependency; support URL specifiers and lockfile when present; document or implement resolution order and cycle handling per 07 §4.3.

## Acceptance Criteria

- [ ] Resolution: for each distinct specifier, resolve to artifact (path → .ks/.kbc; stdlib → stdlib source/artifact; URL → fetch/cache/lockfile when implemented)
- [ ] Types file: compiler produces .kti for each compiled module with export entries (function, val, var with setter_index) and type encoding; consuming compiler reads .kti and builds imported function table (and setter map for vars) for cross-module calls
- [ ] Multi-file compile: compiling entry.ks with imports compiles dependencies (or loads from cache) and uses their .kti for typecheck and codegen; no name lookup at load/runtime (07 §9)
- [ ] Resolution order is deterministic; cycle behaviour is documented or implemented (07 §4.3)
- [ ] E2E: multi-module program with path and stdlib imports compiles and runs; cross-module CALL and imported var assignment work

## Notes

- Overlaps with done story “Import resolution and multi-module”; this story focuses on completing the 07 contract (types file consumption, URL/lockfile if in scope).
