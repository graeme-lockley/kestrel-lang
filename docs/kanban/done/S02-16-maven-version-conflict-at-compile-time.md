# Maven Version Conflict Detection at Compile Time

## Sequence: S02-16
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/done/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01 through S02-15, S02-17, S02-18

## Summary

Maven version conflicts are currently only detected at runtime (when `kestrel run` calls `resolve-maven-classpath.mjs`). If two source files import the same `groupId:artifactId` at different versions, the program compiles successfully and only fails when run. Additionally, an `extern import "maven:g:a:version#Class"` that references a version different from the previously declared side-effect import `import "maven:g:a:version"` silently uses the wrong jar — no warning is issued.

Both checks belong at compile time, where the source context is available for precise error messages.

## Current State

- `compile-file-jvm.ts` resolves each file's maven specifiers independently via `resolveMavenSpecifiers`. No cross-file conflict check exists during compilation.
- `expandExternImports` matches a maven `extern import` target to a resolved `mavenDep` by `groupId:artifactId` (ga) only, not by full version. A version mismatch between the `extern import` target and the side-effect import is silently accepted.
- `scripts/resolve-maven-classpath.mjs` performs the conflict check but is invoked only by the `kestrel run` CLI path — `kestrel build` and `kestrel dis` do not call it.

## Relationship to other stories

- **Depends on S02-12**: the `.kdeps` sidecar mechanism and `resolveMavenSpecifiers` were introduced there.
- **Independent of S02-14, S02-15**.

## Goals

1. During compilation of the **entry-point module**, after all transitive modules have been compiled, read all `.kdeps` sidecars transitively and report any `groupId:artifactId` that appears at two different versions as a **compile error** (with source file locations pointing to the offending `import "maven:..."` declarations).
2. In `expandExternImports`, when matching an `extern import "maven:g:a:version#Class"` to a resolved side-effect import, validate that the version in the `extern import` target matches the version of the resolved artifact. If they differ, emit a diagnostic.
3. The conflict check runs for **all** kestrel compiler invocations that compile an entry point (`kestrel run`, `kestrel build`, `kestrel dis`), not only `kestrel run`.

## Acceptance Criteria

- [x] A program with `import "maven:com.example:lib:1.0"` in one file and `import "maven:com.example:lib:2.0"` in a transitively imported file is rejected at compile time with an error naming both source files and both versions.
- [x] `extern import "maven:com.example:lib:2.0#Cls"` in a file that already has `import "maven:com.example:lib:1.0"` is rejected with a diagnostic explaining the version mismatch.
- [x] `kestrel build` (not only `kestrel run`) surfaces the conflict.
- [ ] A negative E2E test scenario covers the version-conflict compile error. *(See build notes — covered by integration tests instead due to maven cache env constraint.)*
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Impact analysis

| Area | Change |
|------|--------|
| `compiler/src/compile-file-jvm.ts` | Extend `cache` map and `compileOne` return type to include `mavenDeps`; after entry-point compilation scan all cache entries for ga:version conflicts; add version-mismatch check in `expandExternImports` for `maven:` extern import targets |
| `compiler/test/integration/maven-kdeps.test.ts` | Add tests: multi-module conflict detection, extern import version mismatch |
| `docs/specs/07-modules.md` | §4.2 Maven specifier: state conflicts are detected at compile time |

## Tasks

- [x] Add `mavenDeps: MavenResolvedDependency[]` to the cache map type and to `compileOne`'s return type in `compile-file-jvm.ts`
- [x] In `compileOne`, store `mavenDeps` in the cache after successful compilation
- [x] After `compileOne(absPath)` returns `ok:true`, scan all cache entries for ga→version conflicts; emit diagnostics naming both files and versions
- [x] In `expandExternImports`, extract the version from the `maven:` extern import target; if it doesn't match the resolved dep's version, emit a diagnostic
- [x] Add integration test: two-file program where files import same artifact at different versions → compile fails naming both files and versions
- [x] Add integration test: `extern import "maven:g:a:v2#Class"` with `import "maven:g:a:v1"` (version mismatch) → compile error
- [x] Update `docs/specs/07-modules.md` §4.2 to document compile-time conflict detection
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest integration | `compiler/test/integration/maven-kdeps.test.ts` | Multi-module conflict → compile error; extern import version mismatch → compile error |

## Documentation and specs to update

- [ ] `docs/specs/07-modules.md` — §4.2 Maven specifier section: state version conflicts detected at compile time, not run time

## Spec References

- `docs/specs/07-modules.md` — §4.2 Maven specifier section: update to state that version conflicts are detected at compile time (not run time).

## Risks / Notes

- **Entry-point detection**: the compiler compiles modules on demand as imports are resolved. The entry-point module is the root of the compilation graph. The transitive `.kdeps` walk is the same logic already in `resolve-maven-classpath.mjs` — it can be ported to a TypeScript utility and called from the end of `compileEntryPoint` (or equivalent) in `compile-file-jvm.ts`.
- **`kestrel run` still calls `resolve-maven-classpath.mjs`**: the runtime script is a safety net for stale `.class` files compiled before this fix. It should be retained but its conflict check becomes a last-resort rather than the primary gate.
- **Diagnostic location**: the compile-time conflict error should point to the specific `import "maven:..."` declaration in source (span available in the AST). If the transitive conflict comes from an already-compiled `.kdeps`, only the file path is available — a file-level diagnostic is acceptable in that case.

## Build notes

2025-01-01: Implementation approach chosen: extend the `cache` map (inner `Map` inside `compileFileJvm`) to carry `mavenDeps: MavenResolvedDependency[]` per compiled file. After the top-level `compileOne(absPath)` call succeeds, scan all cache entries in one pass with a `Map<ga, {version, filePath}>` to detect the first version conflict. This is simpler than walking `.kdeps` sidecars transitively (which would duplicate logic from `resolve-maven-classpath.mjs`) and is fully in-memory using data already present.

2025-01-01: `expandExternImports` version check: `parts = target.slice('maven:'.length).split(':')` gives `["groupId", "artifactId", "version#ClassName"]` for `extern import` targets. The `#ClassName` fragment is in `parts[2]`, so the version is extracted via `parts[2].split('#')[0]`. The check is intentionally strict: if the user writes `extern import "maven:g:a:2.0#..."` but the side-effect import has `maven:g:a:1.0`, it's a compile error pointing to the `extern import` span.

2025-01-01: E2E negative test omitted: a negative E2E scenario for maven conflicts would require a fake-jar maven cache accessible to the `kestrel run` CLI without network access. The `run-e2e.sh` runner does not support per-test env vars. The acceptance criterion is satisfied by three new Vitest integration tests in `maven-kdeps.test.ts` that directly invoke `compileFileJvm` with `KESTREL_MAVEN_CACHE` set to a temp dir with fake jars.

2025-01-01: 317 compiler tests + 1020 Kestrel tests passing.
