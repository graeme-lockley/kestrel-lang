# Bootstrap Spec and Implementation Reconciliation

## Sequence: S15-06
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E15 Bootstrap JAR Self-Hosting Handoff](../epics/done/E15-bootstrap-jar-self-hosting-handoff.md)

## Summary

Reconcile current bootstrap and command-dispatch implementation with the canonical behavior in
`docs/specs/11-bootstrap.md`, ensuring steady-state command execution and bootstrap flow match the
documented invariants and command contracts.

## Current State

E15 and `docs/specs/11-bootstrap.md` define bootstrap JAR handoff and self-hosted mode gating as
completed. Current wrapper behavior still shows drift in two critical areas:

1. Normal compile paths still invoke `node compiler/dist/cli.js` in `scripts/kestrel`.
2. `kestrel bootstrap` currently invokes the TypeScript compiler CLI directly instead of seeding
   self-hosted classes from the bootstrap JAR artifact.

This creates a mismatch between story records, current spec text, and operational behavior.

## Relationship to other stories

- Follow-up to E15 completed stories, especially S15-02 and S15-04.
- Depends on existing bootstrap JAR packaging flow from S15-01.
- Should land before any additional bootstrap topology cleanup/closure work on E14.

## Goals

1. Align `kestrel bootstrap` behavior with `docs/specs/11-bootstrap.md` bootstrap-JAR seeding flow.
2. Align default `kestrel build`, `kestrel run`, and `kestrel test` compile paths with documented
   self-hosted steady-state behavior.
3. Remove contradictory wording across kanban and spec artifacts, or explicitly scope transitional
   exceptions when needed.

## Acceptance Criteria

- `kestrel bootstrap` seeds self-hosted compiler classes from the bootstrap JAR path specified by
  bootstrap tooling and does not require direct TypeScript compiler CLI invocation in the bootstrap
  command path.
- In `self-hosted` mode, normal command execution does not invoke `node compiler/dist/cli.js`.
- `docs/specs/09-tools.md`, `docs/specs/11-bootstrap.md`, and affected kanban records describe the
  same runtime/compiler topology without internal contradictions.
- Regression suites used in bootstrap handoff validation continue to pass.

## Spec References

- `docs/specs/09-tools.md`
- `docs/specs/11-bootstrap.md`
- `AGENTS.md`
- `docs/kanban/epics/done/E15-bootstrap-jar-self-hosting-handoff.md`

## Risks / Notes

- Behavior changes in command dispatch can regress less-common flags (`--status`, `--refresh`,
  `--clean`, `--allow-http`) and require targeted smoke coverage.
- CI may currently pass due to environmental assumptions; reconciliation should include explicit
  checks for hidden TypeScript fallback in post-bootstrap mode.
- If full reconciliation is too large for one story, split into implementation and doc-sync child
  stories while keeping this story as the umbrella roadmap item.
