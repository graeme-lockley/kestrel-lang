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

- [ ] A program with a `maven:` import produces a `<ClassName>.kdeps` sidecar.
- [ ] The sidecar contains the correct group:artifact:version coordinates.
- [ ] Duplicate Maven coords are deduplicated in the sidecar.
- [ ] Programs without Maven deps produce no `.kdeps` file (or an empty one).
- [ ] `driver.test.ks` verifies the .kdeps sidecar for a maven-import program.
- [ ] `cd compiler && npm run build && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — Maven dependency specifiers
- `docs/specs/09-tools.md` — Maven classpath resolution

## Risks / Notes

- Maven specifiers don't resolve to `.ks` source files; they resolve to JAR artifacts that
  are downloaded separately. The driver must skip source-graph traversal for `maven:` specifiers.
- Coordinate format may vary (`maven:group/artifact@version` vs `maven://group:artifact:version`);
  check how the TS compiler parses them.
