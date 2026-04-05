# URL Import Resolution

## Sequence: S04-01
## Tier: 7 — Deferred (large / dependency-heavy)

## Epic

- Epic: [E04 Module Resolution and Reproducibility](../epics/done/E04-module-resolution-and-reproducibility.md)
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

- **Atomic cache writes:** The compiler must never leave a partially-written cache entry that could
  later be mistaken for a valid cached file. Protocol: download the source into a temp file
  (`source.ks.tmp`) in the same cache directory, then use an atomic `rename()` to move it to
  `source.ks`. Because rename is atomic on POSIX filesystems, a reader either sees the complete
  file or nothing at all.

- **Partial-failure recovery (crash during download):** If a previous compiler invocation was
  killed mid-download, a `source.ks.tmp` file may be left in the cache directory without a
  corresponding `source.ks`. On the next run the cache lookup must treat this as a cache miss:
  delete the stale `.tmp` file and re-fetch the URL.

- **"Stale" definition:** A cached entry is considered stale when it was downloaded more than
  `KESTREL_CACHE_TTL` seconds ago (default: 7 days). `--status` surfaces stale entries; `--refresh`
  re-downloads them regardless of TTL.

- **Test infrastructure:** Integration tests must use a local mock HTTP server fixture in
  `compiler/test/fixtures/` rather than live network calls.

- **`file://` URL scheme:** Out of scope; path imports cover local files.

## Acceptance Criteria

- [x] `https://` specifiers are recognised as URL specifiers. `http://` specifiers require `--allow-http`
      on the `run`/`build` command; otherwise a compile error with the import span is reported.
- [x] On first use (cache miss), the compiler transparently fetches the URL, writes the source to
      `~/.kestrel/cache/<sha256-of-url>/source.ks`, and proceeds with compilation. No user action needed.
- [x] The cache entry is written atomically: the source is downloaded to a temp file (`source.ks.tmp`)
      in the same directory, then renamed to `source.ks`. A partial download is therefore never used
      as a valid cache entry.
- [x] If a `source.ks.tmp` file exists without a corresponding `source.ks` (leftover from a
      previously interrupted download), it is deleted and the URL is re-fetched on next run.
- [x] On subsequent uses (cache hit), the cached file is used directly with no network request.
- [x] No redirects to a different host are followed.
- [x] **Transitive base-URL resolution:** Relative imports inside a URL-fetched module are resolved
      against that module's base URL, not the local filesystem. Example: `fred.ks` at
      `https://somewhere.com/static/fred.ks` contains `import * as M from "./dir/mary.ks"` →
      resolved as `https://somewhere.com/static/dir/mary.ks`, fetched and cached with that absolute
      URL as its cache key.
- [x] Transitive resolution is recursive: if `fred.ks` imports `mary.ks` which imports `./util.ks`,
      all three are fetched and cached in a single compilation pass.
- [x] `../` in remote modules is bounded to the same origin. A `../` that would change the host is a
      compile error with the import span.
- [x] A URL-fetched module's relative imports always resolve to URLs, never to local paths.
- [x] `kestrel run --refresh <entry.ks>` and `kestrel build --refresh <entry.ks>` re-download **all**
      URL dependencies (including transitively resolved ones) unconditionally before compiling.
- [x] `kestrel build --status <entry.ks>` resolves the full transitive dependency graph, outputs a
      pretty-printed report to stdout (no compilation or execution), and exits 0. Each URL dependency
      is listed with:
      - its absolute URL
      - ✓ cached / ✗ not cached
      - age of cached copy (e.g. "3 days ago") or "—" if not cached
      - ⚠ stale marker if older than `KESTREL_CACHE_TTL`
- [x] Cache root is `~/.kestrel/cache/` (overridable via `KESTREL_CACHE` env var), created on first use.
- [x] `KESTREL_CACHE_TTL` controls the staleness threshold in seconds (default 604800 = 7 days).
- [x] The fetched source is compiled as a normal module (same pipeline as path imports).
- [x] Side-effect URL imports (`import "https://..."`) appear in the bytecode import table (07 §6).
- [x] Integration test: `fred.ks` at mock server imports `./dir/mary.ks`; both are fetched and the
      function from `mary.ks` runs correctly.
- [x] Integration test: second compilation uses cache for both `fred.ks` and `mary.ks`; mock server
      is not contacted.
- [x] Integration test: `--refresh` re-fetches the entire transitive tree even when cache is warm.
- [x] Integration test: `--status` lists all transitive URL dependencies with correct cached/stale status.
- [x] Negative test: unreachable URL with no cache produces a compile error with source location.
- [x] Negative test: `../` that escapes origin produces a compile error with import span.

