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

## Impact analysis

| Area | Change |
|------|--------|
| Bootstrap state persistence | Add a canonical state/provenance file under `.kestrel/bootstrap/` that records mode, artifact paths, revision, and checksums. |
| Bootstrap command | Extend `kestrel bootstrap` to write/update state metadata only after successful self-hosted class generation. |
| CLI observability | Add user-visible status output (`kestrel status`) to report current compiler mode and provenance details for local debugging/CI assertions. |
| Compiler mode selection foundations | Add deterministic state readers in `scripts/kestrel` that can be consumed by S15-04 command path switching logic. |
| Docs/specs | Document state schema and status command behavior in tooling docs. |

## Tasks

- [x] Define bootstrap compiler state/provenance file location and schema under `.kestrel/bootstrap/`.
- [x] Add state read/write helpers in `scripts/kestrel`.
- [x] Update `cmd_bootstrap` to write `self-hosted` mode state and provenance only on success.
- [x] Add a user-visible status path (`kestrel status`) that prints mode and provenance.
- [x] Ensure fallback/default mode reports `bootstrap-required` when state is missing/invalid.
- [x] Update docs/spec text for state schema and status output.
- [x] Run `./scripts/build-bootstrap-jar.sh`.
- [x] Run `./kestrel bootstrap`.
- [x] Run `./kestrel status`.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| CLI integration | `scripts/kestrel` state helpers and `status` command | Validate missing/invalid state reports `bootstrap-required` and successful bootstrap reports `self-hosted` with provenance fields. |
| Bootstrap/state integration | `./kestrel bootstrap` then `./kestrel status` | Ensure bootstrap updates persistent state and status output reflects active provenance. |
| Compiler regression | `cd compiler && npm run build && npm test` | Ensure state/provenance changes do not regress compiler behavior. |
| Runtime regression | `./scripts/kestrel test` | Ensure runtime/stdlib tests still pass with new state logic. |

## Build notes

- 2026-04-12: Added bootstrap state/provenance persistence at `.kestrel/bootstrap/state.env` and wrote deterministic schema fields from `kestrel bootstrap` after successful class generation.
- 2026-04-12: Introduced `kestrel status`, which reports active compiler mode (`self-hosted` vs `bootstrap-required`) and state/provenance fields for debugging and CI assertions.
- 2026-04-12: Added state helper functions in `scripts/kestrel` (`state_value`, `compiler_mode`) as foundations for S15-04 command path selection.
- 2026-04-12: Verified required gates pass: bootstrap jar build, bootstrap run, status output, compiler tests, and `./scripts/kestrel test`.

## Documentation and specs to update

- [x] `docs/specs/09-tools.md` — document compiler mode state/provenance format and `kestrel status` output contract.
- [x] `AGENTS.md` — add `./kestrel status` in bootstrap troubleshooting/verification guidance.
