# CI And Spec Bootstrap Handoff Enforcement

## Sequence: S15-05
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E15 Bootstrap JAR Self-Hosting Handoff](../epics/done/E15-bootstrap-jar-self-hosting-handoff.md)
- Companion stories: S15-01, S15-02, S15-03, S15-04

## Summary

Harden CI and documentation/specs so bootstrap handoff invariants are enforced: once bootstrapped, command execution must use self-hosted compiler paths by default, and CI must fail on hidden fallback usage.

## Current State

CI includes bootstrap-smoke commands, but handoff guarantees are not fully enforced. Specs still describe TypeScript-centered topology with staged readiness notes and do not yet define `kestrel bootstrap` as the canonical transition command.

## Relationship to other stories

- **Depends on**: S15-04 default self-hosted command path switch.
- **Final story** in E15; validates the full epic outcomes.

## Goals

1. Add CI assertions that verify post-bootstrap commands run in self-hosted mode and fail if silent fallback occurs.
2. Update specs and guides with final bootstrap handoff contract and operational recovery procedure.
3. Ensure bootstrap verification scripts and CI jobs are aligned on the same mode/provenance expectations.

## Acceptance Criteria

- CI includes a bootstrap handoff gate that fails when post-bootstrap command execution falls back without explicit opt-in.
- `docs/specs/09-tools.md` documents `kestrel bootstrap`, default self-hosted mode, and explicit fallback semantics.
- User-facing docs and AGENTS guidance are consistent with the new bootstrap command and mode contract.

## Spec References

- `docs/specs/09-tools.md`
- `docs/guide.md`
- `AGENTS.md`
- `.github/workflows/ci.yml`

## Risks / Notes

- CI checks must avoid brittle log matching; prefer explicit status/provenance signals where possible.
- Documentation drift is likely while mode transition is in flight; treat spec updates as part of done criteria.
- Ensure migration notes include rollback instructions for maintainers when bootstrap artifacts break.

## Impact analysis

| Area | Change |
|------|--------|
| CI workflow | Add explicit bootstrap handoff gate: build bootstrap JAR, run `kestrel bootstrap`, assert `kestrel status` reports `self-hosted`, and run representative post-bootstrap commands. |
| Fallback enforcement | Add CI assertions that fail if mode is not self-hosted after bootstrap, preventing silent fallback in post-bootstrap flow. |
| Specs/docs | Finalize tools spec language around bootstrap command, mode contract, and fallback semantics. |
| Contributor guidance | Align AGENTS/guide workflow with status/provenance checks and recovery instructions. |

## Tasks

- [x] Update `.github/workflows/ci.yml` to include an explicit bootstrap handoff gate using `./scripts/build-bootstrap-jar.sh`, `./kestrel bootstrap`, and `./kestrel status` assertions.
- [x] Add CI post-bootstrap command checks (`./kestrel build`, `./kestrel run`, `./kestrel test --summary`) that run after status confirms `self-hosted` mode.
- [x] Ensure CI fails fast when `./kestrel status` does not report `compiler mode: self-hosted` post-bootstrap.
- [x] Update docs/spec references to the final bootstrap handoff contract and fallback semantics.
- [x] Run `./scripts/build-bootstrap-jar.sh`.
- [x] Run `./kestrel bootstrap`.
- [x] Run `./kestrel status` and verify `self-hosted`.
- [x] Run `./kestrel build hello.ks && ./kestrel run hello.ks && ./kestrel test --summary`.
- [x] Run `cd compiler && npm run build && npm test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| CI gate | `.github/workflows/ci.yml` bootstrap handoff step | Ensure CI fails when post-bootstrap mode is not `self-hosted`. |
| Command smoke | CI post-bootstrap `build/run/test` checks | Verify steady-state command path remains functional after bootstrap. |
| Local regression | `cd compiler && npm run build && npm test` | Ensure CI/spec hardening changes do not regress compiler tests. |

## Documentation and specs to update

- [x] `docs/specs/09-tools.md` — finalize bootstrap handoff enforcement language and fallback semantics.
- [x] `docs/guide.md` — document operational bootstrap sequence and status-based troubleshooting.
- [x] `AGENTS.md` — align bootstrap verification and CI expectations with `kestrel status` contract.

## Build notes

- 2026-04-12: Added a dedicated CI bootstrap handoff gate that builds the bootstrap JAR, runs `./kestrel bootstrap`, asserts `compiler mode: self-hosted`, and then executes post-bootstrap `build`/`run`/`test` smoke commands.
- 2026-04-12: Updated bootstrap contract wording in AGENTS and tools spec to remove stale Stage-1 fallback language and align with bootstrap-only JAR policy.
