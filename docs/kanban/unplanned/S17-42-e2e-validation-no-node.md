# End-to-end validation without Node; CI gate and spec update

## Sequence: S17-42
## Tier: 9
## Former ID: S17-13 (then S17-23, then S17-39)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01 through S17-41

## Summary

Rename `compiler/` to verify the full test suite (1855+ tests) passes with Node unreachable.
Add a CI step that runs `mv compiler compiler_DISABLED && ./kestrel test` and must exit 0.
Restore `compiler/`. Update `docs/specs/11-bootstrap.md` and
`docs/specs/12-agent-enablement-and-knowledge.md` to reflect the JVM-only runtime path.

## Current State

After S17-22, the self-hosted typechecker and codegen have parity with the TypeScript
compiler for every top-level construct used by the stdlib. This story validates that the
full test suite passes with the TypeScript compiler removed and adds a permanent CI gate.

## Relationship to other stories

- **Depends on**: S17-12 (CLI wired to driver) and the gap-closure stories S17-16..S17-22 which together remove every "Unsupported top-level declaration" or "Unsupported expression form" diagnostic raised by the self-hosted checker for stdlib inputs.
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

