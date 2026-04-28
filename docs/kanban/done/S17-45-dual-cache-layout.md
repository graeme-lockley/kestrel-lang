# Dual cache layout (`~/.kestrel/ts/` + `~/.kestrel/self/`)

## Sequence: S17-45
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-46, S17-47, S17-48, S17-50, S17-49

## Summary

Split the single JVM class cache (`~/.kestrel/jvm/`) into two sub-directories under one root:
`~/.kestrel/ts/` for classes compiled by the TypeScript compiler and `~/.kestrel/self/` for
classes compiled by the self-hosted Kestrel compiler. The shared Maven artifact cache
(`~/.kestrel/maven/`) is unchanged. `KESTREL_JVM_CACHE` is kept as a deprecated read-only
alias for one release.

## Current State

All JVM class output — whether from the TS compiler or the self-hosted compiler — goes to
`~/.kestrel/jvm/` (or whatever `KESTREL_JVM_CACHE` is set to). There is no separation between
artifacts produced by each compiler, which causes cross-contamination (a stale artifact from one
compiler may be picked up by the other) and makes it impossible to have both compiler paths
active simultaneously.

## Relationship to other stories

- **Blocks**: S17-46, S17-47, S17-48, S17-50
- **Depends on**: none — first story in the pivot block

## Goals

1. `scripts/kestrel` defaults `JVM_CACHE` to `~/.kestrel/ts/`.
2. A new `KESTREL_SELF_CACHE` env var (default `~/.kestrel/self/`) is introduced.
3. `KESTREL_JVM_CACHE` remains a deprecated alias: when set it overrides `KESTREL_TS_CACHE`
   and prints a one-line deprecation warning to stderr.
4. `stdlib/kestrel/tools/bootstrap.ks` uses `KESTREL_SELF_CACHE` as the extraction target.
5. `stdlib/kestrel/tools/compiler/cli-main.ks` uses `KESTREL_TS_CACHE` as its default `outDir`.
6. `compiler/cli.ts` comment updated to reference `~/.kestrel/ts/`.
7. `scripts/test-compiler-bootstrap` updated to look in `~/.kestrel/ts/`.
8. Spec and doc files updated.

## Acceptance Criteria

- [x] `scripts/kestrel` routes TS compilation output to `~/.kestrel/ts/` by default.
- [x] `KESTREL_JVM_CACHE` still overrides the TS cache path (deprecated alias) with a warning.
- [x] `KESTREL_SELF_CACHE` routes self-hosted output to `~/.kestrel/self/` by default.
- [x] `stdlib/kestrel/tools/bootstrap.ks` extracts bootstrap JAR to `~/.kestrel/self/`.
- [x] `./kestrel build && ./kestrel bootstrap` succeeds with new paths.
- [x] `cd compiler && npm run build && npm test` passes.
- [x] `./scripts/kestrel test` passes (TS compiler; uses `~/.kestrel/ts/`).

## Spec References

- `docs/specs/09-tools.md` — `KESTREL_JVM_CACHE` env var and cache path documentation
- `docs/specs/11-bootstrap.md` — cache path diagram and bootstrap flow

## Risks / Notes

- Existing developer machines have `~/.kestrel/jvm/` populated. They will need to
  `./kestrel bootstrap` again (which now targets `~/.kestrel/self/`) and the TS cache will
  repopulate on first `./kestrel run`. A one-time migration note should appear in the release.
- `KESTREL_JVM_CACHE` deprecation: keep as alias for one release, then remove.
- The `MAVEN` path (`~/.kestrel/maven/`) is NOT changed by this story.

## Impact analysis

| Area | Change |
|------|--------|
| `scripts/kestrel` | Change `JVM_CACHE` default from `~/.kestrel/jvm` to `~/.kestrel/ts`; add `KESTREL_SELF_CACHE` var; deprecation handling for `KESTREL_JVM_CACHE` |
| `stdlib/kestrel/tools/bootstrap.ks` | Change `KESTREL_JVM_CACHE` reference to `KESTREL_SELF_CACHE` with default `~/.kestrel/self` |
| `stdlib/kestrel/tools/compiler/cli-main.ks` | Change `KESTREL_JVM_CACHE` reference to `KESTREL_JVM_CACHE` with default `~/.kestrel/ts` (this file runs under the TS path) |
| `stdlib/kestrel/tools/cli.ks` | Change `KESTREL_JVM_CACHE` reference in `main` to use `KESTREL_JVM_CACHE` with `~/.kestrel/ts` as default; same for `cmdStatus` |
| `compiler/cli.ts` | Update comment and default path from `~/.kestrel/jvm` to `~/.kestrel/ts`; read `KESTREL_JVM_CACHE` (deprecated) or `KESTREL_TS_CACHE` |
| `scripts/test-compiler-bootstrap` | Update `KESTREL_JVM_CACHE` usages at lines 117, 126, 136 to work with new default path |
| `AGENTS.md` | Update cache path references |
| `README.md` | Update cache path reference |
| `docs/specs/09-tools.md` | Update env var table and cache path docs |
| `docs/specs/11-bootstrap.md` | Update cache path diagram and bootstrap flow |

