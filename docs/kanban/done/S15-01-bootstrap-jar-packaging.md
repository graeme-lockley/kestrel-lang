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

## Impact analysis

| Area | Change |
|------|--------|
| Scripts | Add a dedicated Bash packaging script (`scripts/build-bootstrap-jar.sh`) that builds compiler/runtime prerequisites, compiles `cli-entry.ks`, and assembles a bootstrap JAR in `.kestrel/bootstrap/compiler/`. |
| CLI/tooling integration | No command mode switch yet; this story only produces a deterministic bootstrap artifact and metadata for later stories (`kestrel bootstrap`, compiler mode selection). |
| Cache layout | Introduce stable bootstrap artifact path under `.kestrel/bootstrap/compiler/` with JAR + metadata sidecar files. |
| Tests/verification | Add script-level smoke checks to validate JAR creation, required classes present in the JAR, and metadata generation. |
| Specs/docs | Update tools spec to document bootstrap JAR packaging command, output location, and bootstrap-only usage intent. |

## Tasks

- [x] Add `scripts/build-bootstrap-jar.sh` (Bash) that resolves repo root, verifies prerequisites, and writes artifacts to `.kestrel/bootstrap/compiler/`.
- [x] In `scripts/build-bootstrap-jar.sh`, compile `stdlib/kestrel/tools/compiler/cli-entry.ks` using the TypeScript compiler into a temporary classes directory in `.kestrel/bootstrap/compiler/`.
- [x] Package the compiled classes into a canonical bootstrap JAR (for example `compiler-bootstrap.jar`) using `jar` with deterministic pathing.
- [x] Generate metadata sidecars (at minimum checksum and source revision) alongside the JAR.
- [x] Add verification checks in the script to fail if required entry classes (`Cli_entry`, `Cli_main`) are absent from the JAR.
- [x] Update docs/spec text to describe script usage and `.kestrel/bootstrap/compiler/` output layout.
- [x] Run `bash -n scripts/build-bootstrap-jar.sh`.
- [x] Run `./scripts/build-bootstrap-jar.sh`.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Script smoke | `scripts/build-bootstrap-jar.sh` (direct invocation) | Verify script emits JAR + metadata under `.kestrel/bootstrap/compiler/` on a clean workspace. |
| Artifact integrity | `jar tf .kestrel/bootstrap/compiler/compiler-bootstrap.jar` checks (script-embedded) | Ensure `Cli_entry.class` and `Cli_main.class` are included in packaged bootstrap artifact. |
| Regression | `cd compiler && npm run build && npm test` | Ensure packaging work does not regress TypeScript compiler behavior. |
| Regression | `./scripts/kestrel test` | Ensure runtime/stdlib behavior remains stable after packaging script introduction. |

## Build notes

- 2026-04-12: Added `scripts/build-bootstrap-jar.sh` to package a canonical bootstrap compiler JAR into `.kestrel/bootstrap/compiler/` with prerequisite checks and deterministic output paths.
- 2026-04-12: Implemented entry-class integrity checks for `Cli_entry` and `Cli_main`, and wrote bootstrap metadata sidecars (`compiler-bootstrap.meta`, checksum, revision).
- 2026-04-12: Verified required gates pass: script syntax check, bootstrap packaging run, compiler build/tests, and `./scripts/kestrel test`.

## Documentation and specs to update

- [x] `docs/specs/09-tools.md` — add bootstrap-JAR packaging script usage (`scripts/build-bootstrap-jar.sh`), output path (`.kestrel/bootstrap/compiler/`), and bootstrap-only usage policy.
- [x] `AGENTS.md` — add the packaging script command in build/test references for self-hosting workflows.
