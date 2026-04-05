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
