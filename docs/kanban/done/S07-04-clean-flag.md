# `--clean` Flag for `kestrel build` and `kestrel run`

## Sequence: S07-04
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E07 Incremental Compilation](../epics/unplanned/E07-incremental-compilation.md)
- Companion stories: S07-01 (spec), S07-02 (writer), S07-03 (reader)

## Summary

Users need an explicit escape hatch to discard all incremental `.kti` cache files and force a full recompile from source. Add a `--clean` flag to both `kestrel build` and `kestrel run` (in `compiler/cli.ts` and `scripts/kestrel`). `--clean` deletes every `.kti` file in the configured class output directory before compilation begins, causing S07-03's freshness router to always fall through to a full recompile for that invocation. The flag is orthogonal to `--refresh` (URL source re-download); `--clean --refresh` produces a fully-from-scratch build.

## Current State

- `compiler/cli.ts` exposes `--refresh` and `--allow-http` but no `--clean`.
- `scripts/kestrel` `cmd_build` and `cmd_run` pass through flags to the compiler CLI but have no awareness of `--clean` themselves (the deletion is done inside the CLI before compile starts).
- S07-03 makes `.kti` freshness routing the default path; `--clean` is the opt-out.

## Relationship to other stories

- **Depends on S07-03**: `--clean` is only meaningful once S07-03 adds the freshness router. Without a reader, there are no `.kti` files to honour, so clean-ing them is a no-op.
- Semantically independent of S07-01 and S07-02 but practically requires them to be useful.

## Goals

- `kestrel build --clean` removes all `.kti` files in the output dir, then compiles normally.
- `kestrel run --clean` removes all `.kti` files in the output dir, then compiles and runs.
- `--clean` is documented in `./kestrel help` output and in `docs/specs/09-tools.md`.
- `--clean --refresh` combines cleanly: first delete kti files, then compile from scratch re-downloading URL sources.

## Acceptance Criteria

- `compiler/cli.ts`: `--clean` flag accepted; before calling any `compileOne`, deletes every `*.kti` file in the output directory (`-o` / `outputDir`) if set. If no output dir is configured, `--clean` is silently ignored.
- `scripts/kestrel`: `cmd_build` and `cmd_run` pass `--clean` through to the compiler CLI when the user supplies it.
- `./kestrel build --help` and `./kestrel run --help` document `--clean`.
- Unit test (compiler): calling compile with `--clean` on a directory containing pre-placed `.kti` files results in those files being deleted before compilation and new ones being written after.
- Manual E2E check: `./kestrel build --clean` on multi-package project produces same output as first ever build (i.e., identical `.class` files).
- `--clean` without `-o` (no output dir) exits cleanly with no error.
- `docs/specs/09-tools.md` updated to document `--clean` under the `build` and `run` commands.

## Spec References

- `docs/specs/09-tools.md` — CLI tool reference for `build` and `run` commands
- `docs/specs/07-modules.md §5` — incremental compilation overview (reader spec added by S07-01)

## Risks / Notes

- **Deletion scope**: only delete `*.kti` in the top-level output dir, not recursively, to avoid accidental deletion in nested project structures. Revisit if multi-package projects place `.kti` files in sub-dirs.
- **Race condition**: on `kestrel run --clean`, after deleting `.kti` files another concurrent invocation might not find them. This is an existing risk with any file-system cache and is acceptable.
- **`--clean` vs `--no-cache`**: the flag is named `--clean` (not `--no-cache`) because "clean" is the common metaphor in build tools (e.g., `make clean`, `gradle clean`). `--no-cache` would imply that no `.kti` files are written either; `--clean` only discards old ones and still writes fresh ones.
- **`kestrel run` freshness bypass**: `scripts/kestrel` already skips the compiler entirely for unchanged entry points via the shell-level mtime check (`needs_compile_jvm`). When `--clean` is passed, this skip must be suppressed (otherwise `--clean` would be silently ignored). Update `needs_compile_jvm` or bypass it when `--clean` is in the args.

