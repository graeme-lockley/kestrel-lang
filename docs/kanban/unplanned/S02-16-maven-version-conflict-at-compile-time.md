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

- [ ] A program with `import "maven:com.example:lib:1.0"` in one file and `import "maven:com.example:lib:2.0"` in a transitively imported file is rejected at compile time with an error naming both source files and both versions.
- [ ] `extern import "maven:com.example:lib:2.0#Cls"` in a file that already has `import "maven:com.example:lib:1.0"` is rejected with a diagnostic explaining the version mismatch.
- [ ] `kestrel build` (not only `kestrel run`) surfaces the conflict.
- [ ] A negative E2E test scenario covers the version-conflict compile error.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — §4.2 Maven specifier section: update to state that version conflicts are detected at compile time (not run time).

## Risks / Notes

- **Entry-point detection**: the compiler compiles modules on demand as imports are resolved. The entry-point module is the root of the compilation graph. The transitive `.kdeps` walk is the same logic already in `resolve-maven-classpath.mjs` — it can be ported to a TypeScript utility and called from the end of `compileEntryPoint` (or equivalent) in `compile-file-jvm.ts`.
- **`kestrel run` still calls `resolve-maven-classpath.mjs`**: the runtime script is a safety net for stale `.class` files compiled before this fix. It should be retained but its conflict check becomes a last-resort rather than the primary gate.
- **Diagnostic location**: the compile-time conflict error should point to the specific `import "maven:..."` declaration in source (span available in the AST). If the transitive conflict comes from an already-compiled `.kdeps`, only the file path is available — a file-level diagnostic is acceptable in that case.
