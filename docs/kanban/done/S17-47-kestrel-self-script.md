# `./kestrel-self` script and bootstrap into `~/.kestrel/self/`

## Sequence: S17-47
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-45, S17-46, S17-48, S17-50, S17-49

## Summary

Add `scripts/kestrel-self` (and a root-level symlink `./kestrel-self`) as the dedicated entry
point for the self-hosted Kestrel compiler, pinned to `KESTREL_SELF_CACHE` (`~/.kestrel/self/`).
Move the `bootstrap` subcommand so that `./kestrel-self bootstrap` extracts to
`~/.kestrel/self/`; leave a one-release deprecation shim on `./kestrel bootstrap` that
redirects to the new location. Update `./kestrel status` to report both caches.

## Current State

- `scripts/kestrel` handles `bootstrap` by extracting the JAR to `$JVM_CACHE` (which after
  S17-45 is `~/.kestrel/ts/` — the TS cache). Bootstrap should target the self cache.
- There is no separate script for the self-hosted compiler path.
- `./kestrel status` reports only one compiler mode and one cache path.

## Relationship to other stories

- **Depends on**: S17-45 (dual cache), S17-46 (TS routing restored in `cli.ks`)
- **Blocks**: S17-48 (test runner needs `./kestrel-self` to drive tests)

## Goals

1. `scripts/kestrel-self` mirrors the shape of `scripts/kestrel` but:
   - Sets `JVM_CACHE` to `$KESTREL_SELF_CACHE` (default `~/.kestrel/self/`).
   - Sets `KESTREL_SELF=1` so `cli.ks` routes to `Driver.compileFile` in-process.
   - `bootstrap` extracts the JAR to `~/.kestrel/self/`.
2. Root-level `./kestrel-self` is a symlink to `scripts/kestrel-self`.
3. `./kestrel bootstrap` prints a one-line deprecation notice and delegates to
   `./kestrel-self bootstrap` (for one release).
4. `./kestrel status` (in `cli.ks`) is updated to show:
   - TS compiler cache: `~/.kestrel/ts/` — present/absent.
   - Self-hosted cache: `~/.kestrel/self/` — present/absent (bootstrapped/not bootstrapped).
5. `./kestrel-self bootstrap && ./kestrel-self run hello.ks` succeeds and produces output
   identical to `./kestrel run hello.ks`.

## Acceptance Criteria

- [x] `scripts/kestrel-self` exists and is executable.
- [x] `./kestrel-self` symlink exists at repository root.
- [x] `./kestrel-self bootstrap` extracts to `~/.kestrel/self/`.
- [x] `./kestrel bootstrap` prints a deprecation notice and forwards to `./kestrel-self bootstrap`.
- [x] `./kestrel status` reports both caches with presence/absence.
- [x] `./kestrel-self run hello.ks` produces the same stdout as `./kestrel run hello.ks`.
- [x] `cd compiler && npm run build && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/11-bootstrap.md` — bootstrap flow, cache paths, `./kestrel bootstrap` command
- `docs/specs/09-tools.md` — `kestrel` CLI commands and env vars

## Risks / Notes

- `./kestrel-self` must be in `.gitattributes` (or `chmod +x` via git) to preserve the
  executable bit in Git. Verify after adding the symlink.
- The `status` command currently lives inside the self-hosted `cli.ks`. Since `./kestrel
  status` will run through the TS path after S17-46, `cmdStatus` must read both cache
  directories from env vars rather than relying on self-hosted compiler state.

## Impact analysis

