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

## Impact analysis

| Area | Change |
|------|--------|
| `docs/specs/09-tools.md` | Update entry-point topology to reflect the minimal Bash shim and delegation to `kestrel.tools.Cli`; document `KESTREL_ROOT`; update `run` execution and Maven resolver details |
| `docs/specs/11-bootstrap.md` | Update architecture stages to include `kestrel/tools/Cli.class`; document CLI handoff after bootstrap; add clean-machine install and developer re-compile flow |
| Kanban records | Move story through `planned/` and `doing/` to `done/` with checklist completion and build notes |

## Tasks

- [x] Expand `docs/specs/09-tools.md` §1 Entry Point:
   - Describe the ≤50-line Bash shim contract and `KESTREL_ROOT` export
   - Document delegation to self-hosted `kestrel.tools.Cli` for normal commands
- [x] Update `docs/specs/09-tools.md` §2.1 run:
   - Replace child-JVM wording with in-process `URLClassLoader` execution semantics
   - State that Maven classpath resolution is implemented in Kestrel (`kestrel:tools/cli/maven`)
- [x] Update `docs/specs/11-bootstrap.md`:
   - Revise architecture stage diagram/text to include `kestrel/tools/Cli.class` in bootstrap JAR and JVM cache
   - Extend entry point section with `stdlib/kestrel/tools/cli.ks` handoff role
   - Add clean-machine install walkthrough and developer re-compile workflow sections
- [x] Verify consistency between `09-tools.md` and `11-bootstrap.md` for bootstrap, status, and command delegation behavior
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| N/A (spec-only) | N/A | No new runtime/compiler behavior introduced; verification is consistency review plus existing full test suite runs |

## Documentation and specs to update

- [x] `docs/specs/09-tools.md` — update §1 Entry Point topology and §2.1 `run` execution/classpath language to match post-E16 architecture
- [x] `docs/specs/11-bootstrap.md` — update architecture stages, entry-point ownership, clean-machine install flow, and developer re-compile workflow

## Build notes

- 2026-04-15: Updated both spec documents to reflect the post-E16 architecture where `scripts/kestrel`
   is a minimal bootstrap/build shim and normal commands delegate to `kestrel/tools/Cli.class`.
- 2026-04-15: Corrected stale bootstrap wording that implied `kestrel bootstrap` recompiles sources;
   it now documents extraction from the Maven-cached bootstrap JAR and includes `tools/Cli.class`.
- 2026-04-15: Verification runs completed: compiler suite `440 passed`. Kestrel test suite reported
   `1854 passed`; command exits non-zero due existing async-quiescence warning behavior unrelated to
   this spec-only change.
