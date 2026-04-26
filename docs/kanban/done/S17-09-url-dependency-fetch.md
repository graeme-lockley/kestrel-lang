# URL dependency fetch integration

## Sequence: S17-09
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01, S17-02, S17-03, S17-04, S17-05, S17-06, S17-07, S17-08, S17-10, S17-11, S17-12, S17-13

## Summary

For `https://` (and optionally `http://` with `--allow-http`) specifiers, call
`Resolve.fetchUrl` to populate the URL cache before attempting to resolve the path. Wire
`--refresh` flag to force re-fetch. Verify cached-hit path skips the network.

## Current State

After S17-08, the driver handles local and stdlib dependencies. URL imports are resolved to cache
paths by `Resolve.resolveSpecifier` but `Resolve.fetchUrl` is never called — so if the URL cache
file doesn't already exist, compilation fails with a missing-file error.

## Relationship to other stories

- **Depends on**: S17-08 (multi-module graph compilation)
- **Blocks**: S17-10 (class.deps sidecars include URL dep paths)

## Goals

1. When a dependency specifier starts with `https://` (or `http://` if `allowHttp` is true),
   call `Resolve.fetchUrl(url, opts.cacheRoot, opts.allowHttp)` to ensure the cached `.ks` file
   exists.
2. If the cache file already exists and `refresh` is false, skip the network fetch.
3. If `refresh` is true, force re-fetch even if the cache file exists.
4. Propagate fetch errors as `ok=False` with a diagnostic.

## Acceptance Criteria

- [x] A URL import resolves and compiles when the cache file is present.
- [x] A URL import where `allowHttp=False` but the URL is `http://` returns `ok=False`.
- [x] Cache-hit path skips the network (no fetch call when file exists and `refresh=False`).
- [x] `driver.test.ks` verifies the cache-hit and http-disallowed paths.
- [x] `cd compiler && npm run build && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — URL imports and cache

## Risks / Notes

- `Resolve.fetchUrl` in the current Kestrel implementation is a stub that returns the cache path
  without actually fetching. Real HTTP fetch requires a JVM primitive (`kestrel:io/http` or
  equivalent). For now, the stub is acceptable — the important thing is the wiring.
- The `refresh` flag needs to be added to `CompileOptions` if not already present.

## Impact analysis

- **`stdlib/kestrel/tools/compiler/driver.ks`** — add `refresh: Bool` to `CompileOptions`; add
  `ensureUrlDep` / `ensureUrlDeps` helpers; call `ensureUrlDeps` in `compileGraph` after
  `uniqueDependencyPaths` resolves the dep list.
- **`stdlib/kestrel/tools/compiler/cli-main.ks`** — add `refresh = False` to `defaultCompileOptions`.
- **`stdlib/kestrel/tools/compiler/driver.test.ks`** — extend `defaultOpts` to include `refresh = False`; add new async test group for URL fetch paths.
- **`docs/specs/07-modules.md`** — document URL dep fetch wiring, `refresh` flag, and cache-hit behaviour.

No compiler, JVM runtime, or Resolve changes are needed — `Resolve.fetchUrl` and `Fs.fileExists`
are already available.

## Tasks

- [x] Add `refresh: Bool` to `CompileOptions` record in `driver.ks`
- [x] Add `ensureUrlDep` helper: given a dep, if URL spec call `Resolve.fetchUrl` (honouring `refresh` and `Fs.fileExists`); return `None` on success, `Some(CompileResult)` on failure
- [x] Add `ensureUrlDeps` helper: iterate deps list, calling `ensureUrlDep` for each; short-circuit on first error
- [x] Call `ensureUrlDeps` in `compileGraph` after `uniqueDependencyPaths`, before `compileDepsInOrder`
- [x] Add `refresh = False` to `defaultCompileOptions` in `cli-main.ks`
- [x] Update `defaultOpts` in `driver.test.ks` to include `refresh = False`
- [x] Add test group "URL fetch — cache hit skips fetch" (create cache file, compile — succeeds)
- [x] Add test group "URL fetch — http disallowed returns ok=False"
- [x] Add test group "URL fetch — refresh=True calls fetchUrl even when cache exists"
- [x] Update `docs/specs/07-modules.md` with URL dep fetch wiring and `refresh` flag
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./kestrel test`

## Tests to add

In `stdlib/kestrel/tools/compiler/driver.test.ks`:

- **"URL fetch — cache hit"**: write a valid `.ks` file into the cache path for a URL spec
  (`https://example.com/lib.ks` → `urlCachePath`), write an entry module that imports it, compile
  with `refresh=False`. Assert `ok=True`.
- **"URL fetch — http disallowed"**: write an entry module that imports `http://example.com/lib.ks`,
  compile with `allowHttp=False`. Assert `ok=False`, diagnostic present.
- **"URL fetch — refresh forces fetch"**: create cache file, compile once (`ok=True`), then compile
  again with `refresh=True`. Assert second compile also returns `ok=True` (stub always succeeds on
  https URL). Demonstrates refresh path is invoked without error.

## Documentation and specs to update

- [x] `docs/specs/07-modules.md` — URL dep fetch wiring, `refresh` flag, and cache-hit skip behaviour

## Build notes

- 2026-04-26: Started implementation.
- 2026-04-26: Added `refresh: Bool` to `CompileOptions`; added `ensureUrlDep`/`ensureUrlDeps` helpers in driver.ks; wired into `compileGraph`. The `await` keyword cannot be used directly inside complex boolean expressions (e.g. `!(...await...)`) — must extract to a `val` first. A missing closing `}` for the `uniqueDependencyPaths` match arm was introduced during the brace refactor and required a direct brace-count audit to diagnose. Updated 10 inline `CompileOptions` records in `driver.test.ks` (and 2 in `driver-kti-loading.test.ks`) to include `refresh = False`. URL cross-module tests require `writeKti = True` since the dep needs to emit a KTI for the main module to import from.
