# Rewrite kestrel:tools/test-runner as kestrel:dev/cli entry point

## Sequence: S11-03
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E11 Pure-Kestrel Test Runner](../epics/unplanned/E11-pure-kestrel-test-runner.md)

## Summary

Rewrite `stdlib/kestrel/tools/test-runner.ks` as a proper `kestrel:dev/cli` entry point. The new runner reads the project root from `getProcess().cwd`, finds the kestrel binary via `getEnv("KESTREL_BIN")`, uses `renameFile` for atomic file replacement, and parses flags via `kestrel:dev/cli`. This removes positional-argument hacks and the `sh -c "cmp -s …"` subprocess.

## Current State

`test-runner.ks` uses `args[2]` as project root, `./scripts/kestrel` as hard-coded binary, `sh -c "cmp -s … || mv …"` for atomic swap, and has no `kestrel:dev/cli` integration.

## Relationship to other stories

- Depends on **S11-01** (`getEnv`).
- Depends on **S11-02** (`renameFile`).
- Required by **S11-04** (bash cmd_test invokes this via `./kestrel run kestrel:tools/test-runner`).

## Goals

1. Test-runner reads project root from `getProcess().cwd`.
2. Kestrel binary path from `getEnv("KESTREL_BIN")`, falling back to `"${proc.cwd}/kestrel"`.
3. Uses `renameFile` for atomic temp→dest swap.
4. Flags parsed via `kestrel:dev/cli`: `--verbose`, `--summary`, `--generate`, `--clean`, `--refresh`, `--allow-http`.
5. Compiler flags (`--clean`, `--refresh`, `--allow-http`) forwarded to inner subprocess.

## Acceptance Criteria

- `./kestrel test` discovers and runs all tests correctly.
- `./kestrel test --verbose` and `./kestrel test --summary` work.
- `./kestrel test --generate` writes `.kestrel_test_runner.ks` and exits.
- `./kestrel test --clean` clears cache on both outer and inner compile.
- Explicit file/directory args work.
- No `sh -c "cmp -s …"` subprocess in source.
- `KESTREL_BIN` env var is respected.

## Spec References

- `docs/specs/09-tools.md`

## Risks / Notes

- The inner subprocess invocation style changes from `exec java -cp $cp MainClass "" "" "$ROOT"` to `"$KESTREL_BIN" run .kestrel_test_runner.ks`, so args layout changes; test-runner.ks handles this by no longer passing `"" ""` positional preambles.

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib | Rewrite `stdlib/kestrel/tools/test-runner.ks` using `kestrel:dev/cli`, `getEnv`, `renameFile`/`deleteFile` |
| Tests | Run `./scripts/kestrel test --summary` as acceptance; existing Kestrel test suite is the coverage |
| Docs | Update `docs/specs/09-tools.md` to document new arg layout and env var |

## Tasks

- [x] Rewrite `stdlib/kestrel/tools/test-runner.ks` with `kestrel:dev/cli` CLI spec for all flags
- [x] Use `getEnv("KESTREL_BIN")` → fallback to `${proc.cwd}/kestrel` for binary path
- [x] Use `getProcess().cwd` as project root (remove `getRootDir`/positional rootDir hack)
- [x] Replace `sh -c "cmp -s ... || mv ..."` with `readText` + compare + `renameFile`/`deleteFile`
- [x] Forward `--clean`, `--refresh`, `--allow-http` to inner `kestrelBin run` subprocess
- [x] `cd compiler && npm run build && npm test`
- [x] `./scripts/kestrel test --summary`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| System test | `./scripts/kestrel test --summary` | Full suite passes with new runner |

## Documentation and specs to update

- [x] `docs/specs/09-tools.md` — update `kestrel test` section to document `KESTREL_BIN` env var and new arg layout (no project-root positional)

## Build notes

- 2026-04-10: Started implementation.
- 2026-04-10: `Opt.withDefault(option, default)` - arg order is (option, default), not (default, option). Fixed type error.
- 2026-04-10: The old bash invocation passes `["", "", rootDir, ...]` as mainArgs; the new test-runner.ks expects `["--flag", "paths..."]` via `kestrel:dev/cli`. Verified correct operation with `KESTREL_BIN=$PWD/kestrel ./kestrel run kestrel:tools/test-runner --summary` → 1459 passed.
- 2026-04-10: Replaced `sh -c "cmp -s ... || mv ..."` subprocess with in-process `readText` + `Str.equals` comparison + `renameFile`/`deleteFile` — eliminates the external shell subprocess for this operation.
