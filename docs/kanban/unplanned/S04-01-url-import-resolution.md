# URL Import Resolution

## Sequence: S04-01
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 25

## Epic

- Epic: [E04 Module Resolution and Reproducibility](../epics/unplanned/E04-module-resolution-and-reproducibility.md)
- Companion stories: 63

## Summary

Spec 07 §4.2 defines URL specifiers (e.g., `https://example.com/lib.ks`). The current resolver rejects all URL imports. URL imports require fetching, caching, lockfile integration, and content hashing.

## Current State

- `resolve.ts`: Returns `null` (resolution failure) for any specifier starting with `http://` or `https://`.
- No URL fetching, caching, or content hashing logic.

## Dependencies

- Sequence **63** (Lockfile) should be done first for deterministic URL resolution.

## Acceptance Criteria

- [ ] Specifiers starting with `https://` or `http://` are recognized as URL specifiers.
- [ ] Fetch the source from the URL (HTTPS required for production; HTTP allowed for development).
- [ ] Cache downloaded source under `~/.kestrel/cache/` or similar, keyed by URL + content hash.
- [ ] If a lockfile is present and the URL is listed, use the cached/locked version.
- [ ] If the URL is not reachable and not cached, report a compile error.
- [ ] Compile the fetched source as a normal module.
- [ ] Integration test: import from a URL (mock or local server for testing).

## Spec References

- 07-modules §4.2 (URL specifier resolution)
- 07-modules §7 (Lockfile for URL dependencies)
