# Maven .kdeps sidecar handling

## Sequence: S17-11
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01, S17-02, S17-03, S17-04, S17-05, S17-06, S17-07, S17-08, S17-09, S17-10, S17-12, S17-13

## Summary

Detect `maven:` specifiers in source, write `<ClassName>.kdeps` sidecar alongside `.class`
output (group:artifact:version, one per line). Driver does not download JARs; it records
coordinates. `cli.ks` (and `kestrel:tools/cli/maven`) reads these sidecars to build the JVM
classpath.

## Current State

After S17-10, the driver writes `.class.deps` sidecars. Maven specifiers (`maven:group/artifact@version`)
are silently passed through or cause resolution errors. This story adds Maven coordinate
recording.

## Relationship to other stories

- **Depends on**: S17-10 (sidecar infrastructure established)
- **Blocks**: S17-12 (cli.ks uses .kdeps to build Maven classpath before running)

## Goals

1. During dependency resolution, detect specifiers that start with `maven:`.
2. Parse the Maven coordinate from the specifier (group:artifact:version format).
3. After compiling a module, collect all `maven:` specifiers from its transitive dependency
   graph (deduplicated).
4. Write a `<ClassName>.kdeps` file to `outDir` with one coordinate per line (group:artifact:version).
5. If no Maven deps exist, do not write the file (or write an empty file — match TS compiler).

## Acceptance Criteria

- [x] A program with a `maven:` import produces a `<ClassName>.kdeps` sidecar.
- [x] The sidecar contains the correct group:artifact:version coordinates.
- [x] Duplicate Maven coords are deduplicated in the sidecar.
- [x] Programs without Maven deps produce no `.kdeps` file (or an empty one).
- [x] `driver.test.ks` verifies the .kdeps sidecar for a maven-import program.
- [x] `cd compiler && npm run build && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — Maven dependency specifiers
- `docs/specs/09-tools.md` — Maven classpath resolution

## Risks / Notes

- Maven specifiers don't resolve to `.ks` source files; they resolve to JAR artifacts that
  are downloaded separately. The driver must skip source-graph traversal for `maven:` specifiers.
- Coordinate format may vary (`maven:group/artifact@version` vs `maven://group:artifact:version`);
  check how the TS compiler parses them.

---

## Impact analysis

### Files changed

| File | Change |
|------|--------|
| `stdlib/kestrel/tools/compiler/resolve.ks` | Export `isMavenSpecifier`; filter maven: specs out of `uniqueDependencyPaths` so they are never passed to `resolveSpecifier` |
| `stdlib/kestrel/tools/compiler/driver.ks` | Import `{ Object, StrVal }` from json; add `parseMavenGav`, `collectMavenCoords`, `buildKdepsJson`, `writeKdepsFileIfNeeded`; wire into `compileGraph` after successful compilation |
| `stdlib/kestrel/tools/compiler/driver.test.ks` | Add test group verifying `.kdeps` sidecar JSON for a maven-import program; add test that no `.kdeps` is written when no maven deps |
| `docs/specs/07-modules.md` | Confirm/expand `.kdeps` format produced by the self-hosted driver |

### No change needed

- `cli/maven.ks` — already reads `.kdeps` JSON; the format we produce is compatible
- `driver-kti-loading.test.ks` — unaffected

## Tasks

- [x] Add `isMavenSpecifier(spec: String): Bool` export to `resolve.ks`
- [x] Filter maven: specs out of `uniqueDependencyPaths` in `resolve.ks`
- [x] Add JSON constructors import to `driver.ks`: `import { Object, StrVal } from "kestrel:data/json"` and `import * as Json from "kestrel:data/json"`
- [x] Add `parseMavenGav(spec: String): Option<(String, String)>` in `driver.ks` (parses `maven:g:a:v` → `Some(("g:a","v"))`)
- [x] Add `collectMavenCoords(imports: List<ImportDecl>): List<(String, String)>` in `driver.ks` (deduplicates by ga)
- [x] Add `buildKdepsJson(coords: List<(String, String)>): String` in `driver.ks` (compact JSON `{"maven":{...}}`)
- [x] Add `writeKdepsFileIfNeeded(wasCompiled: Bool, entryPath: String, coords: List<(String, String)>, opts: CompileOptions): Task<Option<CompileResult>>` in `driver.ks`
- [x] Wire into `compileGraph`: extract maven coords from `prog.imports`, call `writeKdepsFileIfNeeded` after `writeDepsFileIfCompiled`
- [x] Add test group `"compileFile — kdeps sidecar for maven import"` in `driver.test.ks`
- [x] Add test `"compileFile — no kdeps when no maven imports"` in `driver.test.ks`
- [x] Update `docs/specs/07-modules.md` to describe `.kdeps` JSON format produced by self-hosted driver

## Tests to add

In `driver.test.ks`:
- Test group "compileFile — kdeps sidecar for maven import":
  - Write `module.ks` with `import "maven:org.apache.commons:commons-lang3:3.17.0"` plus a dummy export
  - Compile it
  - Assert `<className>.kdeps` file exists and parses as JSON with `maven.org.apache.commons:commons-lang3 == "3.17.0"`
- Test "compileFile — no kdeps when no maven imports":
  - Compile a simple module with no maven imports
  - Assert `<className>.kdeps` does not exist

## Documentation and specs to update

- `docs/specs/07-modules.md` §maven — note that the self-hosted driver writes `<ClassName>.kdeps` as compact JSON `{"maven":{"g:a":"version",...}}`; no `jars` or `checksums` sections (CLI uses `deriveJarPath` fallback)

## Build notes

- Started implementation.
- Avoided 3-element nested list pattern `g :: a :: v :: []` in `parseMavenGav` — the JVM codegen does not support nested cons patterns beyond 2 levels in a match expression. Used `Lst.head`/`Lst.drop` index-based extraction instead.
- `isMavenSpecifier` added to `resolve.ks` and used to filter maven: specs before `resolveAll` so they never reach the filesystem path resolver.
- `collectMavenCoords` uses an accumulator + Dict for O(n) deduplication by ga key.
- `buildKdepsJson` uses compact JSON via `Json.stringify`; the `jars`/`checksums` sections are not written (CLI's `deriveJarPath` handles the missing jars section).
- 2 new test groups added (74 total in driver); 1932 Kestrel tests pass; 440 compiler tests pass.