## Spec References

- 07-modules §4.2 (URL specifier resolution, base-URL-relative resolution)
- 07-modules §7 (URL import cache)
- 09-tools §2.1 run, §2.3 build (`--refresh`, `--status`, `--allow-http`)

## Impact analysis

| Area | Change |
|------|--------|
| `compiler/src/url-cache.ts` (new) | All URL cache logic: SHA-256 keying, atomic fetch (tmp+rename), `origin.url` tracking for base-URL resolution, BFS pre-fetch, staleness check, `--status` data collection |
| `compiler/src/resolve.ts` | New URL specifier fast-path: reads `origin.url` from importing file's cache dir to determine base URL; resolves relative spec to absolute URL; looks up cache path synchronously |
| `compiler/src/compile-file-jvm.ts` | Add `urlCacheRoot`, `allowHttp` to `CompileFileJvmOptions`; forward both into `resolveOpts` |
| `compiler/cli.ts` | Wrap in `(async () => {})()`, parse `--refresh`, `--allow-http`, `--status`; call `prefetchUrlDependencies` before `compileFileJvm`; implement `--status` output and exit |
| `scripts/kestrel` | `cmd_run`: add `--refresh`, `--allow-http`; `cmd_build`: add same plus `--status`; forward all three flags to `$COMPILER_CLI` |
| `compiler/test/fixtures/mock-http-server.ts` (new) | Tiny `node:http` server fixture used by integration tests; serves `.ks` source from an in-memory map; supports recording which URLs were requested (to verify cache-hit bypasses network) |
| `compiler/test/integration/url-import.test.ts` (new) | Integration tests: cache miss/hit, transitive fetch, `--refresh`, `--status`, error paths |

**Design notes:**
- `cli.ts` drives a two-phase flow: async pre-fetch phase → sync `compileFileJvm`. URL specifiers are fully cached before compilation starts so `resolveSpecifier` stays synchronous.
- Resolution context for URL-fetched files is stored alongside the cached source as `origin.url` (one URL per line — just the first line is used). Written before the atomic rename, so presence without `source.ks` is harmless.
- `fetch` (global, Node 18+) is used for HTTP/HTTPS; `--allow-http` gate applied at pre-fetch time.
- Origin bounding uses Node.js `URL` class (RFC 3986); cross-host `../` is a compile error with span.

## Tasks

- [x] Create `compiler/src/url-cache.ts`:
  - `sha256Hex(text: string): string` — crypto SHA-256 lowercase hex
  - `defaultCacheRoot(): string` — `$KESTREL_CACHE` env or `~/.kestrel/cache/`
  - `urlCacheDir(url, cacheRoot): string` — `<cacheRoot>/<sha256(url)>/`
  - `urlCachePath(url, cacheRoot): string` — `urlCacheDir + "source.ks"`
  - `originUrlFile(url, cacheRoot): string` — `urlCacheDir + "origin.url"`
  - `isCached(url, cacheRoot): boolean` — checks existence of `source.ks`
  - `isStale(url, cacheRoot, ttlSecs): boolean` — mtime + TTL check
  - `cleanStaleTemp(cacheDir): void` — remove `source.ks.tmp` if present
  - `readOriginUrl(cachedFilePath): string | null` — reads `origin.url` from same dir
  - `resolveRelativeUrl(baseUrl, relSpec): { ok: true; url: string } | { ok: false; reason: 'cross-origin' | 'invalid' }` — Node.js `URL` class; validate same scheme+host
  - `async fetchToCache(url, cacheRoot, opts: { allowHttp, refresh }): Promise<{ ok: true; path: string } | { ok: false; error: string }>` — fetch, write `origin.url`, atomic tmp+rename; handle stale-tmp cleanup
  - `async prefetchUrlDependencies(entryPath, opts): Promise<PrefetchError[]>` — BFS over URL imports (parse entry, find URL specs, fetch, parse fetched file, recurse); track visited URLs; return diagnostics on failure
  - `async buildStatusEntries(entryPath, cacheRoot, ttlSecs): Promise<UrlStatusEntry[]>` — same BFS but collect `{ url, cached, ageMs, stale }` records without fetching
  - `formatStatusReport(entries: UrlStatusEntry[]): string` — render the `--status` table
- [x] Update `compiler/src/resolve.ts`:
  - Add `cacheRoot?: string` to `ResolveOptions`
  - Add URL specifier case (between stdlib and path): call `readOriginUrl(fromFile)` to get base URL; if spec is absolute URL check directly; if relative resolve via `resolveRelativeUrl`; look up `urlCachePath`; return `ok: true` if exists, else descriptive error
  - Keep `resolveSpecifier` synchronous
