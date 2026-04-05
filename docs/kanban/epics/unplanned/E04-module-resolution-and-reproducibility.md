# Epic E04: Module Resolution and Reproducibility

## Status

Unplanned

## Summary

Adds seamless URL import resolution: remote modules are fetched on first use and cached under `~/.kestrel/cache/`; subsequent builds use the cache. `--refresh` forces re-download; `--status` reports cache health. Also removes the hardcoded stdlib whitelist so that `kestrel:` sub-path specifiers (needed by E08) resolve by file-existence rather than an explicit list.

## Stories

- [S04-01-url-import-resolution.md](../../unplanned/S04-01-url-import-resolution.md)
- [S04-02-stdlib-subpath-resolver.md](../../unplanned/S04-02-stdlib-subpath-resolver.md)

## Dependencies

- S04-01 (URL imports) and S04-02 (stdlib sub-path resolver) are independent; either can land first.
- S04-02 **must** land before E08 begins.

## Epic Completion Criteria

- URL specifiers (`https://`) are fetched on first use, cached under `~/.kestrel/cache/`, and reused on subsequent builds — no user action needed for first download.
- Relative imports inside a URL-fetched module are resolved against that module's base URL, recursively — the entire transitive remote dependency tree is pulled into the cache automatically.
- Relative path traversal from remote modules is bounded to the same origin; cross-host traversal is a compile error.
- `kestrel run --refresh` and `kestrel build --refresh` force re-download of the full transitive URL dependency tree.
- `kestrel build --status` pretty-prints the cache state of every URL dependency (direct and transitive: cached, not cached, stale) without building.
- Compile errors for URL resolution failures include source span information.
- Integration tests demonstrate cache hit/miss behaviour, transitive fetching, and `--refresh` using a local mock server.
- `kestrel:X` and `kestrel:X/Y` specifiers resolve by file existence under `stdlib/`, not a hardcoded whitelist.
