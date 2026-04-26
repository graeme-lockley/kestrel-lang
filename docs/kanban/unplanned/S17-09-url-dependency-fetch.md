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

- [ ] A URL import resolves and compiles when the cache file is present.
- [ ] A URL import where `allowHttp=False` but the URL is `http://` returns `ok=False`.
- [ ] Cache-hit path skips the network (no fetch call when file exists and `refresh=False`).
- [ ] `driver.test.ks` verifies the cache-hit and http-disallowed paths.
- [ ] `cd compiler && npm run build && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — URL imports and cache

## Risks / Notes

- `Resolve.fetchUrl` in the current Kestrel implementation is a stub that returns the cache path
  without actually fetching. Real HTTP fetch requires a JVM primitive (`kestrel:io/http` or
  equivalent). For now, the stub is acceptable — the important thing is the wiring.
- The `refresh` flag needs to be added to `CompileOptions` if not already present.
