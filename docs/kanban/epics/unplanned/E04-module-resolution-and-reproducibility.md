# Epic E04: Module Resolution and Reproducibility

## Status

Unplanned

## Summary

Adds deterministic dependency management for remote modules by pairing lockfile support with URL import resolution.

## Stories

- [S04-01-url-import-resolution.md](../../unplanned/S04-01-url-import-resolution.md)
- [S04-02-lockfile-kestrel-lock.md](../../unplanned/S04-02-lockfile-kestrel-lock.md)

## Dependencies

- Story 63 should land before or alongside story 62.

## Epic Completion Criteria

- Lockfile behavior is implemented and documented.
- URL imports use lockfile/cache rules deterministically.
- Integration coverage demonstrates reproducible dependency resolution.
