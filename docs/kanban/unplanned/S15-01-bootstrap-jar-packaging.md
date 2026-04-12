# Bootstrap Compiler JAR Packaging

## Sequence: S15-01
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E15 Bootstrap JAR Self-Hosting Handoff](../epics/unplanned/E15-bootstrap-jar-self-hosting-handoff.md)
- Companion stories: S15-02, S15-03, S15-04, S15-05

## Summary

Create a deterministic Stage-0 packaging flow, controlled by a Bash script, that compiles the executable self-hosted compiler entrypoint with the TypeScript compiler and bundles the resulting classes into a canonical bootstrap compiler JAR with a stable package/entrypoint contract.

## Current State

Bootstrap scripts currently compile class files into cache directories (`.kestrel/bootstrap-stage0`, `.kestrel/bootstrap-stage1`, `.kestrel/compiler-bootstrap-test`) but do not produce a single versioned bootstrap JAR artifact managed by a dedicated packaging script. `scripts/kestrel` still drives TypeScript compilation directly via `compiler/dist/cli.js`.

## Relationship to other stories

- **Foundational for**: S15-02 (bootstrap command), S15-03 (compiler mode state), S15-04 (default command path switch), S15-05 (CI handoff enforcement).
- **Depends on**: E14 self-hosted compiler entrypoints being available and compilable.

## Goals

1. Define canonical bootstrap compiler package naming and JVM entrypoint class contract.
2. Add a dedicated Bash script (for example `scripts/build-bootstrap-jar.sh`) to emit a reproducible bootstrap compiler JAR artifact from TypeScript compiler output.
3. Place JAR and metadata outputs under the `.kestrel` cache tree (for example `.kestrel/bootstrap/compiler/`) for predictable discovery by `kestrel bootstrap`.
4. Record artifact metadata (version/hash/build timestamp) sufficient for later mode/provenance checks.

## Acceptance Criteria

- A dedicated Bash script emits a JAR containing compiler entry classes (`Cli_entry`, `Cli_main`) and required dependencies.
- Running `java -cp <runtime.jar>:<bootstrap-jar> <entry-class> build <file.ks>` is supported and documented.
- Bootstrap JAR and metadata are written inside the `.kestrel` cache directory (under a documented subpath).
- Artifact metadata (for example checksum and source revision) is written alongside the JAR.

## Spec References

- `docs/specs/09-tools.md`
- `scripts/kestrel`
- `scripts/bootstrap-stage0.sh`
- `scripts/bootstrap-stage1.sh`

## Risks / Notes

- JAR packaging must preserve classpath expectations used by runtime JAR and existing `main_class_for` naming.
- Reproducibility can drift if artifact metadata writes non-deterministic content into the JAR payload instead of sidecars.
- Keep packaging isolated from command selection logic; mode switching is handled in later stories.
- The JAR produced here is a bootstrap-only artifact and should not become a normal runtime compile fallback.
