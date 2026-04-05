# URL Import Resolution

## Sequence: S04-01
## Tier: 7 — Deferred (large / dependency-heavy)

## Epic

- Epic: [E04 Module Resolution and Reproducibility](../epics/unplanned/E04-module-resolution-and-reproducibility.md)
- Companion stories: S04-02 (stdlib sub-path resolver)

## Summary

Spec 07 §4.2 defines URL specifiers (e.g. `https://example.com/lib.ks`). The current resolver rejects all
URL imports with a plain error string and no source span. This story implements seamless URL import
resolution: on first encounter the source is fetched and cached; subsequent builds use the cache. Two
flags control behaviour: `--refresh` forces re-download of all URL dependencies; `--status` pretty-prints
the state of every URL dependency without compiling or running.

Critically, URL-fetched modules may themselves contain relative imports (e.g.
`import * as M from "./dir/mary.ks"`). These are resolved relative to the **base URL** of the fetching
module, producing new absolute URLs that are also fetched and cached. The entire transitive dependency
tree of any remote module is therefore automatically downloaded into the cache on first use.

## Current State

- `compiler/src/resolve.ts`: returns `{ ok: false, error: "URL imports not yet supported: ..." }` for
  any specifier starting with `http://` or `https://`. No span is attached.
- No URL fetching, caching, content hashing, or base-URL-relative resolution logic exists.
- Cache directory `~/.kestrel/cache/` does not exist.
- `run` and `build` CLI commands have no `--refresh` or `--status` flags.

## Dependencies

- None. This story is standalone.

## Risks / Notes

- **Base-URL-relative resolution in remote modules:** When a fetched module contains a relative path
  import (e.g. `"./dir/mary.ks"` or `"../util.ks"`), the specifier is resolved relative to the
  **base URL** of the fetched module, not the local filesystem. For example:
  - Fetched: `https://somewhere.com/static/fred.ks`
  - Import inside `fred.ks`: `"./dir/mary.ks"`
  - Resolved to: `https://somewhere.com/static/dir/mary.ks` — fetched and cached with that URL as key
  This applies recursively. The entire transitive remote dependency tree is pulled into the cache in
  a single compilation pass. The cache key for every transitively-resolved module is its
  fully-qualified absolute URL.

- **Path traversal safety:** `../` in a relative import inside a remote module must not escape the
  origin (scheme + host). If resolving `../` would change the host, it is a compile error with the
  import span. The resolved URL must share the same scheme and host as the importing module's URL.

- **Resolution context switch:** A module's resolution context determines how its relative imports are
  resolved. URL-fetched modules use their URL as the base; local files use their filesystem directory.
  A URL-fetched module's relative imports always resolve to URLs — never to local paths.

- **SSRF risk at compile time:** The compiler fetches arbitrary URLs from source code. In CI or shared
  environments a malicious source file could trigger requests to internal services. Mitigations:
  `https://` only by default (`http://` accepted only via `--allow-http`), no redirects to a different
  host, and path traversal is bounded to the same origin.

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
- [ ] **Transitive base-URL resolution:** Relative imports inside a URL-fetched module are resolved
      against that module's base URL, not the local filesystem. Example: `fred.ks` at
      `https://somewhere.com/static/fred.ks` contains `import * as M from "./dir/mary.ks"` →
      resolved as `https://somewhere.com/static/dir/mary.ks`, fetched and cached with that absolute
      URL as its cache key.
- [ ] Transitive resolution is recursive: if `fred.ks` imports `mary.ks` which imports `./util.ks`,
      all three are fetched and cached in a single compilation pass.
- [ ] `../` in remote modules is bounded to the same origin. A `../` that would change the host is a
      compile error with the import span.
- [ ] A URL-fetched module's relative imports always resolve to URLs, never to local paths.
- [ ] `kestrel run --refresh <entry.ks>` and `kestrel build --refresh <entry.ks>` re-download **all**
      URL dependencies (including transitively resolved ones) unconditionally before compiling.
- [ ] `kestrel build --status <entry.ks>` resolves the full transitive dependency graph, outputs a
      pretty-printed report to stdout (no compilation or execution), and exits 0. Each URL dependency
      is listed with:
      - its absolute URL
      - ✓ cached / ✗ not cached
      - age of cached copy (e.g. "3 days ago") or "—" if not cached
      - ⚠ stale marker if older than `KESTREL_CACHE_TTL`
- [ ] Cache root is `~/.kestrel/cache/` (overridable via `KESTREL_CACHE` env var), created on first use.
- [ ] `KESTREL_CACHE_TTL` controls the staleness threshold in seconds (default 604800 = 7 days).
- [ ] The fetched source is compiled as a normal module (same pipeline as path imports).
- [ ] Side-effect URL imports (`import "https://..."`) appear in the bytecode import table (07 §6).
- [ ] Integration test: `fred.ks` at mock server imports `./dir/mary.ks`; both are fetched and the
      function from `mary.ks` runs correctly.
- [ ] Integration test: second compilation uses cache for both `fred.ks` and `mary.ks`; mock server
      is not contacted.
- [ ] Integration test: `--refresh` re-fetches the entire transitive tree even when cache is warm.
- [ ] Integration test: `--status` lists all transitive URL dependencies with correct cached/stale status.
- [ ] Negative test: unreachable URL with no cache produces a compile error with source location.
- [ ] Negative test: `../` that escapes origin produces a compile error with import span.

## Spec References

- 07-modules §4.2 (URL specifier resolution, base-URL-relative resolution)
- 07-modules §7 (URL import cache)
- 09-tools §2.1 run, §2.3 build (`--refresh`, `--status`, `--allow-http`)
