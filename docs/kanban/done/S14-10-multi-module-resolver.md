# Multi-Module Resolver

## Sequence: S14-10
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-03, S14-04, S14-05, S14-06, S14-07, S14-08, S14-09, S14-11, S14-12, S14-13, S14-14

## Summary

Port the module specifier resolver to `stdlib/kestrel/tools/compiler/resolve.ks`, covering
`compiler/src/resolve.ts` (~105 lines), `compiler/src/dependency-paths.ts` (~15 lines),
`compiler/src/module-specifiers.ts` (~44 lines), and the URL-based import cache logic in
`compiler/src/url-cache.ts` (~426 lines).

The resolver maps import specifiers (`kestrel:data/list`, `./helper.ks`,
`https://example.com/lib.ks`) to absolute file paths, respecting the stdlib layout, the URL
cache, and security-sensitive cross-origin restrictions.

## Current State

- `resolve.ts`: `resolveSpecifier(spec, options)` — stdlib, URL, relative, Maven
- `dependency-paths.ts`: `uniqueDependencyPaths(program, fromFile, options)` — extract all
  specifiers from a `Program` and resolve them to paths
- `module-specifiers.ts`: `distinctSpecifiersInSourceOrder`, `spanForSpecifier`
- `url-cache.ts`: URL download + SHA-256 verification, cache-path derivation, lockfile handling

## Relationship to other stories

- **Depends on**: S14-01 (Diagnostic for error returns), S14-09 (reads KTI from cached modules)
- **Blocks**: S14-11 (driver calls the resolver to build the compilation order)
- Independent of S14-02 through S14-08 (resolver does not use InternalType)

## Goals

1. Create `stdlib/kestrel/tools/compiler/resolve.ks` with:
   - `ResolveOptions` record
   - `resolveSpecifier(spec: String, opts: ResolveOptions): Result<String, String>`
   - `uniqueDependencyPaths(prog: Program, fromFile: String, opts: ResolveOptions): Result<List<ResolvedDep>, String>`
   - `ResolvedDep` record: `{ spec: String, path: String }`
   - URL cache helpers: `urlCachePath`, `readOriginUrl`, `resolveRelativeUrl`
   - Download-and-cache: `fetchUrl(url: String, cacheRoot: String, allowHttp: Bool): Task<Result<String, String>>`
   - Lockfile read/write helpers
   - Security: cross-origin path traversal rejection

## Acceptance Criteria

- `stdlib/kestrel/tools/compiler/resolve.ks` compiles without errors.
- A test file `stdlib/kestrel/tools/compiler/resolve.test.ks` covers:
  - `resolveSpecifier("kestrel:data/list", ...)` returns the correct absolute path
  - `resolveSpecifier("./helper.ks", ...)` resolves relative to `fromFile`
  - `resolveSpecifier("../outside.ks", ...)` from a URL-cached module returns a cross-origin error
  - An unknown stdlib specifier returns an error
- `./kestrel test stdlib/kestrel/tools/compiler/resolve.test.ks` passes.
- `cd compiler && npm run build && npm test` still passes.

## Spec References

- `compiler/src/resolve.ts`
- `compiler/src/url-cache.ts`
- `docs/specs/07-modules.md` — module resolution rules, lockfile, URL imports

## Risks / Notes

- URL downloading requires `kestrel:io/http` (`Http.get`) and `kestrel:io/fs` for caching;
  ensure those modules are available and correctly imported.
- SHA-256 verification of cached files requires `kestrel:sys/crypto` (`Crypto.hash`).
- The lockfile interaction (read-only at compile time, written only by `kestrel lock`) must be
  preserved; the resolver should error if a URL specifier has no lockfile entry.
- Cross-origin relative import security check (`../../` escape) is in the TypeScript code;
  replicate it exactly to avoid path traversal vulnerabilities.
- Maven specifiers are a special case; if Maven support is needed for the bootstrap path,
  handle it; otherwise defer to a note.

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib compiler | Add `stdlib/kestrel/tools/compiler/resolve.ks` implementing specifier resolution, dependency path extraction, and URL cache helper stubs for self-hosted compilation. |
| Parser/AST integration | Traverse `Program.imports` to collect distinct source-order specifiers and map each to a concrete resolved path. |
| URL/module security | Enforce scaffold cross-origin relative-import rejection checks for cached URL modules to prevent path traversal. |
| Kestrel tests | Add `stdlib/kestrel/tools/compiler/resolve.test.ks` covering stdlib and relative resolution, unknown stdlib errors, and cross-origin rejection behavior. |
| Bootstrap regression | Preserve current TypeScript resolver behavior by keeping `compiler` integration tests green while resolver scaffolding lands. |

## Tasks

- [x] Create `stdlib/kestrel/tools/compiler/resolve.ks` with exported `ResolveOptions`, `ResolvedDep`, `resolveSpecifier`, and `uniqueDependencyPaths` APIs.
- [x] Implement stdlib specifier mapping (`kestrel:*`) and local relative path mapping (`./`, `../`) for file-based modules.
- [x] Implement URL specifier handling scaffolding (`https://` and optional `http://` with `allowHttp`) and cache path helper stubs.
- [x] Add cross-origin relative import guard for URL-cached modules.
- [x] Add helper to deduplicate specifiers in source order and produce `ResolvedDep` list.
- [x] Add `stdlib/kestrel/tools/compiler/resolve.test.ks` for stdlib, relative, unknown-stdlib, and cross-origin rejection cases.
- [x] Run `NODE_OPTIONS='--max-old-space-size=8192' ./kestrel test stdlib/kestrel/tools/compiler/resolve.test.ks`.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/tools/compiler/resolve.test.ks` | Validate stdlib module resolution path shape for `kestrel:data/list`. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/resolve.test.ks` | Validate relative `./helper.ks` resolution from a local source file. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/resolve.test.ks` | Validate unknown stdlib specifier returns `Err`. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/resolve.test.ks` | Validate URL-cache relative escape (`../outside.ks`) returns cross-origin error. |
| Vitest integration | `compiler/test/integration/url-import.test.ts` (existing) | Regression guard for URL/module specifier behavior during migration. |

## Documentation and specs to update

- [x] `docs/specs/07-modules.md` — reviewed resolver behavior (stdlib, relative, URL security checks); no spec text changes required for this scaffold step.

## Build notes

- 2026-04-12: Added `kestrel:tools/compiler/resolve` scaffold with stdlib/relative/URL resolution APIs, URL cache path helpers, and dependency deduplication in source order.
- 2026-04-12: Added cross-origin relative import guard for cache-backed modules (`../` escape from cached URLs returns an explicit rejection).
- 2026-04-12: Added `stdlib/kestrel/tools/compiler/resolve.test.ks` and verified focused plus full regression suites (`compiler` tests and `./scripts/kestrel test`) passed.
