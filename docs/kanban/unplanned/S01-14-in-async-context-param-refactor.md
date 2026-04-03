# Refactor `inAsyncContext` as Explicit Parameter

## Sequence: S01-14
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)

## Summary

The type checker tracks whether the current expression is inside an async context using a mutable module-level boolean `inAsyncContext` that is manually saved and restored at every scope boundary. This is fragile: any exception thrown without a matching `finally` block leaks the flag, any reordering of `inferExpr` calls would silently corrupt context, and the pattern must be replicated by every new scope-introducing construct (e.g. S01-12 block-local async fun). This story refactors `inAsyncContext` into an explicit parameter threaded through `inferExpr` and friends.

## Current State

```typescript
// compiler/src/typecheck/check.ts, line 95
let inAsyncContext = false; // Track if we're in an async function
```

Every scope boundary does:
```typescript
const wasAsync = inAsyncContext;
if (node.async) inAsyncContext = true;
// ... inferExpr(body) ...
inAsyncContext = wasAsync;
```

## Relationship to other stories

- S01-12 (block-local async fun) becomes simpler if this refactor is done first.
- S01-11 (async lambda) introduced the same save/restore pattern — this would clean it up.
- No runtime changes; type-checker only.

## Goals

1. `inAsyncContext` is removed as module-level state.
2. `inferExpr` (and any helper that checks or propagates async context) accepts an explicit `asyncContext: boolean` parameter.
3. All call sites updated; `FunDecl`, `LambdaExpr`, and `FunStmt` pass the correct value.
4. `AwaitExpr` check reads from the parameter rather than the closure variable.
5. Behaviour is identical; no existing test should change outcome.

## Acceptance Criteria

- No module-level `inAsyncContext` variable exists in `check.ts`.
- `inferExpr` signature includes `asyncContext: boolean` (or equivalent).
- All existing type checker tests pass unchanged.
- `cd compiler && npm test` passes.

## Spec References

- No spec changes needed — this is a compiler-internal refactor.

## Risks / Notes

- `inferExpr` is called in many places; the signature change will touch a large number of call sites.
- Prefer a single pass through the file with a clear mechanical substitution rather than ad-hoc edits.
- If `inferExpr` is also called from the JVM codegen (it shouldn't be, but verify), those call sites also need updating.
