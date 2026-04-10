# Stdlib Namespace Restructure

## Sequence: S08-01
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/done/E08-source-formatter.md)
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

- **Large search-and-replace**: ~74 files need import updates. Use a scripted `sed` replacement to avoid manual errors.
- **Test files that test error paths** (`tests/e2e/scenarios/negative/`) may import `kestrel:no_such_module_e2e_51` intentionally — leave those unchanged.
- `kestrel:socket`, `kestrel:web`, and `kestrel:web routing` are **not** in scope for this story.
- `kestrel:test` is **not** moved here; that is S08-06.
- `kestrel:array` is not in the E08 namespace table and stays flat.
- The `.test.ks` files adjacent to each stdlib module need their imports updated too.

---

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/data/` | New directory; 10 `.ks` files + 10 `.test.ks` files moved here |
| `stdlib/kestrel/io/` | New directory; `console.ks`, `fs.ks` + `fs.test.ks`, `http.ks` + `http.test.ks` moved here |
| `stdlib/kestrel/sys/` | New directory; `process.ks` + `process.test.ks`, `task.ks` + `task.test.ks`, `runtime.ks` moved here |
| `stdlib/kestrel/dev/` | New directory; `stack.ks` + `stack.test.ks` moved here |
| Old flat files | Removed: `basics.ks`, `char.ks`, `string.ks`, `list.ks`, `dict.ks`, `set.ks`, `tuple.ks`, `option.ks`, `result.ks`, `json.ks`, `console.ks`, `fs.ks`, `http.ks`, `process.ks`, `task.ks`, `runtime.ks`, `stack.ks` (and their `.test.ks` siblings) |
| Import sites | ~74 `.ks` and `.sh` files updated: `stdlib/`, `tests/`, `scripts/run_tests.ks`, `scripts/run-e2e.sh`, root example files |
| `docs/specs/02-stdlib.md` | Section headings renamed from `kestrel:X` to `kestrel:data/X` etc. |
| `docs/specs/07-modules.md` | Namespace table and resolution rules updated |
| No compiler changes | Resolver already handles sub-paths via file-existence fallback (S04-02 done) |

## Tasks

- [x] Create `stdlib/kestrel/data/`, `stdlib/kestrel/io/`, `stdlib/kestrel/sys/`, `stdlib/kestrel/dev/` directories (`.gitkeep` if needed)
- [x] Move and update `stdlib/kestrel/basics.ks` → `stdlib/kestrel/data/basics.ks` (no internal kestrel: imports to update)
- [x] Move and update `stdlib/kestrel/basics.test.ks` → `stdlib/kestrel/data/basics.test.ks` (update `kestrel:basics` → `kestrel:data/basics`, `kestrel:test` stays)
- [x] Move and update `stdlib/kestrel/char.ks` → `stdlib/kestrel/data/char.ks` (update `kestrel:basics` → `kestrel:data/basics`)
- [x] Move and update `stdlib/kestrel/char.test.ks` → `stdlib/kestrel/data/char.test.ks`
- [x] Move and update `stdlib/kestrel/string.ks` → `stdlib/kestrel/data/string.ks` (update internal imports)
- [x] Move and update `stdlib/kestrel/string.test.ks` → `stdlib/kestrel/data/string.test.ks`
- [x] Move and update `stdlib/kestrel/list.ks` → `stdlib/kestrel/data/list.ks` (update internal imports)
- [x] Move and update `stdlib/kestrel/list.test.ks` → `stdlib/kestrel/data/list.test.ks`
- [x] Move and update `stdlib/kestrel/dict.ks` → `stdlib/kestrel/data/dict.ks` (update internal imports)
- [x] Move and update `stdlib/kestrel/dict.test.ks` → `stdlib/kestrel/data/dict.test.ks`
- [x] Move and update `stdlib/kestrel/set.ks` → `stdlib/kestrel/data/set.ks` (update internal imports)
- [x] Move and update `stdlib/kestrel/set.test.ks` → `stdlib/kestrel/data/set.test.ks`
- [x] Move and update `stdlib/kestrel/tuple.ks` → `stdlib/kestrel/data/tuple.ks` (update internal imports)
- [x] Move and update `stdlib/kestrel/tuple.test.ks` → `stdlib/kestrel/data/tuple.test.ks`
- [x] Move and update `stdlib/kestrel/option.ks` → `stdlib/kestrel/data/option.ks` (update internal imports)
- [x] Move and update `stdlib/kestrel/option.test.ks` → `stdlib/kestrel/data/option.test.ks`
- [x] Move and update `stdlib/kestrel/result.ks` → `stdlib/kestrel/data/result.ks` (update internal imports)
- [x] Move and update `stdlib/kestrel/result.test.ks` → `stdlib/kestrel/data/result.test.ks`
- [x] Move and update `stdlib/kestrel/json.ks` → `stdlib/kestrel/data/json.ks` (update internal imports)
- [x] Move and update `stdlib/kestrel/json.test.ks` → `stdlib/kestrel/data/json.test.ks`
- [x] Move and update `stdlib/kestrel/console.ks` → `stdlib/kestrel/io/console.ks` (update internal imports)
- [x] Move and update `stdlib/kestrel/fs.ks` → `stdlib/kestrel/io/fs.ks` (update internal imports)
- [x] Move and update `stdlib/kestrel/fs.test.ks` → `stdlib/kestrel/io/fs.test.ks`
- [x] Move and update `stdlib/kestrel/http.ks` → `stdlib/kestrel/io/http.ks` (update internal imports)
- [x] Move and update `stdlib/kestrel/http.test.ks` → `stdlib/kestrel/io/http.test.ks`
- [x] Move and update `stdlib/kestrel/process.ks` → `stdlib/kestrel/sys/process.ks` (update internal imports)
- [x] Move and update `stdlib/kestrel/process.test.ks` → `stdlib/kestrel/sys/process.test.ks`
- [x] Move and update `stdlib/kestrel/task.ks` → `stdlib/kestrel/sys/task.ks` (update internal imports)
- [x] Move and update `stdlib/kestrel/task.test.ks` → `stdlib/kestrel/sys/task.test.ks`
- [x] Move and update `stdlib/kestrel/runtime.ks` → `stdlib/kestrel/sys/runtime.ks` (no internal imports usually)
- [x] Move and update `stdlib/kestrel/stack.ks` → `stdlib/kestrel/dev/stack.ks` (update `kestrel:list` → `kestrel:data/list`)
- [x] Move and update `stdlib/kestrel/stack.test.ks` → `stdlib/kestrel/dev/stack.test.ks`
- [x] Update all non-stdlib `.ks` files that import the 17 moved modules (bulk sed: replace `"kestrel:X"` → `"kestrel:data/X"` etc. for each mapping)
- [x] Update `stdlib/kestrel/array.ks` internal imports (references `kestrel:list`, `kestrel:option`, etc.)
- [x] Update `stdlib/kestrel/array.test.ks` internal imports
- [x] Update `stdlib/kestrel/test.ks` internal imports (references `kestrel:basics`, `kestrel:console`, `kestrel:list`, `kestrel:stack`, `kestrel:string`, `kestrel:task`)
- [x] Update `stdlib/kestrel/socket.ks` internal imports (if it references moved modules)
- [x] Update `stdlib/kestrel/socket.test.ks` internal imports
- [x] Update `stdlib/kestrel/web.ks` internal imports
- [x] Update `stdlib/kestrel/web.test.ks` internal imports
- [x] Update `scripts/run_tests.ks` imports
- [x] Update `scripts/run-e2e.sh` (one import inside an inline heredoc; replace `kestrel:process` → `kestrel:sys/process`)
- [x] Update root example files: `hello.ks`, `mandelbrot.ks`
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`
- [x] Run `cd runtime/jvm && bash build.sh`
- [x] Run `./scripts/run-e2e.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| E2E positive | `tests/e2e/scenarios/positive/stdlib-new-paths.ks` | Import from both `kestrel:data/string` and `kestrel:io/console`, verify execution |

No new unit tests required for a pure move; existing tests serve as regression guards.

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md` — rename all `## kestrel:X` section headings to `## kestrel:data/X`, `## kestrel:io/X`, `## kestrel:sys/X`, `## kestrel:dev/X` per the E08 namespace table
- [x] `docs/specs/07-modules.md` — add namespace map table showing the restructure; update any examples that use old flat paths

## Build notes

- 2026-04-05: Started implementation. Creating directory structure and moving stdlib files.
- 2026-04-05: Moved 17 stdlib modules to data/*, io/*, sys/*, dev/ with internal import updates. Deleted old flat files. Updated ~74 external files (tests, scripts, examples) via sed bulk replacement. Updated compiler integration tests that embed Kestrel source strings. All 419 compiler tests, 532 Kestrel tests, and all E2E scenarios pass. The `kestrel:array`, `kestrel:socket`, `kestrel:web`, and `kestrel:test` modules stay flat per epic plan (test moves in S08-06).

