# Multi-Module Resolver

## Sequence: S14-10
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-03, S14-04, S14-05, S14-06, S14-07, S14-08, S14-09, S14-11, S14-12, S14-13, S14-14

## Summary

Port the module specifier resolver to `stdlib/kestrel/compiler/resolve.ks`, covering
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

1. Create `stdlib/kestrel/compiler/resolve.ks` with:
   - `ResolveOptions` record
   - `resolveSpecifier(spec: String, opts: ResolveOptions): Result<String, String>`
   - `uniqueDependencyPaths(prog: Program, fromFile: String, opts: ResolveOptions): Result<List<ResolvedDep>, String>`
   - `ResolvedDep` record: `{ spec: String, path: String }`
   - URL cache helpers: `urlCachePath`, `readOriginUrl`, `resolveRelativeUrl`
   - Download-and-cache: `fetchUrl(url: String, cacheRoot: String, allowHttp: Bool): Task<Result<String, String>>`
   - Lockfile read/write helpers
   - Security: cross-origin path traversal rejection

## Acceptance Criteria

- `stdlib/kestrel/compiler/resolve.ks` compiles without errors.
- A test file `stdlib/kestrel/compiler/resolve.test.ks` covers:
  - `resolveSpecifier("kestrel:data/list", ...)` returns the correct absolute path
  - `resolveSpecifier("./helper.ks", ...)` resolves relative to `fromFile`
  - `resolveSpecifier("../outside.ks", ...)` from a URL-cached module returns a cross-origin error
  - An unknown stdlib specifier returns an error
- `./kestrel test stdlib/kestrel/compiler/resolve.test.ks` passes.
- `cd compiler && npm test` still passes.

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
