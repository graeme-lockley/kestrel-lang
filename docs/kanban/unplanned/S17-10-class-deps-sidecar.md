# .class.deps sidecar file writing

## Sequence: S17-10
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01, S17-02, S17-03, S17-04, S17-05, S17-06, S17-07, S17-08, S17-09, S17-11, S17-12, S17-13

## Summary

After compiling a module, write `<ClassName>.class.deps` listing the absolute paths of all
direct and transitive source dependencies. This file is used by `cli.ks` for mtime-based
staleness checks (legacy freshness path). Format: one absolute path per line.

## Current State

After S17-09, the driver compiles multi-module programs with URL support. But no `.class.deps`
sidecar files are written. The Bash shim and legacy CLI depend on these files to determine
whether to re-run the Kestrel compiler.

## Relationship to other stories

- **Depends on**: S17-09 (full graph with URL deps available)
- **Blocks**: S17-12 (wire cli.ks; cli uses .class.deps for staleness)

## Goals

1. After writing `.class` files for a module, also write a `<ClassName>.class.deps` file to
   `outDir` containing the absolute paths of all direct and transitive source dependencies of
   that module (in the order they appear in the topological sort).
2. Include the entry file itself in the deps list.
3. Format: one absolute path per line, UTF-8 encoded, newline-terminated.

## Acceptance Criteria

- [ ] `<ClassName>.class.deps` is written to `outDir` after compilation.
- [ ] The file contains the absolute paths of all transitive source deps (including stdlib).
- [ ] `driver.test.ks` verifies the sidecar file content for a two-module program.
- [ ] `cd compiler && npm run build && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/11-bootstrap.md` — class.deps sidecar use by CLI

## Risks / Notes

- Only write `.class.deps` for modules that were actually compiled (not for fresh/skipped
  modules where the existing sidecar is still valid).
- Absolute path canonicalization: ensure symlinks are resolved consistently.
