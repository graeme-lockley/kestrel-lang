# Maven Resolver Hardening: Segment Validation and javap Timeout

## Sequence: S02-17
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/done/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01 through S02-16, S02-18

## Summary

Two low-severity hardening gaps in the E02 implementation:

1. **Maven segment path traversal**: `parseMavenSpecifier` only trims whitespace from `groupId`, `artifactId`, and `version`. A specifier like `import "maven:../../../etc:passwd:1.0"` will produce a file path outside the Maven cache directory. Maven coordinates must be validated against the standard character set before any filesystem or network operation.

2. **`javap` subprocess has no timeout**: `readClassMetadata` in `compiler/src/jvm-metadata/index.ts` calls `execSync('javap ...')` with no `timeout` option. If `javap` hangs (malformed jar, filesystem stall, or a pathological class file), the compiler hangs indefinitely. A bounded timeout should be set.

## Current State

- `sanitizeSegment` in `compiler/src/maven.ts` only calls `.trim()`. No character-level validation.
- `localJarPath` uses `path.join(...coord.groupId.split('.'), ...)` — a groupId of `../../../etc` would traverse out of the cache directory.
- `readClassMetadata` in `compiler/src/jvm-metadata/index.ts`: `execSync(...)` with no `timeout` option set.

## Relationship to other stories

- **Depends on S02-12** (maven resolver) and **S02-13** (jvm-metadata / javap).
- **Independent of S02-14, S02-15, S02-16**.

## Goals

1. Each of `groupId`, `artifactId`, and `version` in a maven specifier is validated against the pattern `[a-zA-Z0-9._\-]+`. Any segment containing characters outside this set is rejected as a **compile error** at `parseMavenSpecifier` call time, before any filesystem write or network request.
2. `readClassMetadata` passes `{ timeout: 15_000 }` (15 seconds) to `execSync`. On timeout, the error is caught and re-thrown as a human-readable message referencing the class name and suggesting checking the jar/classpath.

## Acceptance Criteria

- [ ] `import "maven:../../../etc:passwd:1.0"` is rejected at compile time with a diagnostic naming the invalid segment.
- [ ] `import "maven:com.example:my lib:1.0"` (space in artifactId) is rejected at compile time.
- [ ] `import "maven:com.example:lib:1.0"` (valid coordinate) continues to resolve correctly.
- [ ] A unit test covers the validation rejection cases.
- [ ] `readClassMetadata` throws a descriptive `Error` (not a raw timeout exception) when `javap` does not respond within 15 seconds.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — §4.2 Maven specifier section: note that coordinate segments must match `[a-zA-Z0-9._-]+`; invalid segments are a compile error.

## Risks / Notes

- **Maven Central coordinate conventions**: Maven Central permits a broader set of characters in coordinates in practice (notably `-` and `_`), but all common open-source artifacts use only `[a-zA-Z0-9._\-]`. Starting with this conservative set is safe; it can be relaxed later if a legitimate use case is found.
- **`timeout` interaction with large jars**: for a very large jar on a slow filesystem, 15 seconds may be insufficient. 15 s is conservative for JDK classes and typical Maven artifacts; add a note in the error message that `KESTREL_JAVAP_TIMEOUT_MS` can be set to override.
