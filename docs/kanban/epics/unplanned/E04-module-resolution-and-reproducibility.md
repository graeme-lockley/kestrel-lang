# Epic E04: Module Resolution and Reproducibility

## Status

Unplanned

## Summary

Adds deterministic dependency management for remote modules by pairing lockfile support with URL import resolution. Also removes the hardcoded stdlib whitelist so that `kestrel:` sub-path specifiers (needed by E08) resolve by file-existence rather than an explicit list.

## Stories

- [S04-01-lockfile-kestrel-lock.md](../../unplanned/S04-01-lockfile-kestrel-lock.md)
- [S04-02-url-import-resolution.md](../../unplanned/S04-02-url-import-resolution.md)
- [S04-03-stdlib-subpath-resolver.md](../../unplanned/S04-03-stdlib-subpath-resolver.md)

## Dependencies

- S04-01 (Lockfile) must land before S04-02 (URL imports); S04-02 depends on S04-01's cache and lockfile infrastructure.
- S04-03 (stdlib sub-path resolver) is independent and can land at any time; it **must** land before E08 begins.

## Epic Completion Criteria

- `kestrel.lock` format is defined (JSON), implemented, and documented in docs/specs/09-tools.md.
- `kestrel lock` CLI command resolves all dependencies and writes/updates the lockfile.
- When a lockfile is present, URL resolution uses only locked artifacts (no live network fetch for known specifiers).
- Specifiers starting with `https://` or `http://` are fetched, content-hashed (SHA-256), and cached under `~/.kestrel/cache/`.
- Compile errors for URL resolution failures include source span information.
- Integration tests demonstrate reproducible URL dependency resolution using a local mock server and a lockfile.
- `kestrel:X` and `kestrel:X/Y` specifiers resolve by file existence under `stdlib/`, not a hardcoded whitelist.
- The project root is determined canonically (walk up from entry file to first `kestrel.lock` or project root sentinel, documented in spec).
