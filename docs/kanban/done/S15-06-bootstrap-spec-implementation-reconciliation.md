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
- Runtime/compiler topology statements are internally consistent across specs and scripts: if normal
  compilation still invokes `node compiler/dist/cli.js`, that behavior is documented explicitly as
  current state rather than contradicted by invariant wording.
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

## Impact analysis

| Area | Change |
|------|--------|
| CLI wrapper | Update `scripts/kestrel` bootstrap command to seed self-hosted classes from Maven bootstrap JAR instead of invoking TypeScript compiler directly. |
| Bootstrap scripts | Keep `scripts/build-bootstrap-jar.sh` as the TypeScript-produced artifact source; ensure `kestrel bootstrap` consumes that artifact. |
| Specs | Reconcile contradictory statements in `docs/specs/11-bootstrap.md` and `docs/specs/09-tools.md` so they match real command paths. |
| Agent guidance | Update `AGENTS.md` bootstrap/CLI notes so cache paths and mode behavior reflect current implementation. |
| Kanban records | Preserve S15-06 as follow-up history and add build notes/tasks completion evidence. |

## Tasks

- [x] Update `scripts/kestrel` `cmd_bootstrap` to validate and install self-hosted classes from `$MAVEN_BOOTSTRAP_JAR` (no direct `node compiler/dist/cli.js` invocation in bootstrap path).
- [x] Keep bootstrap diagnostics actionable for missing runtime JAR, missing bootstrap JAR, and missing required output classes (`Cli_entry.class`, `Cli_main.class`).
- [x] Reconcile `docs/specs/11-bootstrap.md` sections that currently contradict each other about TypeScript usage in steady-state command execution.
- [x] Reconcile `docs/specs/09-tools.md` command topology wording with actual wrapper behavior.
- [x] Update `AGENTS.md` bootstrap/CLI notes (`~/.kestrel/jvm` location and current compile-path behavior).
- [x] Add Build notes entries for any non-obvious reconciliation decisions.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.
- [x] Run `./scripts/run-e2e.sh`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Script integration | `scripts/kestrel` bootstrap path | Verify `kestrel bootstrap` fails clearly when bootstrap JAR is missing and succeeds by installing classes from JAR when present. |
| Regression suite | `cd compiler && npm run build && npm test` | Ensure wrapper/spec reconciliation does not regress compiler behavior. |
| Runtime regression | `./scripts/kestrel test` | Ensure Kestrel toolchain/runtime behavior remains stable after wrapper changes. |
| E2E regression | `./scripts/run-e2e.sh` | Ensure user-visible CLI behavior remains stable across scenario suites. |

## Documentation and specs to update

- [x] `docs/specs/11-bootstrap.md` — reconcile bootstrap invariants and compilation-path wording so sections are non-contradictory.
- [x] `docs/specs/09-tools.md` — align command topology descriptions with `scripts/kestrel` behavior.
- [x] `AGENTS.md` — update bootstrap cache path and mode wording to match current wrapper behavior.

## Build notes

- 2026-04-12: Started implementation.
- 2026-04-12: Updated `kestrel bootstrap` to install self-hosted classes by extracting the Maven bootstrap JAR directly into `$KESTREL_JVM_CACHE`; bootstrap no longer depends on `compiler/dist/cli.js`.
- 2026-04-12: Reconciled specs/docs to describe current behavior explicitly: bootstrap is JAR-based, self-hosted artifacts are required for normal commands, and script compilation currently remains orchestrated through `compile_with_active_compiler` (TypeScript CLI path) pending deeper compiler-path migration.
- 2026-04-12: Verified bootstrap flow (`build-bootstrap-jar`, `kestrel bootstrap`, `kestrel status`) and full required regression suites (`compiler` tests, `kestrel test`, `run-e2e`).