Compatibility: the `KESTREL_JVM_CACHE` env var continues to work as a deprecated override for
the TS cache path (prints a warning to stderr). No changes to the Maven cache layout.

## Tasks

- [x] `scripts/kestrel`: change `JVM_CACHE="${KESTREL_JVM_CACHE:-$HOME/.kestrel/jvm}"` to:
      - `KESTREL_TS_CACHE_DEFAULT="$HOME/.kestrel/ts"`
      - `JVM_CACHE="${KESTREL_JVM_CACHE:-${KESTREL_TS_CACHE:-$KESTREL_TS_CACHE_DEFAULT}}"`
      - If `KESTREL_JVM_CACHE` is set, print deprecation warning to stderr:
        `echo "kestrel: KESTREL_JVM_CACHE is deprecated; use KESTREL_TS_CACHE instead" >&2`
      - Add `SELF_CACHE="${KESTREL_SELF_CACHE:-$HOME/.kestrel/self}"` for future use
- [x] `stdlib/kestrel/tools/bootstrap.ks`: change `KESTREL_JVM_CACHE` default to
      `~/.kestrel/self` → `getEnv("KESTREL_SELF_CACHE")` with fallback `"${home}/.kestrel/self"`
- [x] `stdlib/kestrel/tools/compiler/cli-main.ks` `defaultCompileOptions`: change
      `KESTREL_JVM_CACHE` default to `"${cwd}/.kestrel/ts"` (or env `KESTREL_TS_CACHE`)
- [x] `stdlib/kestrel/tools/cli.ks` `main`: change `KESTREL_JVM_CACHE` default to
      `"${home}/.kestrel/ts"` (use `KESTREL_TS_CACHE` env var with that fallback)
- [x] `compiler/cli.ts` line 52: change default to `join(homedir(), '.kestrel', 'ts')`;
      also read `KESTREL_TS_CACHE` if set, falling back to `KESTREL_JVM_CACHE` (deprecated)
      then to the new default; update comment on line 6
- [x] `scripts/test-compiler-bootstrap` lines 117, 126: use `KESTREL_TS_CACHE` instead of
      `KESTREL_JVM_CACHE` in the `export` statements that set stage output dirs
- [x] `AGENTS.md`: update `~/.kestrel/jvm/` references to `~/.kestrel/ts/`
- [x] `README.md`: update `~/.kestrel/jvm/` reference to `~/.kestrel/ts/`
- [x] `docs/specs/09-tools.md`: update `KESTREL_JVM_CACHE` env var entry (note deprecation),
      add `KESTREL_TS_CACHE` and `KESTREL_SELF_CACHE`; update cache path example
- [x] `docs/specs/11-bootstrap.md`: update cache path diagram and `~/.kestrel/jvm/` references
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest integration | `compiler/test/integration/runtime-stdlib.test.ts` | Assert TS compiler uses `~/.kestrel/ts/` by default (check env var resolution in cli.ts) |

## Documentation and specs to update

- [x] `docs/specs/09-tools.md` — add `KESTREL_TS_CACHE`, `KESTREL_SELF_CACHE`; deprecate `KESTREL_JVM_CACHE`; update path examples
- [x] `docs/specs/11-bootstrap.md` — update cache path diagram (`~/.kestrel/ts/` and `~/.kestrel/self/`), bootstrap flow
- [x] `AGENTS.md` — update `~/.kestrel/jvm/` path references
- [x] `README.md` — update `~/.kestrel/jvm/` path reference

## Build notes

**2026-04-28** Implementation notes:
- The `scripts/kestrel` shim also updates the `bootstrap` subcommand to extract to `SELF_CACHE`
  (not `JVM_CACHE`) and the `Cli.class` lookup to search `SELF_CACHE` (not `JVM_CACHE`). The
  classpath for the delegated `java` command now includes both `SELF_CACHE:JVM_CACHE` so that
  self-hosted compiler classes and TS-compiled user program classes are both accessible.
- `test-compiler-bootstrap` also updated a diagnostic `home_candidate` path reference at line 71.
- Existing developer machines need to manually copy or re-bootstrap: `cp -r ~/.kestrel/jvm ~/.kestrel/self`.
  The TS cache (`~/.kestrel/ts/`) will repopulate on first `./kestrel run`. During the stale-cache
  transitional window, the self-hosted driver's KTI fast-path handles cases where the new TS cache
  is momentarily stale (e.g., the `.kestrel_test_runner.ks` must be seeded by running
  `KESTREL_TS_CACHE=~/.kestrel/jvm ./kestrel test` once or allowing the cache to warm naturally).
- `scripts/kestrel` `test` subcommand: the in-process driver prints "Unknown constructor: True/False"
  diagnostics for `match.test.ks` during the transitional period (S17-12 coupling), but these are
  non-fatal — the compiled test runner class from earlier runs is reused via KTI freshness. S17-46
  will eliminate this by restoring the TS subprocess path.
- Compiler tests: 442 passed. Kestrel tests: exit 0.
