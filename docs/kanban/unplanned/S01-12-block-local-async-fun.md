# Block-local `async fun` Support

## Sequence: S01-12
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)

## Summary

`async fun` declarations are currently restricted to top-level scope. Block-local `fun` statements (`FunStmt`) have no `async` field in the AST, the grammar forbids the `async` keyword before a block-level `fun`, and the type checker never sets `inAsyncContext = true` for `FunStmt` bodies. This forces developers to either promote helpers to the module top-level or use `async` lambdas — both of which are ergonomic workarounds for a natural language feature.

This story adds full `async fun` support at block scope: grammar, AST node, type checker, and JVM codegen.

## Current State

- `FunStmt` AST node has no `async` field.
- The parser does not accept `async fun` inside a block expression.
- The type checker handles `FunDecl` async checks but `FunStmt` is a separate code path with no async handling.
- The JVM codegen emits `FunStmt` as a local static method reference; there is no payload/wrapper split for block-local async.
- Workaround: top-level `async fun` or `async` lambda expression.

## Relationship to other stories

- Depends on S01-02 (virtual thread executor is the execution mechanism).
- Depends on S01-11 (async lambda codegen pattern is the closest analogue for inner async methods).
- S01-14 (inAsyncContext refactor) would simplify the type-checker changes here; can be done after.

## Goals

1. The grammar accepts `async fun name(params): Task<T> = body` inside a block.
2. The AST `FunStmt` node gains an `async: boolean` field.
3. The type checker validates async block functions: return type must be `Task<T>`, body type unified against `T`, `await` allowed inside.
4. The JVM codegen compiles block-local `async fun` using the same payload/wrapper split as top-level `async fun`.
5. All existing tests continue to pass.

## Acceptance Criteria

- `async fun` inside a block compiles and produces the correct `Task<T>` return type.
- `await` is legal inside a block-local `async fun`.
- `await` inside a non-async block-local `fun` is still a compile error.
- A conformance test or unit test exercises block-local async functions.
- `cd compiler && npm test` and `./scripts/kestrel test` pass.

## Spec References

- `docs/specs/01-language.md` §2.4 (FunStmt grammar) — needs `async` qualifier added.
- `docs/specs/01-language.md` §5 (async/await semantics) — needs note on block scope.

## Risks / Notes

- The JVM codegen for `FunStmt` emits a local inner method; the async payload split will need care to avoid name collisions with sibling `FunStmt`s in the same block.
- If S01-14 (inAsyncContext as parameter) has not been done first, the same save/restore pattern used in `FunDecl` and `LambdaExpr` must be replicated in the `FunStmt` path.