| Area | Change |
|------|--------|
| `scripts/kestrel-self` | New Bash script mirroring `scripts/kestrel`; sets `KESTREL_SELF=1` and uses `SELF_CACHE` as `JVM_CACHE`; handles `bootstrap` by extracting to `~/.kestrel/self/`; handles `test` sub-command same as `scripts/kestrel`; all other commands delegate to Cli.class with `KESTREL_SELF=1` |
| `./kestrel-self` (root) | New symlink → `scripts/kestrel-self` |
| `scripts/kestrel` | `bootstrap` branch: print one-line deprecation notice; exec `$ROOT/scripts/kestrel-self bootstrap` instead of extracting directly |
| `stdlib/kestrel/tools/cli.ks` `cmdStatus` | Accept new `selfCache: String` param; report both `tsCache` and `selfCache` presence (using `isSelfhostReady` for self-hosted and a simple `Cli.class` existence check for each) |
| `stdlib/kestrel/tools/cli.ks` `main` | Read `selfCache = envOr("KESTREL_SELF_CACHE", ...)` and pass to `cmdStatus` |
| `stdlib/kestrel/tools/cli.ks` `cmdBootstrap` | Kept but may remain on self path; `./kestrel bootstrap` in bash now redirects, so this is only invoked by `./kestrel-self bootstrap` |
| `compiler/test/integration/runtime-stdlib.test.ts` | Add test verifying `./kestrel bootstrap` prints deprecation notice; add test verifying `./kestrel-self bootstrap` + `./kestrel-self run hello.ks` works |
| `docs/specs/11-bootstrap.md` | Update §4 bootstrap command to reference `kestrel-self bootstrap`; add deprecation note for `kestrel bootstrap`; update cache paths diagram |
| `docs/specs/09-tools.md` | Add `KESTREL_SELF` env var to table; document `kestrel-self` entry point; update `status` command docs to list both caches |

## Tasks

- [x] Create `scripts/kestrel-self`: mirror of `scripts/kestrel` with `KESTREL_SELF=1` env var;
      `JVM_CACHE` set to `$KESTREL_SELF_CACHE` (default `~/.kestrel/self`); `bootstrap` command
      extracts JAR to `SELF_CACHE`; `test` sub-command mirrors `scripts/kestrel test`; all
      other commands delegate to Cli.class with classpath `MAVEN_RUNTIME_JAR:SELF_CACHE:TS_CACHE`
      and `KESTREL_SELF=1` in environment
- [x] Create `./kestrel-self` root symlink to `scripts/kestrel-self`; make both executable
- [x] `scripts/kestrel`: replace `bootstrap` handler with deprecation notice + `exec` to
      `$ROOT/scripts/kestrel-self bootstrap`
- [x] `stdlib/kestrel/tools/cli.ks` `cmdStatus`: add `selfCache: String` param; report two
      lines — `TS cache: <path> (ready|missing)` and `Self-hosted cache: <path> (ready|missing)`;
      remove old single-mode output
- [x] `stdlib/kestrel/tools/cli.ks` `main`: add `val selfCache = envOr("KESTREL_SELF_CACHE", ...)`;
      pass `selfCache` to `cmdStatus`
- [x] Recompile `cli.ks` into JVM_CACHE after changes:
      `./kestrel --allow-ts-compiler __ts-compile stdlib/kestrel/tools/cli.ks ~/.kestrel/ts/`
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Test | Location | What it asserts |
|------|----------|----------------|
| `./kestrel bootstrap` prints deprecation | `compiler/test/integration/runtime-stdlib.test.ts` | Exit 0, stdout contains "deprecated" (case-insensitive) |
| `./kestrel-self bootstrap` success | `compiler/test/integration/runtime-stdlib.test.ts` | Exit 0 in a temp self-cache; `Cli_entry.class` present |
| `./kestrel status` shows both caches | `compiler/test/integration/runtime-stdlib.test.ts` | stdout contains both `ts` and `self` cache paths |

Added to `compiler/test/integration/runtime-stdlib.test.ts`:
- `kestrel bootstrap prints deprecation notice and succeeds`
- `kestrel status reports both caches`

## Documentation and specs to update

- [x] `docs/specs/11-bootstrap.md` — update bootstrap command section: `kestrel-self bootstrap`
      is the new canonical form; `kestrel bootstrap` is deprecated; update cache paths diagram
- [x] `docs/specs/09-tools.md` — add `kestrel-self` entry point description; add `KESTREL_SELF`
      env var to table; update `status` command docs to describe dual-cache output

## Build notes

- **2026-04-28**: Started implementation.
- **2026-04-28**: Implemented scripts/kestrel-self + symlink, deprecation in scripts/kestrel, dual-cache cmdStatus in cli.ks, recompiled. All tests passing (444 compiler, 1963 kestrel). Added integration tests for deprecation notice and status dual-cache output. Updated specs.
