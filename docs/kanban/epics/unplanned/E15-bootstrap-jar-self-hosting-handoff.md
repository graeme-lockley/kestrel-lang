# Epic E15: Bootstrap JAR Self-Hosting Handoff

## Status

Unplanned

## Summary

Establish a deterministic bootstrap flow where the TypeScript compiler produces a bootstrap compiler JAR once, then a dedicated command (`./kestrel bootstrap`) uses that JAR to compile the Kestrel compiler into standard self-hosted class outputs; after bootstrap succeeds, normal commands (`kestrel build`, `kestrel run`, `kestrel test`) use only the compiled Kestrel compiler classes by default. The bootstrap JAR is for `kestrel bootstrap` only and is not used as a runtime fallback for normal command execution.

## Stories (ordered — implement sequentially)

1. [S15-01-bootstrap-jar-packaging.md](../../done/S15-01-bootstrap-jar-packaging.md) — ✅ Package TypeScript-produced bootstrap compiler classes into a canonical executable JAR artifact with metadata.
2. [S15-02-kestrel-bootstrap-command.md](../../unplanned/S15-02-kestrel-bootstrap-command.md) — Add `./kestrel bootstrap` to seed self-hosted compiler classes from the bootstrap JAR.
3. [S15-03-compiler-mode-and-provenance-state.md](../../unplanned/S15-03-compiler-mode-and-provenance-state.md) — Add explicit compiler mode/provenance state and visible status reporting.
4. [S15-04-default-cli-self-hosted-compiler-path.md](../../unplanned/S15-04-default-cli-self-hosted-compiler-path.md) — Switch default `build`/`run`/`test` compile paths to self-hosted classes and prevent bootstrap-JAR use in normal flow.
5. [S15-05-ci-and-spec-bootstrap-handoff-enforcement.md](../../unplanned/S15-05-ci-and-spec-bootstrap-handoff-enforcement.md) — Enforce bootstrap handoff in CI and finalize specs/docs for operational use.

## Dependencies

- E14 Self-Hosting Compiler (in progress) - requires stable self-hosted compiler entrypoints and bootstrap verification baseline.
- E13 Stdlib Compiler Readiness (done) - required stdlib/runtime primitives for compiler tooling.
- Existing CLI/runtime integration in scripts and JVM runtime process bridge.

## Implementation Approach

1. Add a bootstrap packaging step (driven by a Bash script) that emits a canonical bootstrap compiler JAR from the TypeScript compiler output with a stable package/entrypoint contract.
2. Add `kestrel bootstrap` to seed self-hosted compiler classes from the bootstrap JAR into the compiler cache layout used by normal commands.
3. Add compiler-mode selection with explicit state/provenance metadata so the active compiler can be audited (`bootstrap-jar` vs `self-hosted`).
4. Switch default command behavior (`build`, `run`, `test`) to self-hosted compiled classes once bootstrap state is valid, and disallow bootstrap-JAR execution in normal command flow.
5. Strengthen CI bootstrap checks to prove no hidden TypeScript/JAR dependency remains after a successful bootstrap handoff.

## Epic Completion Criteria

- `./kestrel bootstrap` exists and succeeds on a clean workspace with required tool prerequisites.
- Bootstrap process uses the bootstrap JAR to compile self-hosted compiler classes into the standard compiler cache/output layout.
- After successful bootstrap, `./kestrel build`, `./kestrel run`, and `./kestrel test` default to self-hosted compiler classes without requiring JAR execution in the normal path.
- Compiler mode/provenance is observable (for example through state metadata or explicit status output), and bootstrap JAR usage is limited to the bootstrap command.
- CI includes a bootstrap handoff check that fails if post-bootstrap commands silently fall back to TypeScript/JAR compiler paths.
- Documentation/specs are updated to describe bootstrap command semantics, default compiler selection, and bootstrap-only JAR policy.
