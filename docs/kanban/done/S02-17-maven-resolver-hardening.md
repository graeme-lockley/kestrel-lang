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

## Tasks

- [x] Add `MAVEN_SEGMENT_RE = /^[a-zA-Z0-9._\\-]+$/` to `compiler/src/maven.ts`; in `parseMavenSpecifier`, after parsing parts, validate each segment against `MAVEN_SEGMENT_RE` and throw a descriptive error if invalid
- [x] In `compiler/src/jvm-metadata/index.ts` (`readClassMetadata`): declare `timeoutMs` outside `try`, pass `{ timeout: timeoutMs }` to `execSync`, detect timeout in `catch` via `err.killed || err.signal`
- [x] Add unit tests in `compiler/test/unit/maven.test.ts`: path-traversal groupId, space in artifactId, null byte in version, valid coordinate accepted
- [x] Update `docs/specs/07-modules.md` §4.2 to document segment validation requirement
- [x] Run `cd compiler && npm test`
- [x] Run `./scripts/kestrel test`

## Acceptance Criteria

- [x] `import "maven:../../../etc:passwd:1.0"` is rejected at compile time with a diagnostic naming the invalid segment.
- [x] `import "maven:com.example:my lib:1.0"` (space in artifactId) is rejected at compile time.
- [x] `import "maven:com.example:lib:1.0"` (valid coordinate) continues to resolve correctly.
- [x] A unit test covers the validation rejection cases.
- [x] `readClassMetadata` throws a descriptive `Error` (not a raw timeout exception) when `javap` does not respond within 15 seconds.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — §4.2 Maven specifier section: note that coordinate segments must match `[a-zA-Z0-9._-]+`; invalid segments are a compile error.

## Risks / Notes

- **Maven Central coordinate conventions**: Maven Central permits a broader set of characters in coordinates in practice (notably `-` and `_`), but all common open-source artifacts use only `[a-zA-Z0-9._\-]`. Starting with this conservative set is safe; it can be relaxed later if a legitimate use case is found.
- **`timeout` interaction with large jars**: for a very large jar on a slow filesystem, 15 seconds may be insufficient. 15 s is conservative for JDK classes and typical Maven artifacts; add a note in the error message that `KESTREL_JAVAP_TIMEOUT_MS` can be set to override.

## Build notes

2025-01-01: `sanitizeSegment` kept as-is (trim only); validation added as a separate `MAVEN_SEGMENT_RE` check after trimming in `parseMavenSpecifier`. Path-traversal test uses `../../../etc` which contains `/` characters — outside `[a-zA-Z0-9._-]`. Error message includes the offending segment and the specifier string.

2025-01-01: `readClassMetadata` timeout: `timeoutMs` moved outside the `try` block so it's accessible in `catch`. `execSync` receives `{ timeout: timeoutMs }`. On timeout, `execSync` throws with either `killed: true` or a non-null `signal` — detected via `asErr.killed || asErr.signal`. The env var `KESTREL_JAVAP_TIMEOUT_MS` overrides the 15 s default.

2025-01-01: 321 compiler tests + 1020 Kestrel tests passing.
