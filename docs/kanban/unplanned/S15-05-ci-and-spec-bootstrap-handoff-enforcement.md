# CI And Spec Bootstrap Handoff Enforcement

## Sequence: S15-05
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E15 Bootstrap JAR Self-Hosting Handoff](../epics/unplanned/E15-bootstrap-jar-self-hosting-handoff.md)
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
