# Async Lambda Expressions

## Sequence: S01-11
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/done/E01-async-runtime-foundation.md)
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

- [x] `async (x: String) => await Fs.readText(x)` parses and type-checks as `(String) -> Task<String>`.
- [x] `await` inside a non-async lambda `(x) => await Fs.readText(x)` is a compile error ("await used outside async context").
- [x] `await` inside a non-async lambda nested inside an `async fun` is also a compile error — the `LambdaExpr` case in `check.ts` must save `inAsyncContext`, set it to `false` for non-async lambdas (or `true` for async lambdas), then restore it. This fixes a pre-existing bug where a non-async lambda inherits the outer async context.
- [x] Async lambda can be passed to higher-order functions: `List.map(paths, async (p) => await Fs.readText(p))` compiles.
- [x] Async lambda result is awaitable: `val task = async (x: Int) => x + 1; val n = await task(42)` evaluates to `43`.
- [x] Type inference works: the inferred type of `async (x: Int) => x + 1` is `(Int) -> Task<Int>`.
- [x] `docs/specs/01-language.md` grammar and §5 updated.
- [x] Conformance test `tests/conformance/typecheck/invalid/await_in_non_async_lambda.ks` added (covers both standalone and nested-inside-async-fun cases).
- [x] Conformance test `tests/conformance/runtime/valid/async_lambda.ks` added.
- [x] All tests pass: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`.

## Spec References

- `docs/specs/01-language.md` §3.7 (Lambda grammar), §5 (Async and Task model)
- `docs/specs/06-typesystem.md` (`Task<T>`, async context)

## Risks / Notes

- **Type inference for async lambdas**: The body of `async (x) => expr` is type-checked in an async context. The declared return type is `Task<R>` where `R` is inferred from `expr`. Verify this does not conflict with Hindley-Milner generalization or higher-order function type inference.
- **Generic async lambdas**: `async <A>(x: A) => ...` should work if non-async generic lambdas already do. Verify the combination.
- **`inAsyncContext` scoping**: The type checker uses a module-level mutable `inAsyncContext` flag. Entering a nested async lambda must save and restore the outer context (a lambda inside a non-async function, or a non-async lambda nested inside an async fun). Ensure the scoping is correct.
- **Codegen lambda numbering**: Async lambdas become async static methods (`$lambdaN`). The dispatch wrapping (virtual-thread submission) must be added alongside the existing `$lambdaN` emission logic.
- **Spec wording**: §5 currently says "await is only valid in an async context (inside an `async fun`)". Update to "inside an `async fun` or `async` lambda".

## Impact analysis

| Area | Change |
|------|--------|
| Compiler parser (`compiler/src/parser/parse.ts`) | Extend lambda parsing to recognize an optional leading `async` on both plain and generic lambdas, likely touching `parseUnary()`, `parseGenericLambda()`, and lambda disambiguation around `parseAtom()`. Compatibility risk is low because `async` is already reserved and currently invalid before a lambda head. |
| Compiler AST (`compiler/src/ast/nodes.ts`) | Add async metadata to `LambdaExpr` so parser, typechecker, and JVM codegen can distinguish sync vs async closures. Prefer a concrete boolean field to match `FunDecl` and reduce downstream branching ambiguity. |
| Compiler typechecker (`compiler/src/typecheck/check.ts`) | Change the `LambdaExpr` inference path so it saves/restores `inAsyncContext`, forces non-async lambdas to type-check outside async context even when nested in `async fun`, and wraps async lambda bodies as `Task<R>`. This directly addresses the scoping risk called out in Risks / Notes. |
| Bytecode codegen (`compiler/src/codegen/`) | No change expected. The active backend for this story is JVM-only; note this explicitly so the implementer does not spend time on legacy/nonexistent bytecode work. |
| JVM codegen (`compiler/src/jvm-codegen/codegen.ts`) | Carry async metadata through `LambdaInfo` / `collectLambdas()`, add async lambda emission alongside `$lambdaN` generation, and mirror the existing top-level async-function split (`$async$...` payload + `KRuntime.submitAsync(...)`) so invoking an async lambda yields `KTask`. The lambda numbering/capture path is the main rollback risk here. |
| JVM runtime (`runtime/jvm/src/kestrel/runtime/KRuntime.java`, `runtime/jvm/src/kestrel/runtime/KTask.java`, `runtime/jvm/src/kestrel/runtime/KFunction.java`) | No API change is expected because `submitAsync`, `KTask`, and `KFunction.apply` already support async dispatch returning an object payload. Still verify that closure invocation can reuse the existing runtime contract without a new helper. |
| Stdlib (`stdlib/kestrel/`) | No source changes expected. Existing polymorphic higher-order functions should accept async lambdas once `(T) -> Task<R>` types are inferred correctly; if a stdlib signature blocks that, document it as follow-up rather than silently broadening scope. |
| Scripts / CLI (`scripts/`) | No direct script or CLI changes expected. User-visible behaviour changes through the compiler and runtime only, but this story should still run E2E coverage because async lambda syntax becomes part of the surface language. |
| Tests (`compiler/test/**`, `tests/conformance/**`, `tests/e2e/**`) | Add parser, typechecker, JVM integration/codegen, conformance, and end-to-end coverage for plain async lambdas, generic async lambdas, nested-context rejection, and runtime awaiting of returned `Task` values. This is the main protection against regressions in parsing, async-context scoping, and closure codegen. |
| Specs (`docs/specs/01-language.md`, `docs/specs/06-typesystem.md`) | Update grammar and async-context wording to include `async` lambdas, plus the type-system rule that async lambda bodies infer `Task<R>`. This addresses the current spec mismatch and preserves the docs as source of truth. |

## Tasks

- [x] Update `compiler/src/parser/parse.ts` so lambda parsing accepts an optional `async` prefix for both `(params) => body` and `<T>(params) => body` forms, and ensure lambda disambiguation still works when `async` appears before the lambda head.
- [x] Update `compiler/src/ast/nodes.ts` to carry async metadata on `LambdaExpr` and adjust any downstream type imports/usages that assume lambdas are always synchronous.
- [x] Update the `LambdaExpr` path in `compiler/src/typecheck/check.ts` to save and restore `inAsyncContext`, type-check async lambdas in async context, force non-async lambdas to type-check out of async context, and infer async lambda return types as `Task<R>`.
- [x] Confirm `compiler/src/codegen/` requires no work for this JVM-only story; if any shared codegen layer participates in lambda lowering, document and update it explicitly before touching JVM-specific emission.
- [x] Update `compiler/src/jvm-codegen/codegen.ts` so lambda collection/emission knows whether a lambda is async, emits async payload helpers or equivalent wrapper methods for async lambdas, and routes async lambda invocation through `KRuntime.submitAsync(...)` the same way top-level async functions do.
- [x] Verify `runtime/jvm/src/kestrel/runtime/` needs no API changes for async lambdas; if JVM codegen cannot reuse `KFunction`, `KTask`, and `KRuntime.submitAsync` as-is, add the minimal runtime helper required and keep the change scoped to lambda dispatch.
- [x] Add parser coverage in `compiler/test/integration/parse.test.ts` for `async (x) => ...` and `async <A>(x: A) => ...` so the new syntax and AST flag are locked down.
- [x] Add typechecker regression coverage in `compiler/test/unit/typecheck/` for async lambda type inference, `await` rejection in non-async lambdas, and the nested-in-async-fun case where a sync lambda must not inherit the outer async context.
- [x] Add JVM backend regression coverage in `compiler/test/unit/jvm-codegen.test.ts` and/or `compiler/test/integration/jvm-async-runtime.test.ts` to prove async lambda lowering returns `KTask` and awaits correctly at runtime.
- [x] Add conformance coverage: `tests/conformance/typecheck/invalid/await_in_non_async_lambda.ks`, a valid typecheck case for async lambda inference/generics, and `tests/conformance/runtime/valid/async_lambda.ks` for runtime behaviour.
- [x] Add an end-to-end positive scenario under `tests/e2e/scenarios/positive/` that exercises async lambda syntax through the CLI and confirms the printed result when an awaited async lambda returns.
- [x] Update `docs/specs/01-language.md` to extend the lambda grammar and async-context wording from "async fun only" to "async fun or async lambda," including parser/disambiguation notes where needed.
- [x] Update `docs/specs/06-typesystem.md` to define async lambda typing as `(T1, ..., Tn) -> Task<R>` and to state that async context applies to async lambda bodies as well as async functions.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `cd runtime/jvm && bash build.sh`.
- [x] Run `./scripts/kestrel test`.
- [x] Run `./scripts/run-e2e.sh`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest integration | `compiler/test/integration/parse.test.ts` | Assert the parser accepts `async (x) => x` and `async <A>(x: A) => x`, and that resulting `LambdaExpr` nodes carry async metadata without breaking existing lambda parsing. |
| Vitest unit | `compiler/test/unit/typecheck/async-lambda.test.ts` or existing typecheck suite | Assert async lambdas infer `(T) -> Task<R>`, generic async lambdas instantiate correctly, and non-async lambdas reject `await` even when nested inside an outer `async fun`. |
| Vitest unit/integration | `compiler/test/unit/jvm-codegen.test.ts` and/or `compiler/test/integration/jvm-async-runtime.test.ts` | Assert async lambda lowering uses JVM async dispatch and that `val task = async (x: Int) => x + 1; await task(42)` evaluates to `43`. |
| Conformance typecheck | `tests/conformance/typecheck/invalid/await_in_non_async_lambda.ks` | Guard the regression that `await` in a sync lambda is rejected both at top level and when the sync lambda is nested inside an `async fun`. |
| Conformance typecheck | `tests/conformance/typecheck/valid/async_lambda.ks` | Prove async lambda inference, higher-order usage, and generic async lambda syntax type-check successfully without requiring explicit `Task<...>` annotations at the lambda site. |
| Conformance runtime | `tests/conformance/runtime/valid/async_lambda.ks` | Verify runtime behaviour of invoking and awaiting async lambdas, including at least one captured variable or higher-order call path so closure conversion stays covered. |
| E2E positive | `tests/e2e/scenarios/positive/async-lambda-expressions.ks` | Exercise the feature through the CLI/compiler/runtime stack and compare stdout against an `.expected` file so user-visible syntax stays working end to end. |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — Update the expression grammar’s `Lambda` production, parser/lexer disambiguation notes, and Section 5 async-context wording to include `async` lambdas alongside `async fun`.
- [x] `docs/specs/06-typesystem.md` — Update Section 6 and the lambda row in the expression-typing summary so async lambda bodies type-check in async context and infer function types returning `Task<R>`.

## Notes

- Existing JVM async-function lowering already provides the model to copy: top-level async functions emit a private payload method plus a public wrapper that calls `KRuntime.submitAsync(...)`. Reusing that pattern for lambdas is lower risk than inventing a separate closure-only async path.
- Current test coverage has a gap at every level relevant to this story: parser tests cover async functions but not async lambdas, typechecker tests cover top-level `await` misuse but not nested lambda context scoping, and runtime/conformance tests cover async functions but not async closures.
- No stdlib or CLI migration is expected. If higher-order examples reveal a separate library ergonomics issue, capture it as a follow-up story instead of widening S01-11.

## Build notes

- 2026-04-03: Started implementation.
- 2026-04-03: Added `async` metadata to `LambdaExpr`, taught the parser to recognize `async (...) => ...` and `async <T>(...) => ...`, and made non-async lambdas explicitly reset `inAsyncContext` so they no longer inherit an enclosing async function by accident.
- 2026-04-03: Implemented async lambda lowering by generating wrapper closure classes whose `apply()` submits generated payload closures to `KRuntime.submitAsync(...)`, plus payload methods that execute the lambda body and preserve captures.
- 2026-04-03: Async lambda payload methods must be emitted as directly callable static methods, not private helpers, because generated payload classes invoke them via bytecode rather than reflection.
- 2026-04-03: Existing `fs`, `process`, and `async_virtual_threads` Kestrel tests were relying on the old bug where sync `group` callbacks inherited outer async context. Moved awaits out of those sync callbacks and kept assertions/grouping synchronous.
- 2026-04-03: `cd compiler && npm run build && npm test`, `cd runtime/jvm && bash build.sh`, and `./scripts/run-e2e.sh` all pass.
- 2026-04-03: Re-ran full verification for epic closure: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`, and `./scripts/run-e2e.sh` all pass on this machine.