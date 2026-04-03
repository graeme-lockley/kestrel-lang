# Preserve Trampoline Optimization for Sync Members of Async SCCs

## Sequence: S01-20
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)

## Summary

The JVM codegen currently skips the trampoline tail-call optimization for an **entire** strongly-connected component (SCC) if any member of that SCC is `async`. This means a synchronous tail-recursive function that happens to be mutually recursive with an async function silently loses its tail-call optimization, with no warning to the developer. The fix is to apply the trampoline only to the synchronous members of the SCC and emit the async member normally.

## Current State

```typescript
// compiler/src/jvm-codegen/codegen.ts
// Skip trampoline optimization for SCCs containing any async function
if (scc.some((name) => funByName.get(name)?.async)) continue;
```

This skips the entire SCC rather than excluding only the async member.

## Relationship to other stories

- Depends on S01-02 (virtual threads / async function codegen).
- Depends on the existing tail-call SCC trampoline from stories 10–11 of the original done list.
- Standalone codegen fix; no stdlib or spec impact.

## Goals

1. The SCC trampoline is applied to all synchronous members of an SCC, regardless of whether async members are present.
2. Async members of the SCC are emitted using the standard async payload/wrapper pattern, not the trampoline.
3. No existing test regresses; tail-recursive sync functions in mixed SCCs are correctly trampolined.
4. A unit or conformance test covers a mixed sync/async mutually-recursive group.

## Acceptance Criteria

- A mutually-recursive group containing both a sync tail-recursive function and an async function: the sync function uses the trampoline, the async function does not.
- Stack overflow does not occur for large input to the sync tail-recursive function in such a group.
- `cd compiler && npm test` passes.

## Spec References

- No spec changes needed — this is an internal codegen correctness fix.

## Risks / Notes

- The trampoline and async codegen paths share some descriptor-selection logic; verify that emitting them for the same SCC does not produce conflicting static method names.
- The test must use a deep enough input to actually trigger the original stack overflow to be a meaningful regression guard.
