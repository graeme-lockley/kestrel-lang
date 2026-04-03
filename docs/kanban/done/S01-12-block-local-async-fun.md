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

## Impact analysis

| Area | Change |
|------|--------|
| AST `compiler/src/ast/nodes.ts` | Add `async?: boolean` to `FunStmt` interface |
| Parser `compiler/src/parser/parse.ts` | In `parseBlock`: detect `async` keyword before `fun`, include `async` flag in `FunStmt` push |
| Type checker `compiler/src/typecheck/check.ts` | In `BlockExpr` FunStmt phase 2: save/restore `inAsyncContext`, validate `Task<T>` return type, unify body against inner `T` |
| JVM codegen `compiler/src/jvm-codegen/codegen.ts` | In `walkBlock`: pass `stmt.async ?? false` to `addLambda` (currently hardcoded `false`) |
| Tests | New conformance runtime test + Kestrel unit test |
| Spec | `docs/specs/01-language.md` §2.4 grammar + §5 semantics |

## Tasks

- [x] Add `async?: boolean` to `FunStmt` interface in `compiler/src/ast/nodes.ts`
- [x] In `compiler/src/parser/parse.ts` `parseBlock`: detect `async` before `fun`, pass `async: isAsync` in the `FunStmt` push
- [x] In `compiler/src/typecheck/check.ts` `BlockExpr` FunStmt phase 2: save/restore `inAsyncContext`, validate `Task<T>` return, unify body against inner `T`
- [x] In `compiler/src/jvm-codegen/codegen.ts` `walkBlock`: change hardcoded `false` to `stmt.async ?? false` in `addLambda` call
- [x] Add conformance runtime test `tests/conformance/runtime/valid/async_block_local_fun.ks`
- [x] Add typecheck negative test `tests/conformance/typecheck/invalid/await_in_non_async_block_fun.ks`
- [x] Update `docs/specs/01-language.md` §2.4 (FunStmt grammar) and §5 (async semantics)
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`
- [x] Run `cd runtime/jvm && bash build.sh`
- [x] Run `./scripts/run-e2e.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance runtime | `tests/conformance/runtime/valid/async_block_local_fun.ks` | block-local async fun compiles and returns correct `Task<T>`; `await` inside is valid |
| Conformance typecheck | `tests/conformance/typecheck/invalid/await_in_non_async_block_fun.ks` | `await` inside a non-async block-local fun is a compile error |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` §2.4 — add `async` qualifier to `FunStmt` grammar rule
- [x] `docs/specs/01-language.md` §5 — note that `async fun` is valid at block scope

## Build notes

- 2026-03-07: All 4 compiler changes implemented simultaneously (nodes.ts, parse.ts, check.ts, codegen.ts). Key insight: must set `inAsyncContext = stmt.async ?? false` (unconditional reset) rather than `if (stmt.async) inAsyncContext = true` — the latter left `inAsyncContext` true for non-async block funs inside an async outer scope, incorrectly permitting `await`. This mirrors the exact pattern in `LambdaExpr` handling.
- 2026-03-07: Runtime conformance test format: keep no inline comments inside function bodies (harness treats `//` lines as expected output); must include `run()` call at bottom of file.
- Tests verified: `npm test` 230/230, `./scripts/kestrel test` 1011/1011, `./scripts/run-e2e.sh` 10/10.
