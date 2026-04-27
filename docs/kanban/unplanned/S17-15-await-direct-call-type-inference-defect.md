# Fix await direct-call type inference defect in recursive async functions

## Sequence: S17-15
## Tier: Optional
## Former ID: S17-16

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)

## Summary

In multiple async functions, code currently uses an intermediate binding before `await`, for example:

```kestrel
val next: Task<Unit> = deleteFiles(rest)
await next
```

Replacing this with the equivalent direct form:

```kestrel
await deleteFiles(rest)
```

fails with a type error (`await expects Task<T> but got α...`) in at least one recursive case. This indicates a type-inference defect where direct await-call typing diverges from await-on-bound-value typing.

This story fixes the defect in both compiler implementations (TypeScript compiler and self-hosted Kestrel compiler) so direct `await <async-call>` works reliably, including recursive calls.

## Current State

- The current workaround pattern (`val next: Task<T> = ...; await next`) appears in CLI and related async code.
- Direct `await` on function calls can mis-infer the argument to `await`, producing a polymorphic type variable instead of `Task<T>`.
- The issue appears in real code (`stdlib/kestrel/tools/cli.ks`) and is not just synthetic.

## Relationship to other stories

- Builds on S17-12 (CLI wired to self-hosted driver), where this pattern is visible in production self-hosted code.
- Complements S17-15 (async/result readability refactors) by removing another workaround pattern once typing is fixed.

## Goals

1. Reproduce and isolate the type-inference mismatch between `await f(...)` and `val x: Task<T> = f(...); await x`.
2. Fix inference/checking in the TypeScript compiler so direct await-call expressions infer `Task<T>` correctly.
3. Apply the equivalent fix in the self-hosted Kestrel compiler to preserve parity.
4. Remove workaround temporary bindings in affected code paths where safe, starting with `stdlib/kestrel/tools/cli.ks`.

## Acceptance Criteria

- [ ] A regression test captures the failing recursive case (`await deleteFiles(rest)`-style direct call) and fails before the fix.
- [ ] The TypeScript compiler accepts direct `await` on recursive async calls where the callee returns `Task<T>`.
- [ ] The self-hosted Kestrel compiler accepts the same source and produces matching behavior.
- [ ] Known workaround sites can be simplified from `val next: Task<T> = ...; await next` to direct `await ...` without new diagnostics.
- [ ] Compiler tests pass: `cd compiler && npm test`.
- [ ] Kestrel tests pass: `./scripts/kestrel test`.

## Spec References

- `docs/specs/01-language.md` (async/await semantics)
- `docs/specs/06-typesystem.md` (inference and type checking)
- `docs/specs/10-compile-diagnostics.md` (diagnostic expectations)

## Risks / Notes

- The bug may be in unification/instantiation timing for call expressions inside `await`, especially in recursive contexts.
- If TS and self-hosted implementations currently diverge in `await` typing internals, this story should align both and add parity tests to prevent regressions.
- Keep the fix focused on inference correctness; avoid broad refactors unless required to preserve soundness.
