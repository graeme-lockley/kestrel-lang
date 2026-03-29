# Block Expression Codegen Cleanups

## Sequence: 53
## Tier: 6 — Polish
## Former ID: 20

## Summary

The BlockExpr codegen has several workarounds and magic numbers that should be cleaned up for maintainability. These are internal code quality issues, not user-facing bugs, but they make the codegen harder to understand and extend.

## Current State

- Placeholder padding used instead of explicit next-block-slot tracking.
- Magic number `2` for `blockLocalStart` -- unclear why this value.
- Optional SET_FIELD discard pattern -- sometimes the result of SET_FIELD is discarded with an extra slot.
- Internal `blockEnv` keys are undocumented conventions.
- `$discard` slot pattern for expression statements within blocks.

## Acceptance Criteria

- [ ] Replace placeholder padding with explicit next-block-slot tracking in the local allocator.
- [ ] Replace magic number `2` for `blockLocalStart` with a named constant or computed value with a comment explaining its derivation.
- [ ] Clean up SET_FIELD discard pattern -- either always discard or document when the result is used.
- [ ] Add code comments documenting internal `blockEnv` keys and their purposes.
- [ ] Ensure no regression: all existing tests (compiler unit + Kestrel unit + E2E) continue to pass.

## Spec References

- None (internal code quality)
