# Async Lambda Expressions

## Sequence: S01-11
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)
- Companion stories: S01-01, S01-02, S01-03, S01-06, S01-07, S01-08, S01-09, S01-10

## Summary

Extend the Kestrel grammar to allow `async` on lambda expressions (`async (params) => body`). An async lambda has type `(T) -> Task<R>`, its body is an async context (so `await` is valid inside it), and its codegen wraps the body in a virtual-thread dispatch — the same way `async fun` does. Without this, `await` inside any lambda is always a compile error, which becomes a serious usability gap once `listDir`, `writeText`, `runProcess`, and `readText` all return `Task<T>`.

## Current State

- **Parser** (`compiler/src/parser/parse.ts`): `async` is only consumed in `parseFunDecl()`. The lambda branch (`parseAtom` / `parseGenericLambda`) has no `async` keyword check. Grammar: `Lambda ::= ["<" typeParams ">"] "(" ParamList ")" "=>" Expr` — no `async`.
- **AST** (`compiler/src/ast/nodes.ts`): `LambdaExpr` has no `async` field. `FunDecl` has `async: boolean`.
- **Type checker** (`compiler/src/typecheck/check.ts`): `inAsyncContext` is set only when entering an `async fun` body. The `LambdaExpr` case never sets it. `await` inside a lambda is always a compile error.
- **Codegen** (`compiler/src/jvm-codegen/codegen.ts`): Lambda bodies are compiled as static `$lambdaN` methods. There is no async-dispatch path for lambdas.
- **Spec** (`docs/specs/01-language.md`): §3.7 Lambda grammar has no `async`; §5 states "await is only valid in an async context (inside an `async fun`)".

## Relationship to other stories

- **Depends on S01-01 and S01-02**: KTask class and virtual-thread executor must exist so async lambda bodies can be dispatched.
- **Logically follows S01-03/07/08/09**: Once async I/O APIs exist, users will immediately hit the "can't await inside lambda" error.
- **Enables S01-06**: Conformance tests should cover async lambdas.
- **Independent of S01-04/05/10**: Error ADTs, CLI flags, and test harness are orthogonal.

## Goals

1. **Grammar**: `Lambda ::= [ "async" ] [ "<" typeParams ">" ] "(" ParamList ")" "=>" Expr`.
2. **AST**: `LambdaExpr` gains an `async?: boolean` field.
3. **Type checker**: When type-checking an async lambda body, set `inAsyncContext = true`. The inferred return type is `Task<R>` where `R` is the body type. A non-async lambda with `await` in its body is a type (context) error — unchanged from today.
4. **JVM codegen**: Async lambda bodies are dispatched to the virtual-thread executor just like async `fun` bodies, returning a `KTask`.
5. **Spec update**: `docs/specs/01-language.md` §3.7 and §5 updated to document async lambdas.
6. **Tests**: Conformance tests for async lambdas (valid and invalid — e.g. `await` in a non-async lambda must still error).

## Acceptance Criteria

- [ ] `async (x: String) => await Fs.readText(x)` parses and type-checks as `(String) -> Task<String>`.
- [ ] `await` inside a non-async lambda `(x) => await Fs.readText(x)` is a compile error ("await used outside async context").
- [ ] Async lambda can be passed to higher-order functions: `List.map(paths, async (p) => await Fs.readText(p))` compiles.
- [ ] Async lambda result is awaitable: `val task = async (x: Int) => x + 1; val n = await task(42)` evaluates to `43`.
- [ ] Type inference works: the inferred type of `async (x: Int) => x + 1` is `(Int) -> Task<Int>`.
- [ ] `docs/specs/01-language.md` grammar and §5 updated.
- [ ] Conformance test `tests/conformance/typecheck/invalid/await_in_non_async_lambda.ks` added.
- [ ] Conformance test `tests/conformance/runtime/valid/async_lambda.ks` added.
- [ ] All tests pass: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`.

## Spec References

- `docs/specs/01-language.md` §3.7 (Lambda grammar), §5 (Async and Task model)
- `docs/specs/06-typesystem.md` (`Task<T>`, async context)

## Risks / Notes

- **Type inference for async lambdas**: The body of `async (x) => expr` is type-checked in an async context. The declared return type is `Task<R>` where `R` is inferred from `expr`. Verify this does not conflict with Hindley-Milner generalization or higher-order function type inference.
- **Generic async lambdas**: `async <A>(x: A) => ...` should work if non-async generic lambdas already do. Verify the combination.
- **`inAsyncContext` scoping**: The type checker uses a module-level mutable `inAsyncContext` flag. Entering a nested async lambda must save and restore the outer context (a lambda inside a non-async function, or a non-async lambda nested inside an async fun). Ensure the scoping is correct.
- **Codegen lambda numbering**: Async lambdas become async static methods (`$lambdaN`). The dispatch wrapping (virtual-thread submission) must be added alongside the existing `$lambdaN` emission logic.
- **Spec wording**: §5 currently says "await is only valid in an async context (inside an `async fun`)". Update to "inside an `async fun` or `async` lambda".
