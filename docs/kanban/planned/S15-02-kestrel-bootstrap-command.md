# Kestrel Bootstrap Command

## Sequence: S15-02
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E15 Bootstrap JAR Self-Hosting Handoff](../epics/unplanned/E15-bootstrap-jar-self-hosting-handoff.md)
- Companion stories: S15-01, S15-03, S15-04, S15-05

## Summary

Introduce an explicit `./kestrel bootstrap` command that uses the bootstrap compiler JAR to compile the self-hosted compiler into the standard compiler cache/output layout used by normal Kestrel commands.

## Current State

`scripts/kestrel` does not have a `bootstrap` command. Bootstrapping is currently split across ad hoc verification scripts (`bootstrap-stage0.sh`, `bootstrap-stage1.sh`, `test-compiler-bootstrap`) rather than a first-class CLI operation.

## Relationship to other stories

- **Depends on**: S15-01 bootstrap JAR packaging.
- **Blocks**: S15-03 compiler mode/provenance state, S15-04 default command path switch.

## Goals

1. Add `bootstrap` to CLI usage/help and command dispatch in `scripts/kestrel`.
2. Implement bootstrap flow that invokes the bootstrap JAR compiler entrypoint to build self-hosted compiler classes into the canonical cache location.
3. Return actionable diagnostics when bootstrap prerequisites are missing (JAR absent, runtime unavailable, compile failure).

## Acceptance Criteria

- `./kestrel bootstrap` exists and exits 0 on success in a clean checkout with prerequisites installed.
- Successful bootstrap writes self-hosted compiler classes to the canonical cache layout expected by `kestrel build/run/test`.
- Failure output clearly identifies whether the problem is missing artifacts, classpath/runtime setup, or compile errors.

## Spec References

- `docs/specs/09-tools.md`
- `scripts/kestrel`
- `stdlib/kestrel/tools/compiler/cli-entry.ks`

## Risks / Notes

- Bootstrap should be idempotent: repeated invocations should refresh safely without requiring manual cache cleanup.
- Avoid recursive invocation loops between shell CLI and self-hosted CLI dispatch when adding the new command.
- Keep bootstrap implementation deterministic so CI can compare outputs across runs.

## Impact analysis

| Area | Change |
|------|--------|
| CLI wrapper | Add a first-class `bootstrap` command to `scripts/kestrel` usage/help and dispatch. |
| Bootstrap execution path | Invoke `.kestrel/bootstrap/compiler/compiler-bootstrap.jar` with runtime classpath to compile `stdlib/kestrel/tools/compiler/cli-entry.ks` into canonical self-hosted class output under `.kestrel/bootstrap/self-hosted/`. |
| Prerequisite handling | Add actionable failure diagnostics for missing Java, missing runtime JAR, missing bootstrap JAR, and bootstrap compile failures. |
| Idempotence/cache behavior | Ensure `kestrel bootstrap` recreates/refreshes output directories safely and consistently on repeated runs. |
| Docs/specs | Update tools spec and project agent guidance for `kestrel bootstrap` semantics and artifact locations. |

## Tasks

- [ ] Update `scripts/kestrel` usage/help and command dispatch to include `bootstrap`.
- [ ] Implement `cmd_bootstrap` in `scripts/kestrel` that validates prerequisites and invokes the bootstrap compiler JAR against `stdlib/kestrel/tools/compiler/cli-entry.ks`.
- [ ] Write bootstrap output classes to a canonical cache location (for example `.kestrel/bootstrap/self-hosted/`) used by subsequent stories.
- [ ] Ensure `cmd_bootstrap` is idempotent and refreshes output safely.
- [ ] Add clear, specific error messages for missing runtime/bootstrap artifacts and bootstrap compilation failures.
- [ ] Update docs/spec guidance for `kestrel bootstrap` usage and expected outputs.
- [ ] Run `./scripts/build-bootstrap-jar.sh`.
- [ ] Run `./kestrel bootstrap`.
- [ ] Run `cd compiler && npm run build && npm test`.
- [ ] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| CLI integration | `scripts/kestrel` (`bootstrap` command path) | Ensure bootstrap command dispatches correctly and exits with actionable errors on missing prerequisites. |
| Bootstrap smoke | `./kestrel bootstrap` | Validate bootstrap JAR compiles self-hosted compiler classes into canonical output location. |
| Compiler regression | `cd compiler && npm run build && npm test` | Ensure bootstrap command changes do not regress TypeScript compiler/test pipeline. |
| Runtime regression | `./scripts/kestrel test` | Ensure runtime/stdlib behavior remains stable with new bootstrap command wiring. |

## Documentation and specs to update

- [ ] `docs/specs/09-tools.md` — add `kestrel bootstrap` command semantics, prerequisites, and output layout.
- [ ] `AGENTS.md` — include `./kestrel bootstrap` in bootstrap verification guidance.
