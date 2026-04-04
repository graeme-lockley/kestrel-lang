# Epic E07: Incremental Compilation

## Status

Unplanned

## Summary

Currently Kestrel recompiles every imported package on every invocation, regardless of whether the source has changed. As programs grow in size and import depth, total compilation time grows proportionally. This epic introduces incremental compilation: alongside each generated `.class` file the compiler writes a companion metadata file containing the package's exported declarations, and on subsequent compilations it reads that metadata instead of re-parsing and re-type-checking unchanged packages. This makes iterative development fast while preserving correctness for any package whose source has been modified or whose dependencies have changed.

## Stories

(None yet — use plan-epic to decompose, or story-create to add individual stories.)

## Dependencies

- E04 (module resolution and reproducibility) — the module resolver must produce stable, canonical package identities before per-package metadata can be keyed and invalidated correctly.

## Epic Completion Criteria

- Compiling a package that has no changed transitive dependencies does not re-parse or re-type-check those dependencies; it reads their companion metadata files instead.
- Companion metadata files are written alongside generated `.class` files after every successful compilation of a package.
- Metadata files contain the full exported declaration surface (types, functions, ADT constructors, operators) sufficient for the type-checker and code-generator of dependent packages.
- A changed source file (or a changed transitive dependency) causes that package and all packages that transitively depend on it to be recompiled; unchanged unrelated packages are not recompiled.
- The compiler CLI exposes an option (e.g. `--no-cache`) to force a full recompilation.
- All existing compiler tests and E2E tests continue to pass with incremental compilation enabled.
- Incremental compilation is measurably faster than full recompilation for a project with three or more packages whose transitive dependencies are unchanged.

## Implementation Approach

Each successfully compiled package produces a companion file (e.g. `<PackageName>.ksi`) written to the same output directory as its `.class` files. The metadata file is a structured JSON (or binary) document describing the package's exported environment: type aliases, ADT definitions, function signatures, and operator declarations. On a subsequent compilation the resolver checks whether a `.ksi` file exists and whether the source file's modification timestamp (or content hash) is newer than the metadata. If the metadata is up to date the type-checker loads the exported environment directly from the metadata, skipping lexing, parsing, and type inference for that package entirely. If the metadata is stale or absent the package is recompiled normally and a fresh `.ksi` is written.
