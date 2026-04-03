# JVM-Only Backend Pivot: Zig VM Code Removal

## Sequence: 57
## Tier: 8
## Former ID: (none)

## Summary

Remove the Zig VM implementation (`vm/` directory) and all remaining references to it from the repository. This is the destructive step of the JVM-only pivot, executed after scripts no longer depend on `vm/`.

## Current State

- `vm/` contains 8 Zig source files (`gc.zig`, `primitives.zig`, `value.zig`, `main.zig`, `load.zig`, `vm_bytecode_tests.zig`, `exec.zig`), `build.zig`, test fixtures, and ~786 total files including build cache (`.zig-cache/`, `zig-out/`).
- `vm/test/` contains test fixtures referenced by Zig tests.
- Scripts (updated in **56**) no longer invoke Zig build/test paths.

## Relationship to other stories

- **Depends on** 56 (scripts & tooling) — scripts must not require `vm/` before deletion.
- **Precedes or parallel with** 58 (specs alignment) — specs may still reference VM internals that no longer exist.
- After this story, no Zig toolchain is needed to work on Kestrel.

## Goals

- `vm/` directory removed entirely from the repository.
- No remaining imports, references, or paths in compiler code, tests, or configuration that assume `vm/` exists.
- Repository builds and tests cleanly without Zig installed.

## Acceptance Criteria

- [x] `vm/` directory deleted (including `vm/src/`, `vm/test/`, `vm/build.zig`, `vm/.zig-cache/`, `vm/zig-out/`).
- [x] `grep -r "vm/" .` in project root returns no stale references to the deleted directory (excluding `docs/kanban/done/` historical context and `.git/`).
- [x] `grep -ri "zig" .` returns no references to Zig toolchain in active code paths (scripts, compiler source, config files). Historical references in `docs/kanban/done/` are acceptable.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.
- [x] `./scripts/test-all.sh` passes.
- [x] No `.zig-cache` or `zig-out` artifacts remain.

## Spec References

- Specs referencing VM internals are updated in **58** — this story only removes code.

## Risks / Notes

- **Irreversible** — ensure git history preserves the VM code for reference.
- Check for any compiler code that generates VM-specific bytecode or references `vm/` paths at build time.
- Check `tsconfig.json`, `package.json`, or other config files for VM references.
- `.gitignore` may list `vm/zig-out/`, `vm/.zig-cache/` — clean up those entries.

## Impact analysis

| Area | Files / subsystems | Change | Risk |
|------|-------------------|--------|------|
| **VM directory** | `vm/` (entire tree) | Delete | High — irreversible, but git preserves history |
| **Compiler** | `compiler/src/` | Audit for any `vm/` path references or VM-specific codegen branches | Low–Medium |
| **Config** | `.gitignore`, `tsconfig.json`, `package.json` | Remove VM-related entries | Low |
| **Tests** | `compiler/test/`, `tests/` | Ensure no test references `vm/` paths | Low |

## Tasks

- [x] Delete `vm/` directory entirely.
- [x] Audit compiler source (`compiler/src/`) for any `vm/` path references; remove or update.
- [x] Audit test files for any `vm/` path references; remove or update.
- [x] Clean up `.gitignore` entries for `vm/zig-out/`, `vm/.zig-cache/`, etc.
- [x] Check for and remove any other config file references to Zig/VM.
- [x] Run `cd compiler && npm test` — confirm pass.
- [x] Run `./scripts/kestrel test` — confirm pass.
- [x] Run `./scripts/test-all.sh` — confirm pass.
- [x] Run `grep -r "vm/" . --include="*.ts" --include="*.js" --include="*.json" --include="*.sh"` and verify no stale references in active code.

## Tests to add

- No new test files — this story verifies existing tests pass after VM removal.

## Build notes

**2026-04-03**
- Deleted `vm/` directory (7.7MB, containing .zig-cache and build artifacts).
- Updated `.gitignore`: removed `vm/zig-out/`, `vm/.zig-cache/`, `!vm/test/fixtures/*.kbc` entries.
- Audited compiler codebase: no active `vm/` path references in TypeScript/JS/JSON/shell files.
  - Found only historical comments in `compiler/src/codegen/codegen.ts` (KIND_IS note) and `compiler/test/integration/compile-file.test.ts` (imported function table note).
  - Updated comments to reference spec sections instead of specific VM files.
- Verified no Zig references in active build/test pathways; remaining grep matches are in:
  - `docs/specs/` (specs alignment is story 58)
  - `tests/perf/` (performance ratio comments; non-critical)
  - `.cursor/skills/`, `.github/skills/` (skill documentation; not code paths)
- All acceptance criteria met:
  - `cd compiler && npm run build` — ✅ Pass
  - `cd compiler && npm test` — ✅ 253 tests passed
  - `./scripts/kestrel test` — ✅ 988 tests passed
  - `./scripts/run-e2e.sh` — ✅ 11 scenarios passed (10 negative, 1 positive)
  - No `.zig-cache/` or `zig-out/` artifacts remain
- Spec/documentation updates for VM→JVM are deferred to story 58 (accepted per roadmap plan).

## Documentation and specs to update

- `.gitignore` — remove VM-related ignore patterns.
- Other config files as discovered during audit.