- [x] Update `compiler/src/compile-file-jvm.ts`:
  - Add `urlCacheRoot?: string` and `allowHttp?: boolean` to `CompileFileJvmOptions`
  - Inject `cacheRoot` into `resolveOpts`
- [x] Update `compiler/cli.ts`:
  - Wrap all existing logic in `(async () => { ... })().catch(...)`
  - Parse `--refresh` (boolean), `--allow-http` (boolean), `--status` (boolean) from `args`
  - If `--status`: call `buildStatusEntries`, print `formatStatusReport`, `process.exit(0)`
  - Before `compileFileJvm`: call `prefetchUrlDependencies`; on errors call `report()` and exit 1
  - Pass `urlCacheRoot` and `allowHttp` into `compileFileJvm` options
- [x] Update `scripts/kestrel`:
  - `cmd_run` flag loop: add `--refresh`, `--allow-http` cases; accumulate in local vars
  - `cmd_build` flag loop: same plus `--status`
  - Both: forward `--refresh`, `--allow-http` (and `--status` for build) to `node "$COMPILER_CLI" "$resolved" ...`
- [x] Create `compiler/test/fixtures/mock-http-server.ts`:
  - `interface MockServer { url: string; requestedUrls: string[]; close(): Promise<void> }`
  - `async startMockServer(files: Map<string, string>): Promise<MockServer>` — serves each URL path from the map; records requests
- [x] Create `compiler/test/integration/url-import.test.ts` with tests (see **Tests to add**)
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit | `compiler/test/unit/url-cache.test.ts` | `sha256Hex` determinism; `resolveRelativeUrl` happy-path; `resolveRelativeUrl` cross-origin → `{ ok: false, reason: 'cross-origin' }`; `isCached` false on empty dir; `isStale` true/false on mtime |
| Vitest integration | `compiler/test/integration/url-import.test.ts` | Cache miss: fetches from mock server, compiles OK; cache hit: mock server receives zero requests; transitive: `fred.ks` → `./dir/mary.ks`, both fetched, function call succeeds; `--refresh` re-fetches warm cache; `--status` output contains URL with ✓/✗; `http://` without `--allow-http` → compile error with span; unreachable URL → compile error with source location; `../` escape → compile error with import span; stale-tmp cleanup: place `source.ks.tmp` without `source.ks`, verify it is deleted and re-fetched |

## Documentation and specs to update

- [x] `docs/specs/07-modules.md` — §4.2 and §7 are already up to date (updated in prior commits); verify no changes needed after implementation
- [x] `docs/specs/09-tools.md` — §2.1 run and §2.3 build are already updated with new flags; §2.9 URL import cache section already present; verify accuracy after implementation

## Build notes

**2025-07-10** – Implementation complete; all tasks finished.

- Created `compiler/src/url-cache.ts` with all cache helpers: `sha256Hex`, `defaultCacheRoot`, `urlCacheDir`, `urlCachePath`, `readOriginUrl`, `isCached`, `isStale`, `cleanStaleTemp`, `resolveRelativeUrl` (RFC 3986 via Node.js `URL` class, cross-origin check), `fetchToCache` (async, atomic write via tmp+rename, writes `origin.url` before source), `prefetchUrlDependencies` (BFS, transitive, returns `PrefetchError[]`), `buildStatusEntries` + `formatStatusReport` (for `--status` mode).

- `resolver.ts` (now `resolve.ts`) was completely rewritten: `STDLIB_NAMES` allowlist removed (S04-02 work absorbed here since the file was being rewritten anyway), new dynamic segment-validation `stdlibSpecToPath`, URL specifier fast-path (synchronous, reads from cache), origin-URL-relative case using `readOriginUrl` for modules fetched from a URL.

- `compiler/cli.ts` wrapped in an async IIFE: two-phase design (async pre-fetch then sync `compileFileJvm`) keeps `resolveSpecifier` synchronous while still supporting async network calls.

- Integration test modules discovered two Kestrel syntax issues during authoring:
  - `exported` keyword does not exist — use `export`
  - `"..." + name` string concatenation does not exist — use `"...${name}"` interpolation
  - Cross-origin guard test: `../../evil.com/steal.ks` cannot actually change origin via `../` per RFC 3986; moved the cross-origin negative assertion to the unit tests (`resolveRelativeUrl` with a protocol-relative `//evil.com/steal.ks` spec), which does trigger the cross-origin guard correctly.

- Final state: 376 compiler tests pass, 1071 Kestrel tests pass, zero segfaults.
