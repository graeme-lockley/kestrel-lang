# Epic E07: Incremental Compilation

## Status

Unplanned

## Summary

The `.kti` (types file) format is fully specified in `docs/specs/07-modules.md §5` and was implemented for the old VM-based compiler pipeline. The JVM compiler (`compile-file-jvm.ts`) does not use it: every invocation re-parses and re-typechecks all transitive dependencies from source. As programs grow in import depth, total compilation time grows proportionally. This epic wires the existing `.kti` format into the JVM compilation pipeline so that unchanged packages are skipped at the compiler level, making iterative development fast while preserving correctness for any package whose source has changed.

## Current State

- **`.kti` format** is fully specified in `docs/specs/07-modules.md §5` (version 3). It carries exported functions, vars, ADT constructors, and type aliases — everything a dependent package needs to typecheck and codegen against a dependency without re-parsing its source. Version-rejection on load is required by spec and already spec'd.
- **Old VM compiler**: `.kti` was implemented and stories are in `docs/kanban/done/` (30-types-file-full-spec07, 31-export-var-getter-setter, etc.). No `types-file.ts` or equivalent survives in the current compiler source; the JVM pivot did not carry the implementation forward.
- **JVM compiler** (`compile-file-jvm.ts`): does not read or write `.kti` files. Every compiler invocation recursively re-parses and re-typechecks all dependencies from source. An in-process `cache` Map avoids re-compiling the same file twice within a single invocation, but nothing persists between runs.
- **Shell-level skip** (`needs_compile_jvm` in `scripts/kestrel`): `kestrel run` skips invoking the compiler entirely if the entry `.class` is newer than all source deps (mtime-based). `kestrel build` always invokes the compiler.
- **`--refresh`** forces re-download of URL-fetched source files into `~/.kestrel/cache/`; it has no effect on whether packages are recompiled from source.

## Goals

- Make iterative development fast: unchanged transitive dependencies are skipped at the compiler level, not just at the shell level.
- Preserve correctness: any change to a source file or its transitive dependencies triggers recompilation of that package and all dependents.
- Reuse the existing `.kti` spec rather than invent a new format.
- Compose cleanly with existing CLI flags: `--refresh` (URL re-download) and `--clean` (force full recompilation) remain orthogonal and combinable.

## Stories

(None yet — use plan-epic to decompose, or story-create to add individual stories.)

## Dependencies

- E04 (module resolution and reproducibility) — the module resolver must produce stable, canonical package identities before per-package metadata can be keyed and invalidated correctly. **E04 is complete.**

## Epic Completion Criteria

- `compile-file-jvm.ts` writes a `.kti` file alongside each successfully compiled package's `.class` output.
- On a subsequent compilation, if a package's `.kti` is present and its embedded source hash matches the current source content, `compile-file-jvm.ts` loads the exported environment from the `.kti` instead of re-parsing and re-typechecking that package.
- A changed source file (or a changed transitive dependency) causes that package and all packages that transitively depend on it to be recompiled; unchanged unrelated packages are not recompiled.
- `.kti` files produced by an incompatible compiler version are rejected (format version mismatch) and the package is recompiled from source; no silent misread.
- `kestrel build --clean <script>` deletes all `.kti` files in the output directory before compilation, forcing a full rebuild from source. It is composable with `--refresh` (`kestrel build --clean --refresh`) for a fully-from-scratch build including URL re-download.
- The three-layer freshness model is consistent:
  - **Shell level** (`kestrel run` only): skip compiler invocation entirely if the entry `.class` is up to date (mtime vs. source deps).
  - **Compiler level** (all invocations): skip re-parse/re-typecheck of deps whose `.kti` hash is up to date. Bypassed by `--clean`.
  - **URL cache level** (all invocations): use cached remote source; re-download with `--refresh`.
- All existing compiler tests and E2E tests continue to pass with incremental compilation enabled.
- Incremental compilation is measurably faster than full recompilation for a project with three or more packages whose transitive dependencies are unchanged.

## Spec References

- `docs/specs/07-modules.md §5` — `.kti` format (current spec, version 3); this is the authoritative definition. Needs a new subsection documenting the freshness/invalidation algorithm and the `sourceHash` field to be added to the format.
- `docs/specs/09-tools.md` — CLI flag reference; `--clean` must be added to `kestrel build` and its interaction with `--refresh` documented.

## Risks / Notes

- **`--refresh` vs `--clean`**: these are distinct flags covering different caches. `--refresh` re-downloads URL source files; `--clean` discards `.kti` metadata. Both can be combined. `--clean` is chosen over `--no-cache` to align with build-tool convention (`make clean`, `gradle clean`) and to reflect that it deletes stale files rather than merely bypassing them.
- **Invalidation correctness**: mtime is unreliable in CI and on coarse-timestamp filesystems. Prefer SHA-256 of source content as the freshness key; embed it in the `.kti` as a new `sourceHash` field. The current spec does not include `sourceHash` — adding it is a minor version bump (version 4).
- **Transitive invalidation**: a changed dep must invalidate all packages that directly or transitively depend on it. The simplest correct approach is to embed the hashes of all direct dependencies' `.kti` files in the dependent's own `.kti`; a mismatch triggers recompilation.
- **stdlib packages**: stdlib `.ks` files compile to a shared output dir. `.kti` placement for stdlib (alongside `.class` files vs a separate dir) must be decided before implementation.
- **`.kti` writer in the JVM pipeline**: the old VM implementation no longer exists in `compiler/src/`. The writer must be re-implemented (or extracted from done-story context) to match spec version 4.

## Implementation Approach

`compile-file-jvm.ts` is extended to operate in two modes per dependency:

1. **Cache hit**: if `<dep>.kti` exists, its `version` matches the current compiler's supported version, and its `sourceHash` matches `SHA-256(source)` and all declared dep hashes match their own `.kti` files, load the exported environment (functions, type aliases, constructors) directly from the `.kti` and skip lexing, parsing, and type inference for that package.
2. **Cache miss / stale**: compile the package normally (existing path), then write a `.kti` alongside its `.class` output containing the version, `sourceHash`, dep hashes, and the full exported environment.

`kestrel build --clean` is added to the CLI: it deletes all `.kti` files in the output directory before invoking the compiler, restoring full-recompile behaviour without removing `.class` output.
