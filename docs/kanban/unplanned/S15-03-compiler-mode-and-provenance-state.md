# Compiler Mode And Provenance State

## Sequence: S15-03
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E15 Bootstrap JAR Self-Hosting Handoff](../epics/unplanned/E15-bootstrap-jar-self-hosting-handoff.md)
- Companion stories: S15-01, S15-02, S15-04, S15-05

## Summary

Add explicit compiler mode state and provenance metadata so Kestrel commands can determine and report whether bootstrap has completed and self-hosted compiled classes are active; bootstrap JAR usage remains limited to `kestrel bootstrap` and not normal command execution.

## Current State

Compiler selection is implicit and mostly environment-driven (`KESTREL_CLI_TS_FALLBACK`, `KESTREL_JVM_CACHE`). There is no persistent bootstrap-state file or command that reports active compiler source/provenance.

## Relationship to other stories

- **Depends on**: S15-02 (`kestrel bootstrap`) producing a canonical self-hosted compiler output.
- **Blocks**: S15-04 default command behavior switch and S15-05 CI assertions.

## Goals

1. Define compiler mode states (at minimum `bootstrap-required` and `self-hosted`) and persistence format.
2. Write/update state as part of `kestrel bootstrap` and explicit recovery transitions.
3. Expose mode/provenance in a user-visible status path (for example `kestrel build --status` extension or dedicated status command output).

## Acceptance Criteria

- A persisted state/provenance record exists after bootstrap and identifies active compiler mode and artifact revision/hash.
- Normal CLI execution can read this state and choose compiler path deterministically.
- Bootstrap JAR execution is only used by `kestrel bootstrap`; normal CLI flow never switches to JAR compile mode.

## Spec References

- `docs/specs/09-tools.md`
- `scripts/kestrel`
- `scripts/test-compiler-bootstrap`

## Risks / Notes

- Silent fallback defeats epic intent; mode transitions must be explicit and observable.
- State schema changes should be forward-compatible to avoid breaking older caches.
- Mode reporting should be concise enough for CI log assertions.
