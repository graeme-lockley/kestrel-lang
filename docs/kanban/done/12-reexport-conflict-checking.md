# Re-export Conflict Checking

## Sequence: 12
## Tier: 3 — Complete the core language
## Former ID: 95

## Summary

[07-modules.md](../../specs/07-modules.md) §3.2–§3.4 require a **computed export set** for each module: every `export * from` and `export { … } from` contributes **(name, source)** pairs, with a **compile error** when the same export name would come from **different** sources (07 §3.3). The reference compiler now implements this pipeline end-to-end: distinct specifiers include re-export `from` strings, dependencies are resolved and merged in `typecheck` with `export:reexport_conflict` / `export:not_exported`, bytecode uses `importSpecifierOrder` aligned with the imported-function table, and `exportFunctionSlotByName` enables transitive re-exports for named imports and namespace members.

## Current State (done)

- **Parser:** Unchanged (`ExportStar` / `ExportNamed`).
- **compile-file / compile-file-jvm:** `distinctSpecifiersInSourceOrder` ([module-specifiers.ts](../../../compiler/src/module-specifiers.ts)); `dependencyExportsBySpec` passed into `typecheck`; re-export wiring and `.kti` emission; `resolveExportedCtorOrigin` for namespace constructors through re-export chains; `exportFunctionSlotByName` on the compile cache for cross-hop value imports.
- **Typecheck:** Source-order export merge with conflict diagnostics and `reexports` list ([check.ts](../../../compiler/src/typecheck/check.ts)).
- **Codegen:** Optional `importSpecifierOrder` for import table ([codegen.ts](../../../compiler/src/codegen/codegen.ts)).
- **Diagnostics:** `export:reexport_conflict` ([types.ts](../../../compiler/src/diagnostics/types.ts)).
- **Tests:** [reexport-conflict.test.ts](../../../compiler/test/integration/reexport-conflict.test.ts).

## Tasks

- [x] Implement distinct specifiers + dependency snapshots + typecheck merge and conflicts
- [x] Wire re-exports in compile-file (imports, codegen import table, .kti, transitive slots)
- [x] JVM compile-file parity (specifiers, export sets, `dependencyExportsBySpec`)
- [x] Integration tests + full compiler / kestrel / VM / e2e verification
- [x] Update specs (07, 03, kti-format, 10, language spec §11) and story closure

## Acceptance Criteria

### Behaviour (spec 07 §3.2–§3.4, §8, §10 item 4)

- [x] Build the module export set in **source order**, tracking **source** per name: **local** vs **re-export from &lt;specifier&gt;** (07 §3.3–§3.4).
- [x] **`export * from`:** Resolve the specifier, take the dependency’s **fully computed** export set (including transitive re-exports in that dependency, 07 §3.4), add each name with that re-export source.
- [x] **`export { x [ as y ] } from`:** Verify `x` is in the dependency export set (07 §3.2); add `y` (or `x`) with that re-export source; missing name → compile error.
- [x] **Conflict:** Same export name from **different** sources → compile error (07 §3.3). Stable code **`export:reexport_conflict`** and **`related`** span for the first export (10 §2).
- [x] **No conflict:** Same name re-exported twice from the **same** specifier (e.g. `export * from "./m"` then `export { x } from "./m"` when `x` is already exported by `./m`) remains valid (07 §3.3).
- [x] **Local vs re-export:** A local export and a re-export of the same simple name from a dependency → conflict (07 §3.1, §3.3).
- [x] **Recursive re-export:** If A does `export * from "./b"` and B does `export * from "./c"`, then A’s export set includes everything C exports via B (07 §3.4); integration test.
- [x] **End-to-end:** Re-exported value/type/exception and non-opaque ADT constructors visible through barrel; `.kti` and import / imported-function tables aligned with 07 §5–§6 and 03 §6.5–§6.6.
- [x] **JVM path:** [compile-file-jvm.ts](../../../compiler/src/compile-file-jvm.ts) uses the same distinct-specifier and dependency-export rules for typecheck.

### Documentation

- [x] **07-modules.md:** §2.1 and §6 updated; checklist §10 item 2 updated.
- [x] **03-bytecode-format.md:** §6.5 import_count wording aligned with 07.
- [x] **kti-format.md:** Note on re-exported names in `.kti`.
- [x] **10-compile-diagnostics.md:** `export:reexport_conflict` in §4.
- [x] **01-language.md:** N/A — grammar unchanged; behaviour matches existing ExportDecl wording.
- [x] **Kestrel_v1_Language_Specification.md** §11: distinct specifiers note added.

### Tests

- [x] Conflict — two `export *` (code + `export:reexport_conflict`).
- [x] Conflict — `export *` + `export { … }` from another specifier.
- [x] Conflict — local + re-export.
- [x] No conflict — same specifier `export *` + `export { x }`.
- [x] Rename resolves conflict; importer uses both names.
- [x] Invalid external name → `export:not_exported`.
- [x] Transitive `export *` chain.
- [x] Opaque type + exported ADT + `val` re-exported via `export *` (namespace smoke).
- [x] `.kti` consumer: barrel fresh `.kti` / `.kbc`, stale leaf `.ks`.
- [x] Regression: `npm test` (compiler), `./scripts/kestrel test`, `zig build test` (vm), `./scripts/run-e2e.sh`.

**Conformance `.ks` (tests/conformance/typecheck):** N/A — the conformance harness runs single-file `typecheck` only; re-exports require `compileFile` and `dependencyExportsBySpec`. Coverage is in `compiler/test/integration/reexport-conflict.test.ts` instead.

## Spec References

- [01-language.md](../../specs/01-language.md) §3.1 — `ExportDecl`, `ExportSpec`
- [03-bytecode-format.md](../../specs/03-bytecode-format.md) §6.5–§6.6 — Import and imported-function tables
- [07-modules.md](../../specs/07-modules.md) §2.1, §3.2, §3.3, §3.4, §5–§6, §8, §10
- [10-compile-diagnostics.md](../../specs/10-compile-diagnostics.md) §2, §4
- [kti-format.md](../../specs/kti-format.md)

## Dependencies / Notes

- Cycles (07 §4.3): unchanged; circular **import** still rejected by existing `visited` / cache behaviour.
