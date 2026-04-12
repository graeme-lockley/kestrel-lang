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
