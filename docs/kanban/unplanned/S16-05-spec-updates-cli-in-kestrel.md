# Spec updates for Kestrel CLI in Kestrel

## Sequence: S16-05
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E16 Kestrel CLI in Kestrel](../epics/unplanned/E16-kestrel-cli-in-kestrel.md)
- Companion stories: S16-01, S16-02, S16-03, S16-04

## Summary

Update `docs/specs/09-tools.md` and `docs/specs/11-bootstrap.md` to accurately reflect the
architecture delivered by S16-01 through S16-04: the trimmed Bash shim, the `KESTREL_ROOT`
environment contract, in-process program execution via `URLClassLoader`, Maven classpath resolution
in Kestrel, and the updated bootstrap pipeline that includes `kestrel/tools/Cli.class` in the
bootstrap JAR.

## Current State

Both spec files were written when the CLI was entirely Bash-based:
- `09-tools.md` §1 describes `scripts/kestrel` delegating to `compiler/dist/cli.js`.
- `09-tools.md` §2.1 (run) mentions spawning `java` as a child process.
- `11-bootstrap.md` §1.1 shows a three-stage pipeline that does not include the CLI class.
- Neither document mentions `KESTREL_ROOT`, `URLClassLoader` in-process execution, or the
  Kestrel-written Maven classpath resolver.

## Relationship to other stories

- **Depends on S16-04**: all implementation changes are complete before specs are updated.
- No other story depends on this one; it is the final story in the epic.

## Goals

### `docs/specs/09-tools.md`

1. §1 Entry Point — update "Topology" to describe the Bash shim (≤ 50 lines) that sets
   `KESTREL_ROOT` and delegates to `kestrel.tools.Cli` via `exec java`. Remove reference to
   `compiler/dist/cli.js` from the normal execution path.
2. §2.1 run — update "Execution" to state that the user program is executed in-process via
   `URLClassLoader` (no child JVM spawned); `System.exit()` terminates the CLI JVM.
3. §2.1 run — update "Maven classpath" to note the resolver is now implemented in
   `kestrel:tools/cli/maven.ks` rather than a Node.js script.
4. Add `KESTREL_ROOT` to the environment variable table (or create one if absent).

### `docs/specs/11-bootstrap.md`

1. §1.1 Architecture Stages — add `kestrel/tools/Cli.class` to the "Bootstrap JAR" and
   "Self-Hosted Classes" boxes.
2. §1.2 Self-Hosted Compiler Entry Points — add `stdlib/kestrel/tools/cli.ks` and describe how
   it is the target of the Bash shim after bootstrap.
3. Add a §1.3 (or equivalent) "Clean-Machine Install" section describing the two-step flow:
   `./scripts/build-bootstrap-jar.sh && ./kestrel bootstrap`, what each step installs, and how
   to verify the machine is fully bootstrapped (`./kestrel status`).
4. Add a §1.4 "Developer Re-Compile" section: how to rebuild the CLI (`kestrel build
   stdlib/kestrel/tools/cli.ks`) and the compiler itself without a full re-bootstrap.

## Acceptance Criteria

- Both spec files accurately describe the post-E16 architecture.
- No spec statement contradicts the actual implementation.
- The clean-machine install walkthrough in the spec can be followed literally to produce a
  working installation.
- §2.1 run in `09-tools.md` no longer states that `java` is spawned as a child process.

## Spec References

- `docs/specs/09-tools.md` — primary file for this story.
- `docs/specs/11-bootstrap.md` — primary file for this story.

## Risks / Notes

- Spec-only story; no code changes. Low risk.
- The spec updates should be done as a single commit with a clear `docs(specs):` message so they
  can be reviewed or reverted independently of code changes.
