# Lockfile: kestrel.lock

## Sequence: S04-02
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 26

## Epic

- Epic: [E04 Module Resolution and Reproducibility](../epics/unplanned/E04-module-resolution-and-reproducibility.md)
- Companion stories: S04-01 (URL imports — primary consumer of lockfile)

## Summary

Spec 07 §7 defines `kestrel.lock` as a project-root file that records resolved dependency information for deterministic resolution without network access. This is primarily important for URL imports (S04-01) but also defines the cache directory conventions and project-root determination logic that all specifier kinds depend on.

## Current State

- No lockfile implementation exists.
- The compiler resolves imports on every compilation.
- URL imports are rejected (`resolve.ts` returns an error string for URLs).
- For local path imports, resolution is already deterministic (same project layout = same result).
- Project root is currently `process.cwd()` hardcoded in `compileFileJvm` — spec §7 requires the implementation to define this formally (walk up from entry file).
- Cache directory `~/.kestrel/cache/` does not exist.

## Dependencies

- None. This story is foundational for S04-01.

## Risks / Notes

- **Format decision: JSON.** The lockfile will use JSON (consistent with `.kti` types files and `package.json` ecosystem). One top-level key per specifier string; value contains `url` (original), `sha256` (content hash of the downloaded source), and `cachedPath` (absolute path under `~/.kestrel/cache/`).
- **Project-root determination:** The spec (07 §7) requires the implementation to document how the project root is found. Implementation: walk up the directory tree from the entry file's directory, stopping at the first directory that contains `kestrel.lock` or a `.git` directory; if neither is found, use the entry file's directory. This must be documented in `docs/specs/09-tools.md`.
- **`kestrel lock` command:** Must be added to `docs/specs/09-tools.md` and wired into the `scripts/kestrel` CLI. The command resolves all distinct URL specifiers transitively from an entry file and writes/updates `kestrel.lock`.
- **Version conflict detection:** URL dependencies do not carry semantic version metadata. If the same URL appears with two different locked SHA-256 hashes in a transitive graph, report a compile error (analogous to Maven version conflicts in `maven.ts`).
- **Offline enforcement:** When a lockfile is present, URL resolution must not perform live network fetches for specifiers already in the lockfile. An `--offline` flag should enforce this for all specifiers (error if any URL specifier is not in the lockfile).

## Acceptance Criteria

- [ ] Project-root determination is implemented: walk up from entry file to first directory containing `kestrel.lock` or `.git`; fall back to entry file's directory. Documented in `docs/specs/09-tools.md`.
- [ ] Cache root is `~/.kestrel/cache/` (overridable via `KESTREL_CACHE` env var), created on first use.
- [ ] Lockfile format is JSON; each entry maps a URL specifier string to `{ sha256: string, cachedPath: string }`.
- [ ] `kestrel lock <entry.ks>` command: resolves all URL specifiers transitively, fetches and caches sources, writes `kestrel.lock` at the project root.
- [ ] When lockfile is present and a URL specifier is listed, the compiler uses the cached artifact (no network fetch). If the cached file is missing, report an error with a suggestion to re-run `kestrel lock`.
- [ ] When a URL specifier is NOT in the lockfile: resolve live, cache the result, and update the lockfile (append mode). Under `--offline`, this is a compile error instead.
- [ ] Two distinct URL specifiers resolving to artifacts with mismatched SHA-256 hashes in the lockfile produce a compile error at the import site.
- [ ] `kestrel lock` is documented in `docs/specs/09-tools.md` (format, location, behaviour, `--offline` flag).
- [ ] Integration test: run `kestrel lock`, delete network access (mock), confirm compiler uses locked cache.
- [ ] Integration test: modify a cached artifact's content, confirm SHA-256 mismatch produces a compile error.

## Spec References

- 07-modules §7 (Lockfile: format, location, behaviour)
- 09-tools (CLI commands — `kestrel lock` to be added)
