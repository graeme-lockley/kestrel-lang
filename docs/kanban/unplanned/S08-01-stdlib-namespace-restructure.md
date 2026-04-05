# Stdlib Namespace Restructure

## Sequence: S08-01
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/unplanned/E08-source-formatter.md)
- Companion stories: S08-02, S08-03, S08-04, S08-05, S08-06, S08-07

## Summary

The current stdlib is a flat collection of `kestrel:X` modules (e.g., `kestrel:string`, `kestrel:list`). This story reorganises those modules into a principled sub-namespace hierarchy:

- `kestrel:data/*` — pure data structures and algorithms
- `kestrel:io/*` — effectful I/O modules
- `kestrel:sys/*` — system-level concerns (processes, tasks, runtime errors)
- `kestrel:dev/stack` — debug/developer tools

Every import site in `stdlib/`, `tests/`, `scripts/`, and root-level example files is updated to use the new paths. The old flat paths are removed (clean cut — no aliases).

The sub-path resolver (S04-02, already done) means no compiler changes are needed; the file-existence fallback automatically resolves any valid `kestrel:X/Y` specifier.

## Current State

`stdlib/kestrel/` contains 22 flat `.ks` files:
`array.ks`, `basics.ks`, `char.ks`, `console.ks`, `dict.ks`, `fs.ks`, `http.ks`, `json.ks`, `list.ks`, `option.ks`, `process.ks`, `result.ks`, `runtime.ks`, `set.ks`, `socket.ks`, `stack.ks`, `string.ks`, `task.ks`, `test.ks`, `tuple.ks`, `web.ks`.

All of these use `import "kestrel:X"` style specifiers internally and are referenced by ~96 files in `stdlib/`, `tests/`, `scripts/`, and the root examples.

`kestrel:socket`, `kestrel:web`, and `kestrel:web routing` are E03 networking modules; they are **not** moved in this story (they are not in the E08 namespace table) and stay at their current paths.

`kestrel:test` and `kestrel:array` are separate concerns:
- `kestrel:test` → `kestrel:tools/test` is handled by S08-06.
- `kestrel:array` is not listed in the E08 namespace table; it stays at `kestrel:array` for now.

## Relationship to other stories

- **Blocks** S08-03, S08-04, S08-05, S08-06, S08-07 — all later stories import from the new paths.
- **Independent of** S08-02 (CLI change).
- **Depends on** S04-02 (already done) for file-existence resolver fallback.

## Goals

1. Move the 15 stdlib modules listed in the E08 namespace table to their new locations.
2. Update every `import "kestrel:X"` reference in `stdlib/`, `tests/`, `scripts/`, and root-level `.ks` files to use the new path.
3. Delete the old flat files (or replace them with a clear error to catch stale imports discovered during the migration).
4. All existing passing tests continue to pass after the rename.

## Acceptance Criteria

- `stdlib/kestrel/data/basics.ks`, `data/char.ks`, `data/string.ks`, `data/list.ks`, `data/dict.ks`, `data/set.ks`, `data/tuple.ks`, `data/option.ks`, `data/result.ks`, `data/json.ks` all exist.
- `stdlib/kestrel/io/console.ks`, `io/fs.ks`, `io/http.ks` all exist.
- `stdlib/kestrel/sys/process.ks`, `sys/task.ks`, `sys/runtime.ks` all exist.
- `stdlib/kestrel/dev/stack.ks` exists.
- Old flat files are removed.
- `cd compiler && npm test` passes.
- `./scripts/kestrel test` passes.
- `./scripts/run-e2e.sh` passes.

## Spec References

- `docs/specs/02-stdlib.md` — stdlib public API
- `docs/specs/07-modules.md` — module specifier resolution rules

## Risks / Notes

- **Large search-and-replace**: ~96 files need import updates. Use a scripted `sed` replacement to avoid manual errors.
- **Test files that test error paths** (`tests/e2e/scenarios/negative/`) may import `kestrel:no_such_module_e2e_51` intentionally — leave those unchanged.
- `kestrel:socket`, `kestrel:web`, `kestrel:web routing` are **not** in scope for this story.
- `kestrel:test` is **not** moved here; that is S08-06.
- `kestrel:array` is not in the E08 namespace table and stays flat.
- The `.test.ks` files adjacent to each stdlib module need their imports updated too.
