# URL Import Resolution

## Sequence: S04-01
## Tier: 7 — Deferred (large / dependency-heavy)

## Epic

- Epic: [E04 Module Resolution and Reproducibility](../epics/unplanned/E04-module-resolution-and-reproducibility.md)
- Companion stories: S04-02 (stdlib sub-path resolver, formerly S04-03)

## Summary

Spec 07 §4.2 defines URL specifiers (e.g. `https://example.com/lib.ks`). The current resolver rejects all
URL imports with a plain error string and no source span. This story implements seamless URL import
resolution: on first encounter the source is fetched and cached; subsequent builds use the cache. Two
flags control behaviour: `--refresh` forces re-download of all URL dependencies; `--status` pretty-prints
the state of every URL dependency without compiling or running.

## Current State

- `compiler/src/resolve.ts`: returns `{ ok: false, error: "URL imports not yet supported: ..." }` for
  any specifier starting with `http://` or `https://`. No span is attached.
- No URL fetching, caching, or content hashing logic exists.
- Cache directory `~/.kestrel/cache/` does not exist.
- `run` and `build` CLI commands have no `--refresh` or `--status` flags.

## Dependencies

- None. This story is standalone.

## Risks / Notes

- **SSRF risk at compile time:** The compiler fetches arbitrary URLs from source code. In CI or shared
  environments a malicious source file could trigger requests to internal services. Mitigations:
  `https://` only by default (`http://` accepted only via `--allow-http`), no redirects to a different
  host.
- **Content hash algorithm:** SHA-256. Cache path is `~/.kestrel/cache/<sha256-of-url>/source.ks`
  (directory name is the hex SHA-256 of the URL string, lowercase). This makes the cache layout
  stable and human-inspectable.
- **"Stale" definition:** A cached entry is considered stale when it was downloaded more than
  `KESTREL_CACHE_TTL` seconds ago (default: 7 days). `--status` surfaces stale entries; `--refresh`
  re-downloads them regardless of TTL.
- **Test infrastructure:** Integration tests must use a local mock HTTP server fixture in
  `compiler/test/fixtures/` rather than live network calls.
- **`file://` URL scheme:** Out of scope; path imports cover local files.

## Acceptance Criteria

- [ ] `https://` specifiers are recognised as URL specifiers. `http://` specifiers require `--allow-http`
      on the `run`/`build` command; otherwise a compile error with the import span is reported.
- [ ] On first use (cache miss), the compiler transparently fetches the URL, writes the source to
      `~/.kestrel/cache/<sha256-of-url>/source.ks`, and proceeds with compilation. No user action needed.
- [ ] On subsequent uses (cache hit), the cached file is used directly with no network request.
- [ ] No redirects to a different host are followed.
- [ ] `kestrel run --refresh <entry.ks>` and `kestrel build --refresh <entry.ks>` re-download **all**
      URL dependencies unconditionally before compiling, then update the cache.
- [ ] `kestrel build --status <entry.ks>` resolves the full dependency graph, outputs a pretty-printed
      report to stdout (no compilation or execution), and exits 0. Each URL dependency is listed with:
      - its specifier string
      - ✓ cached / ✗ not cached
      - age of cached copy (e.g. "3 days ago") or "—" if not cached
      - ⚠ stale marker if older than `KESTREL_CACHE_TTL`
- [ ] Cache root is `~/.kestrel/cache/` (overridable via `KESTREL_CACHE` env var), created on first use.
- [ ] `KESTREL_CACHE_TTL` controls the staleness threshold in seconds (default 604800 = 7 days).
- [ ] The fetched source is compiled as a normal module (same pipeline as path imports).
- [ ] Side-effect URL imports (`import "https://..."`) appear in the bytecode import table (07 §6).
- [ ] Integration test: import a function from a URL using a local mock HTTP server; verify the function
      runs correctly.
- [ ] Integration test: second compilation uses cache, mock server is not contacted.
- [ ] Integration test: `--refresh` contacts the mock server again even when cache is warm.
- [ ] Integration test: `--status` output lists the URL with correct cached/stale status.
- [ ] Negative test: unreachable URL with no cache produces a compile error with source location.

## Spec References

- 07-modules §4.2 (URL specifier resolution)
- 07-modules §7 (URL import cache)
- 09-tools §2.1 run, §2.3 build (`--refresh`, `--status`, `--allow-http`)
