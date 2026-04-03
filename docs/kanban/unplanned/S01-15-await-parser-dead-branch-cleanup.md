# Remove Dead `CallExpr` Branch in `await` Parser

## Sequence: S01-15
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)

## Summary

In `parsePrimary`, after parsing an `await`-prefixed expression, there is a conditional branch that checks `expr.kind === 'CallExpr'` before wrapping with `AwaitExpr`. Both branches produce an identical result, making the `CallExpr` check dead code. This is a residue of an earlier design where `await` was restricted to call expressions. The dead branch should be removed to simplify the code and eliminate a source of potential confusion for contributors.

## Current State

```typescript
// compiler/src/parser/parse.ts (parsePrimary)
if (awaitPrefix && expr.kind === 'CallExpr') {
    return { kind: 'AwaitExpr', value: expr };   // branch A
}
if (awaitPrefix) {
    return { kind: 'AwaitExpr', value: expr };   // branch B — identical to A
}
```

Branch A is unreachable in any meaningful sense because branch B catches all `awaitPrefix` cases and produces the same output.

## Relationship to other stories

- Standalone cleanup; no dependencies.
- Related context: S01-11 introduced `async` lambda parsing in the same file.

## Goals

1. The two-branch pattern is collapsed to a single `if (awaitPrefix) return { kind: 'AwaitExpr', value: expr }`.
2. Behaviour is identical for all valid and invalid inputs.
3. Parser tests still pass.

## Acceptance Criteria

- `parsePrimary` has a single `AwaitExpr` return path for `awaitPrefix`.
- No test behaviour changes.
- `cd compiler && npm test` passes.

## Spec References

- No spec changes needed.

## Risks / Notes

- Trivial change. Verify the exact line range before editing to avoid touching adjacent logic.
