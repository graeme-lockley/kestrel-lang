# VSCode Extension: Cross-File Navigation and Workspace Symbols (requires E04 + E07)

## Sequence: S10-12
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E10 VSCode Extension — Language Server and Editor Integration](../epics/unplanned/E10-vscode-extension-language-server.md)
- Companion stories: S10-01, S10-02, S10-03, S10-04, S10-05, S10-06, S10-07, S10-08, S10-09, S10-10, S10-11

## Summary

Upgrade go-to-definition, completion, and find-references to work across files. Cmd-clicking an imported name navigates to its declaration in the originating module. Find-references lists every use-site of a binding across the workspace. Rename updates all references. Workspace symbol search (`Cmd+T`) shows all top-level declarations across all `.ks` files. These cross-file features require E04 (stable module identities) and E07 (incremental `.ksi` metadata files) for acceptable performance.

## Current State

Go-to-definition (S10-05) and completion (S10-05) work within a single file. Cross-file lookup requires the LSP server to load and type-check all reachable modules, which is only feasible with E07's `.ksi` incremental metadata. E04 provides stable module specifiers needed for URIs in cross-package navigation.

## Relationship to other stories

- **Blocked by E04 (Module Resolution and Reproducibility)** and **E07 (Incremental Compilation)**.
- **Depends on S10-05** (single-file go-to-definition) — extends rather than replaces.
- This is the last story in the E10 roadmap; all Tier 1 features (S10-01 through S10-09) can ship before this story is started.

## Goals

1. Extend `compiler-bridge.ts` with `compileWorkspace(workspaceRoot: string): Map<uri, { ast: Program; types: TypeEnv }>` using `compileFileJvm()` + E07 `.ksi` files for incremental loading.
2. Upgrade `providers/definition.ts`: when the resolved name comes from an `import` statement, open the source of the target module (via E04 resolver) and find the matching `FunDecl`/`ValDecl` span. Return a cross-file `Location`.
3. Add `vscode-kestrel/src/server/providers/references.ts`: `textDocument/references` — collect all `IdentExpr` / `IdentType` nodes across all loaded modules whose resolved declaration matches the target.
4. Add `vscode-kestrel/src/server/providers/rename.ts`: `textDocument/rename` — gather all reference locations (as in find-references), return a `WorkspaceEdit` replacing each reference and the declaration with the new name.
5. Upgrade `providers/completion.ts` to include cross-module exported names (from loaded `.ksi` type index) in the completion list.
6. Add `vscode-kestrel/src/server/providers/workspaceSymbols.ts`: `workspace/symbol` — returns all `DocumentSymbol`s from all loaded module ASTs, filtered by the query string.
7. Register new capabilities: `referencesProvider`, `renameProvider`, `workspaceSymbolProvider`.
8. Integration tests with a two-file project: go-to-definition from one file to another; find-references returns both files.

## Acceptance Criteria

- Cmd-clicking an imported name (e.g., `println`) navigates to its definition in the stdlib `.ks` file.
- "Find All References" for a top-level `fun` lists every call site across all `.ks` files in the workspace.
- Renaming a function updates all call sites across files.
- `Cmd+T` (workspace symbol) finds any `fun`, `val`, or `type` declaration by name prefix.
- Cross-module completion shows exported names from all reachable modules.

## Spec References

- `docs/specs/07-modules.md` — module resolution and export rules.
- E04 and E07 stories (once completed) for `.ksi` format and resolver API.

## Risks / Notes

- Loading all workspace modules on every keystroke is expensive. This story must integrate with E07's on-demand incremental compilation so only dirty modules are re-checked.
- Rename safety: the rename provider must verify that the new name does not clash with an existing binding in any reachable scope before applying the `WorkspaceEdit`.
- URL-specifier modules (fetched from the internet) are navigable to a local cache copy; the `Location.uri` should point to the cached `.ks` source.
- This story should be planned (moved to `planned/`) only after both E04 and E07 are in `done/`.
