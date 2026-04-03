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

## Impact analysis

| Area | Change |
|------|--------|
| Type checker `compiler/src/typecheck/check.ts` | Remove `let inAsyncContext = false`, add `asyncCtx: boolean` parameter to `inferExpr`; update all ~51 call sites; `AwaitExpr` uses parameter instead of closure variable; scope-introducing constructs (FunDecl, LambdaExpr, FunStmt) pass computed value directly |

## Tasks

- [x] Change `inferExpr(expr: Expr): InternalType` to `inferExpr(expr: Expr, asyncCtx: boolean): InternalType`
- [x] Change `if (!inAsyncContext)` → `if (!asyncCtx)` in `AwaitExpr` handler
- [x] In `LambdaExpr`: remove `wasAsync` save/restore, pass `expr.async` directly to `inferExpr(expr.body, expr.async)`
- [x] In `FunStmt` (BlockExpr handler): remove `wasAsync` save/restore, pass `stmt.async ?? false` directly
- [x] In `FunDecl`: remove `wasAsync` save/restore, pass `node.async` directly
- [x] All other ~47 call sites inside `inferExpr`: add `, asyncCtx` pass-through argument
- [x] Calls outside `inferExpr` in the top-level processing loop: add `, false`
- [x] Fix `.map(inferExpr)` usages to `.map((e) => inferExpr(e, asyncCtx))`
- [x] Remove `let inAsyncContext = false` declaration
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

No test changes needed — this is a behaviour-identical internal refactor.

## Documentation and specs to update

No spec changes needed — this is a compiler-internal refactor.

## Build notes

- 2026-03-07: Used a Python script for bulk mechanical transformation of ~51 call sites. Script ran twice (background + foreground confusion), causing double `asyncCtx` — fixed with `sed 's/, asyncCtx, asyncCtx)/, asyncCtx)/g'`.
- 2026-03-07: `.map(inferExpr)` in two places (argTs and elements) needed `(e) => inferExpr(e, asyncCtx)` wrapper since `.map` passes 3 args (item, index, array) which would fail with the new signature.
- 2026-03-07: Tests verified: `npm test` 231/231, `./scripts/kestrel test` 1011/1011.
