# End-to-end validation without Node; CI gate and spec update

## Sequence: S17-13
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01, S17-02, S17-03, S17-04, S17-05, S17-06, S17-07, S17-08, S17-09, S17-10, S17-11, S17-12

## Summary

Rename `compiler/` to verify the full test suite (1855+ tests) passes with Node unreachable.
Add a CI step that runs `mv compiler compiler_DISABLED && ./kestrel test` and must exit 0.
Restore `compiler/`. Update `docs/specs/11-bootstrap.md` and
`docs/specs/12-agent-enablement-and-knowledge.md` to reflect the JVM-only runtime path.

## Current State

After S17-12, the driver is wired into the CLI. But the test suite still uses Node/TypeScript
for compilation in many paths. This story validates that everything works with Node removed.

## Relationship to other stories

- **Depends on**: S17-12 (CLI wired to driver)
- **Blocks**: nothing — this is the final story in the epic.

## Goals

1. Temporarily rename `compiler/` to `compiler_DISABLED/` and run `./kestrel test`.
2. Fix any remaining failures that reveal Node dependency paths.
3. Restore `compiler/`.
4. Add a CI gate (script or workflow step) that automates this validation.
5. Update `docs/specs/11-bootstrap.md` §1 and §2 to describe the JVM-only runtime path.
6. Update `docs/specs/12-agent-enablement-and-knowledge.md` to reflect that Node is no longer
   a runtime dependency.

## Acceptance Criteria

- [ ] `./kestrel test` passes with `compiler/` renamed/absent.
- [ ] A CI gate script (`scripts/test-no-node.sh` or workflow step) exists and is documented.
- [ ] `docs/specs/11-bootstrap.md` reflects the JVM-only runtime path.
- [ ] `docs/specs/12-agent-enablement-and-knowledge.md` reflects the JVM-only runtime path.
- [ ] `cd compiler && npm run build && npm test` passes (TypeScript tests still pass with compiler present).
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/11-bootstrap.md` — bootstrap and self-hosted pipeline
- `docs/specs/12-agent-enablement-and-knowledge.md` — agent/tool knowledge

## Risks / Notes

- Some E2E tests or fixtures may still invoke `node` indirectly (e.g. via `scripts/kestrel`
  Bash shim). Audit all test fixtures.
- The CI gate must restore `compiler/` after the test to avoid breaking the TypeScript build.
- The `compiler/dist/cli.js` path may still be needed for the bootstrap process (building the
  bootstrap JAR); document this clearly in the spec.
