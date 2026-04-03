# Improve `await` Type-Error Diagnostic Message

## Sequence: S01-16
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)

## Summary

When `await` is applied to an expression that does not resolve to `Task<T>`, the type checker emits the generic message `"await expects Task<T> type"`. This gives the developer no indication of what type was actually inferred, making the error harder to diagnose. The message should include the resolved type, e.g. `"await expects Task<T> but got Int"`.

## Current State

```typescript
// compiler/src/typecheck/check.ts (AwaitExpr handler)
} else {
    throw new TypeCheckError('await expects Task<T> type', expr);
}
```

The actual resolved type is available at that point (`applied` after `apply(taskT)`) but is not included in the error message.

## Relationship to other stories

- Standalone; no dependencies beyond the existing type-checker infrastructure.
- S01-14 (inAsyncContext refactor) does not affect this change.

## Goals

1. The `await`-on-non-Task error message includes the actual inferred type rendered as a human-readable string.
2. The format is consistent with other type-mismatch diagnostics in the codebase.
3. The `"await can only be used in async contexts"` message is unaffected.

## Acceptance Criteria

- Applying `await` to an `Int` produces a message containing `"Int"` (or equivalent).
- A typecheck conformance test or compiler unit test verifies the new message text.
- `cd compiler && npm test` passes.

## Spec References

- `docs/specs/10-compile-diagnostics.md` — add entry for the improved `await` diagnostic if a diagnostics catalogue is maintained there.

## Risks / Notes

- Requires a `typeToString` (or equivalent) utility to render `InternalType` → human-readable. Verify one already exists before writing a new one.
- Avoid over-engineering: the rendered string does not need to be identical to surface syntax, just recognisable.

## Impact analysis

| Area | Change |
|------|--------|
| Type checker `check.ts` | Change `'await expects Task<T> type'` → `` `await expects Task<T> but got ${typeStr(applied)}` `` |
| Tests | New conformance typecheck invalid test |

## Tasks

- [x] In `check.ts` `AwaitExpr` handler: change error message to include `typeStr(applied)`
- [x] Add `tests/conformance/typecheck/invalid/await_non_task_type.ks`
- [x] Run `cd compiler && npm run build && npm test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance typecheck | `tests/conformance/typecheck/invalid/await_non_task_type.ks` | Verify error message includes the actual type |

## Documentation and specs to update

No spec changes needed — `docs/specs/10-compile-diagnostics.md` is a framework spec, not a message catalogue.

## Build notes

- 2026-03-07: `typeStr` already available at module scope; no new utility needed. `npm test` 231/231.