## Impact Analysis

### `compiler/cli.ts`
- Parse `--clean` boolean flag from argv.
- When set: before calling `compileFileJvm`, recursively find and delete all `*.kti` files under `outputPath`. If `outputPath` not configured (no `-o` and no `KESTREL_JVM_CACHE`), silently skip.
- Update usage comment at top of file.

### `compiler/src/compile-file-jvm.ts`
- No changes needed; `--clean` clears the file system before `compileFileJvm` is called, so the freshness router naturally falls through to a full compile (no `.kti` files to read).

### `scripts/kestrel`
- `run_usage()`: add `--clean` flag to usage text.
- `cmd_build`: add `--clean)` case in the flag-parsing `while` loop; set `clean_flag="--clean"`; pass `$clean_flag` to the compiler CLI.
- `cmd_run`: add `--clean)` case; set `clean_flag="--clean"`; when `clean_flag` is non-empty, bypass `needs_compile_jvm` (force compilation); pass `$clean_flag` to the compiler CLI.

### `docs/specs/09-tools.md`
- §2.1 (run): add `--clean` to usage line and bullet list.
- §2.3 (build): add `--clean` to usage line and bullet list.

## Tasks

- [x] 1. `compiler/cli.ts`: parse `--clean`; add recursive `deleteKtiFiles` helper; call it before `compileFileJvm` when set; update usage comment.
- [x] 2. `scripts/kestrel` `cmd_build`: add `--clean` case; set `clean_flag`; pass to compiler CLI.
- [x] 3. `scripts/kestrel` `cmd_run`: add `--clean` case; set `clean_flag`; bypass `needs_compile_jvm` when `--clean`; pass to compiler CLI.
- [x] 4. `scripts/kestrel` `run_usage`: document `--clean`.
- [x] 5. `docs/specs/09-tools.md`: document `--clean` in §2.1 run and §2.3 build.
- [x] 6. Add integration test in `compiler/test/integration/` confirming that `--clean` deletes existing `.kti` files from the output dir.

## Tests to Add

- `compiler/test/integration/kti-clean.test.ts` (new):
  - Test: "clean deletes existing `.kti` files before compilation" — write a stale `.kti` file with wrong hash into the class output dir, call `compileFileJvm` after the CLI-level deletion (simulate by calling the helper directly or by invoking the CLI subprocess), verify the stale file is gone and a fresh one is written.
  - In practice, the cleanest approach: extract the deletion logic into a helper `deleteKtiFilesInDir(dir: string)` exported from a small utility or inlined in `cli.ts`. For integration tests, we can directly test the end-to-end CLI behavior by spawning a subprocess, or test `compileFileJvm` + manual pre-deletion as two separate steps.
  - Simplest: test via CLI subprocess (`node dist/cli.js ... --clean`) using `execSync`.

## Documentation and Specs to Update

- `docs/specs/09-tools.md` §2.1 (run) — add `--clean` to usage + bullet
- `docs/specs/09-tools.md` §2.3 (build) — add `--clean` to usage + bullet
- `docs/specs/kti-format.md` — no changes needed (clean is a CLI concern)

## Build notes

- 2025-07-16: Implemented. `deleteKtiFiles` is a recursive helper in `cli.ts` (uses `readdirSync`/`statSync`/`unlinkSync`); it is called before `compileFileJvm` when `--clean` is set. Deletion is recursive because `.kti` files live in path-mirrored subdirectories of the class output dir (e.g. `~/.kestrel/jvm/Users/.../Foo.kti`); the story note saying "not recursively" was written before the full path structure was understood.
- `scripts/kestrel` `cmd_run` bypass: the shell-level `needs_compile_jvm` mtime check is bypassed by replacing `if needs_compile_jvm ...` with `if [ -n "$clean_flag" ] || needs_compile_jvm ...`, so `--clean` always forces the compiler to run.
- 419 tests pass (30 files).
