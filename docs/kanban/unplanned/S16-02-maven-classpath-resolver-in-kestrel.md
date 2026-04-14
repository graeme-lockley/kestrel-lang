# Maven classpath resolver in Kestrel

## Sequence: S16-02
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E16 Kestrel CLI in Kestrel](../epics/unplanned/E16-kestrel-cli-in-kestrel.md)
- Companion stories: S16-01, S16-03, S16-04, S16-05

## Summary

Replace `scripts/resolve-maven-classpath.mjs` (a ~110-line Node.js script invoked via `node` from
the Bash launcher) with a Kestrel module `kestrel:tools/cli/maven.ks`. The module reads `.kdeps`
JSON sidecar files produced by the compiler, walks the transitive dependency graph via `.class.deps`
files, resolves Maven artefact paths from the `~/.kestrel/maven` cache, detects version conflicts,
and returns the ordered classpath list. This is the last significant Node.js dependency in the
normal execution path.

## Current State

`scripts/resolve-maven-classpath.mjs` is invoked from the Bash `maven_classpath_for_entry`
function:
```bash
node "$MAVEN_CLASSPATH_RESOLVER" "$entry_source" "$class_dir"
```
It:
1. Derives the `.class` file path for a `.ks` entry using the same `classNameForPath` logic as the
   compiler.
2. Reads the `.class.deps` file to discover transitive `.ks` sources.
3. Reads `.kdeps` JSON files beside each `.class` file (produced by the compiler for Maven imports).
4. Merges all `maven:` coordinates, checking for version conflicts.
5. Also handles explicit `jars:` entries in `.kdeps`.
6. Prints resolved JAR paths as a colon-separated string to stdout.

The dependency graph walk, JSON parsing, and Maven cache path construction are straightforward
translations from JavaScript to Kestrel.

`kestrel:io/fs.ks` provides `readText`, `fileExists`, and `stat`.
`kestrel:data/json.ks` provides JSON parsing.
`kestrel:data/dict.ks` and `kestrel:data/list.ks` are available for accumulation.

## Relationship to other stories

- **Independent of S16-01** (`runInProcess`): can be built in any order.
- **Prerequisite for S16-03** (`kestrel:tools/cli`): the CLI needs the resolved classpath to
  build `java_cp` for in-process loading (S16-01) and for sub-process spawning (`dis`).

## Goals

1. `stdlib/kestrel/tools/cli/maven.ks` is created, exporting:
   ```
   export async fun resolveMavenClasspath(
     entrySource: String,
     classDir: String,
     mavenCache: String
   ): Task<Result<List<String>, String>>
   ```
2. The function replicates the full logic of `resolve-maven-classpath.mjs`:
   - Class-name derivation from source path (same algorithm).
   - Transitive `.class.deps` walk.
   - `.kdeps` JSON reading and `maven:` extraction.
   - Conflict detection (same `groupId:artifactId` with differing versions → `Err`).
   - `jars:` explicit path support.
   - Maven cache path construction:
     `<mavenCache>/<groupId path>/<artifactId>/<version>/<artifactId>-<version>.jar`
3. Unit tests in `stdlib/kestrel/tools/cli/maven.test.ks` covering: a simple resolve, conflict
   detection, and `jars:` entries.
4. `scripts/resolve-maven-classpath.mjs` is retained (but becomes dead code with respect to the
   main path) until the Bash shim is removed in S16-04.

## Acceptance Criteria

- `resolveMavenClasspath` returns the same ordered JAR set as `resolve-maven-classpath.mjs` for
  the same inputs (verified against the existing Node.js script in integration).
- Version conflict → `Err(...)` with a human-readable message.
- Missing `.kdeps` file (no Maven deps) → `Ok([])`.
- All existing tests using the Node.js resolver still pass (until S16-04, it is still used by the
  current Bash shim).

## Spec References

- `docs/specs/09-tools.md` §2.1 (run — Maven classpath).

## Risks / Notes

- **JSON parsing**: `kestrel:data/json.ks` must support parsing object fields as `Dict`; confirm
  this works for the `.kdeps` shape `{ "maven": { "group:artifact": "version" }, "jars": [...] }`
  before committing to this approach.
- **`classNameForPath` duplication**: currently in the Bash script, `resolve-maven-classpath.mjs`,
  and (for the internal compiler gate) in TypeScript. This story introduces a canonical Kestrel
  implementation; S16-03 will use the same function for the CLI's own class-name derivation.
