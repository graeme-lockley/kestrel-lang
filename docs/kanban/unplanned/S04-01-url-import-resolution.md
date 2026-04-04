# URL Import Resolution

## Sequence: S04-01
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 25

## Epic

- Epic: [E04 Module Resolution and Reproducibility](../epics/unplanned/E04-module-resolution-and-reproducibility.md)
- Companion stories: S04-02 (Lockfile — must land first)

## Summary

Spec 07 §4.2 defines URL specifiers (e.g., `https://example.com/lib.ks`). The current resolver rejects all URL imports with a plain error string and no source span. URL imports require fetching, content hashing (SHA-256), caching, and lockfile integration.

## Current State

- `compiler/src/resolve.ts`: returns `{ ok: false, error: "URL imports not yet supported: ..." }` for any specifier starting with `http://` or `https://`. No span is attached to this diagnostic at the call site in `compile-file-jvm.ts` (the span lookup via `spanForSpecifier` is only applied after the error is returned, so the location is already lost for URL paths).
- No URL fetching, caching, or content hashing logic.
- Cache directory (`~/.kestrel/cache/`) does not exist.

## Dependencies

- **S04-02 (Lockfile)** must land first — URL resolution depends on S04-02's lockfile format, cache directory conventions, and project-root determination.

## Risks / Notes

- **SSRF risk at compile time:** The compiler fetches arbitrary URLs from source code. In CI or shared environments, a malicious source file could trigger requests to internal services. Mitigations: HTTPS-only by default (HTTP only via explicit flag), no redirect following to different hosts, and the lockfile should be the primary mechanism in production builds.
- **Content hash algorithm:** Must be SHA-256 (consistent with `maven.ts` and the lockfile format defined in S04-02).
- **Test infrastructure:** Integration tests must use a local mock HTTP server (e.g., a small Node.js `http.createServer` fixture in `compiler/test/fixtures/`) rather than live network calls, so tests are deterministic and offline-safe.
- **`file://` URL scheme:** Out of scope for this story; relative and absolute path imports already cover local files. `file://` URLs will be rejected with the same error as unsupported schemes.
- **Error quality:** The current rejection in `resolve.ts` does not surface a source span. The fix must attach the import span to the diagnostic (the span is available via `spanForSpecifier` in `compile-file-jvm.ts` — this works for the "not yet supported" error today but will need to be preserved once real URL resolution is wired in).

## Acceptance Criteria

- [ ] Specifiers starting with `https://` are recognised as URL specifiers. `http://` specifiers are accepted only when a `--allow-http` flag is passed; otherwise a compile error is reported with the import span.
- [ ] The compiler fetches the source from the URL over HTTPS. No redirects to a different host are followed.
- [ ] Downloaded source is cached under `~/.kestrel/cache/<sha256-of-url>/source.ks`, where the directory name is the SHA-256 hash of the URL string (hex, lowercase).
- [ ] If a lockfile is present and lists the URL specifier, the compiler uses the cached artifact matching the locked SHA-256 hash and does **not** perform a network fetch.
- [ ] If the URL is not reachable and no cached or locked artifact exists, a compile error is reported with the import span and a suggestion to run `kestrel lock`.
- [ ] If the fetched content differs from a locked SHA-256 hash, it is a compile error (lockfile mismatch).
- [ ] The fetched source is compiled as a normal module (same pipeline as path imports).
- [ ] Side-effect URL imports (`import "https://..."`) appear in the bytecode import table (07 §6).
- [ ] Integration test: import a function from a URL using a local mock HTTP server; verify the function runs correctly.
- [ ] Integration test: with a lockfile present, the mock server is not contacted (offline-safe).
- [ ] Negative E2E test: unreachable URL with no cache/lockfile produces a compile error with source location.

## Spec References

- 07-modules §4.2 (URL specifier resolution)
- 07-modules §7 (Lockfile for URL dependencies)
