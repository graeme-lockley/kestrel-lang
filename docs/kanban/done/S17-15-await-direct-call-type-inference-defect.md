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

- [x] A regression test captures the failing recursive case (`await deleteFiles(rest)`-style direct call) and fails before the fix.
- [x] The TypeScript compiler accepts direct `await` on recursive async calls where the callee returns `Task<T>`.
- [x] The self-hosted Kestrel compiler accepts the same source and produces matching behavior.
- [x] Known workaround sites can be simplified from `val next: Task<T> = ...; await next` to direct `await ...` without new diagnostics. *(TypeScript compiler and self-hosted typecheck both now accept the simplified form; cli.ks still uses workaround pattern pending bootstrap rebuild — see Build notes.)*
- [x] Compiler tests pass: `cd compiler && npm test`.
- [x] Kestrel tests pass: `./scripts/kestrel test`.

## Spec References

- `docs/specs/01-language.md` (async/await semantics)
- `docs/specs/06-typesystem.md` (inference and type checking)
- `docs/specs/10-compile-diagnostics.md` (diagnostic expectations)

## Risks / Notes

- The bug may be in unification/instantiation timing for call expressions inside `await`, especially in recursive contexts.
- If TS and self-hosted implementations currently diverge in `await` typing internals, this story should align both and add parity tests to prevent regressions.
- Keep the fix focused on inference correctness; avoid broad refactors unless required to preserve soundness.

## Impact analysis

| Area | File(s) | Nature of change |
|------|---------|-----------------|
| TypeScript type checker | `compiler/src/typecheck/check.ts` | Add `var` case in `AwaitExpr` handler: unify the type variable with `Task<γ>` instead of throwing |
| Self-hosted type checker | `stdlib/kestrel/dev/typecheck/typecheck.ks` | Add `TVar(_)` case in `inferAwait`: unify with `TApp("Task", [inner])` instead of emitting error |
| Stdlib (workaround removal) | `stdlib/kestrel/tools/cli.ks` | Replace 4 intermediate-binding workarounds with direct `await …(rest, …)` |
| Conformance tests (typecheck) | `tests/conformance/typecheck/valid/` | New `await_recursive_direct_call.ks` regression test |
| Self-hosted typecheck tests | `stdlib/kestrel/dev/typecheck/typecheck.test.ks` | New test for `inferAwait` on a `TVar` operand |
| Specs | `docs/specs/01-language.md`, `docs/specs/06-typesystem.md` | Clarify that `await` constrains its operand to `Task<T>` via unification, not just checks |

**Compatibility:** purely additive in inference — previously-accepted code continues to compile unchanged. Workaround patterns remain valid (they are just no longer necessary).

**Rollback risk:** low. The change is localized to two `await`-expression handlers. If the `TVar` unification produces wrong types in edge cases, reverting one branch is sufficient.

## Tasks

- [x] Add conformance test `tests/conformance/typecheck/valid/await_recursive_direct_call.ks` that directly awaits a recursive async call and verify it fails before the fix.
- [x] Fix `AwaitExpr` handler in `compiler/src/typecheck/check.ts`: when `applied.kind === 'var'`, unify it with `Task<γ>` and return `γ` instead of throwing.
- [x] Fix `inferAwait` in `stdlib/kestrel/dev/typecheck/typecheck.ks`: add `TVar(_)` match arm that unifies with `TApp("Task", [inner])` and returns `inner`.
- [x] Add test in `stdlib/kestrel/dev/typecheck/typecheck.test.ks` covering `inferAwait` on a `TVar`-typed operand.
- [x] Remove workaround in `stdlib/kestrel/tools/cli.ks` `deleteFiles` (line ~144): replace `val next: Task<Unit> = deleteFiles(rest); await next` with `await deleteFiles(rest)`. *(Deferred: requires bootstrap rebuild — see Build notes.)*
- [x] Remove workaround in `stdlib/kestrel/tools/cli.ks` `anyDepNewer` (lines ~88-101): replace all three `val next: Task<Bool> = anyDepNewer(rest, classMtime); await next` patterns with `await anyDepNewer(rest, classMtime)`. *(Deferred: requires bootstrap rebuild — see Build notes.)*
- [x] Update `docs/specs/01-language.md` async/await semantics to note that `await` constrains its operand to `Task<T>` via unification.
- [x] Update `docs/specs/06-typesystem.md` to describe the unification approach for `await`.
- [x] Run `cd compiler && npm test` and verify all tests pass.
- [x] Run `./scripts/kestrel test` and verify all tests pass.

## Build notes

- 2026-04-27: Started implementation. Root cause confirmed: `AwaitExpr` handler in `check.ts` throws immediately when the operand type is an unresolved type variable (e.g. during recursive async call inference), instead of constraining it to `Task<γ>` via unification. Same defect exists in `inferAwait` in the self-hosted type checker `typecheck.ks`.
- 2026-04-27: `cli.ks` workaround removal deferred due to bootstrap chicken-and-egg: the `./kestrel test` command uses the current bootstrap JAR (which contains the old, unfixed typecheck) to compile all stdlib files including `cli.ks`. Removing the intermediate bindings in `cli.ks` causes the bootstrap's unfixed typecheck to reject the direct `await f(rest)` call — the very bug being fixed. The TypeScript compiler (`check.ts`) and self-hosted source (`typecheck.ks`) are both fixed; `cli.ks` can be simplified after the next `./scripts/build-bootstrap-jar.sh` run that incorporates this fix. Deferred cleanup folded into **S17-42** (Goals §7, Acceptance Criteria final bullet, Risks/Notes).

## Tests to add

| Test | Location | What it asserts |
|------|----------|----------------|
| `await_recursive_direct_call.ks` | `tests/conformance/typecheck/valid/` | Recursive async function with direct `await f(rest)` call is accepted without error |
| `inferAwait_tvar` (or expand existing `inferAwait` tests) | `stdlib/kestrel/dev/typecheck/typecheck.test.ks` | `inferAwait` on an expression whose type resolves to a `TVar` returns the inner type after unification |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — async/await semantics: add note that `await` constrains its operand via unification (`operand type` ⇒ `Task<T>`) rather than simply checking a concrete type.
- [x] `docs/specs/06-typesystem.md` — type inference rules: add or update the `await` rule to document the unification-based constraint.
