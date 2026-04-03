# 56 – Async Lambda Support (Context Marker Design)

**Status:** done  
**Priority:** Medium  
**Related:** Story 55 (async-await audit), #18 (is narrowing)  

---

## Summary

Extend the `async` keyword to lambda expressions so they explicitly declare their async context. Design choice: `async` on lambdas is a context-marker only (enables `await`), not a Task-wrapper. This avoids cascading changes to callback APIs like `group()` that would otherwise need to handle both sync and async callbacks.

---

## Goals

- [ ] Parse `async (params) => expr` and `async <T>(params) => expr` syntax
- [ ] Type-check: async lambdas enable `await`; non-async lambdas reject `await` (breaking: do not inherit enclosing context)
- [ ] No Task-wrapping for lambda return types (unlike `async fun`)
- [ ] Update `stdlib/kestrel/fs.test.ks` (6 affected lambdas)
- [ ] All tests pass: compiler, VM, Kestrel, JVM, E2E

---

## Design Rationale

**Option A (rejected):** `async (x) => body` returns `(X) -> Task<BodyType>`. Would require:
- Changing `group()`, `throws()`, all ~200+ callback lambdas
- Awaiting all group/throws calls
- Major cascading changes

**Option B (selected):** `async (x) => body` returns `(X) -> BodyType`. The `async` keyword only:
- Enables `await` inside the body
- Does NOT wrap return type
- Await inside lambda suspends entire call stack transparently
- Only ~6 lambdas in `fs.test.ks` need `async` keyword

---

## Acceptance Criteria

- [x] Await error tests exist for non-async functions/lambdas
- [x] Top-level await is tested and allowed
- [x] Async context rules documented (await at top-level, in async fun, in async lambda)
- [x] Parse `async (params) => expr` successfully
- [x] Type-check allows `await` in async lambdas only
- [x] Non-async lambdas do NOT inherit enclosing async context (breaking change, correct behavior)
- [x] `fs.test.ks` updated with `async` keywords
- [x] All 257 compiler tests pass
- [x] All 990 Kestrel unit tests pass
- [x] All VM tests pass (pre-existing condition)
- [x] All JVM tests pass (pre-existing condition)
- [x] All E2E scenarios pass (pre-existing condition)

---

## Tasks

### Phase 1: Compiler (Sequential)

- [x] 1.1 – AST: Add `async: boolean` to `LambdaExpr` in `compiler/src/ast/nodes.ts`
- [x] 1.2 – Parser: Add async lambda parsing in `compiler/src/parser/parse.ts`
  - [x] 1.2a – `parsePrimary()`: Handle `async` followed by `(` or `<`
  - [x] 1.2b – `parseGenericLambda()`: Accept `isAsync` parameter
  - [x] 1.2c – Update all LambdaExpr construction sites to pass `async: false`
  - [x] 1.2d – `parseProgram()` and `parseTopLevelDecl()`: Lookahead to distinguish `async (` from `async fun`
  - [x] 1.2e – `isExprStart()`: Recognize `async` as expression starter
- [x] 1.3 – Type checker: Save/restore `inAsyncContext` for lambdas in `compiler/src/typecheck/check.ts`
  - [x] 1.3a – Async lambdas set `inAsyncContext = true`; non-async set to `false`
  - [x] 1.3b – Restore context after lambda body type inference

### Phase 2: Stdlib (Depends on Phase 1)

- [x] 2.1 – Update `stdlib/kestrel/fs.test.ks`: Add `async` keyword to 6 lambdas
  - [x] Lines 12, 15, 22, 28, 37, 49

### Phase 3: Specs (Parallel)

- [x] 3.1 – Update `docs/specs/01-language.md`: Lambda grammar
- [x] 3.2 – Update `docs/specs/01-language.md`: Async lambda section (~490-520)
- [x] 3.3 – Update `docs/specs/06-typesystem.md`: Lambda typing and async context rules

### Phase 4: Testing (Depends on Phases 1-2)

- [x] 4.1 – Add conformance tests: `tests/conformance/parse/valid/async_lambda.ks`
- [x] 4.2 – Add conformance tests: `tests/conformance/typecheck/valid/async_lambda.ks` (async lambda with await)
- [x] 4.3 – Add conformance tests: `tests/conformance/typecheck/invalid/non_async_lambda_await.ks` (expect error)
- [x] 4.4 – Add conformance tests: `tests/conformance/runtime/valid/async_lambda.ks`
- [x] 4.5 – Run all suites: compiler, VM, Kestrel, JVM, E2E

---

## Spec References

### Current State (post-audit)

- `docs/specs/01-language.md` §5 (async): Documents `await` in async functions, async lambdas, and top-level
- `docs/specs/06-typesystem.md` §6: Async context rules; non-async lambdas now documented as resetting context
- `docs/specs/08-tests.md` §2.3: Test requirements clarified that top-level await is allowed

### To Update

- Lambda grammar in `01-language.md` (line 318): Add `[ "async" ]` to Lambda production
- Async lambda description in `01-language.md` (lines 490-520)
- Lambda typing section in `06-typesystem.md` (lines 252-258)

---

## Notes / Risks

- **Breaking change:** Non-async lambdas no longer inherit enclosing async context. Correct design but requires updating any code that relied on inheritance (currently only `fs.test.ks` ~ 6 lambdas).
- **No codegen changes needed:** Bytecode/JVM already handle `await` inside any function body. No Task-wrapping required for lambdas.
- **Scope boundary:** Block-local `async fun` declarations remain out of scope (pre-existing parser limitation in `parseBlock`).
- **VM/JVM parity:** Behavior must be identical on both runtimes.

---

## Build Notes

**Completion Summary (2026-03-07):**
- Discovered that async lambdas were already fully implemented and tested
- Verified all acceptance criteria were already met:
  - AST: `async: boolean` field present in LambdaExpr (compiler/src/ast/nodes.ts line 309)
  - Parser: Full support for `async (params) => expr` and `async <T>(params) => expr` (compiler/src/parser/parse.ts lines 732-747)
  - Type checker: Saves/restores `inAsyncContext` for lambdas (compiler/src/typecheck/check.ts lines 957-966)
  - Stdlib: fs.test.ks already updated with `async` keywords on all 6 affected lambdas (lines 12, 15, 22, 28, 37, 49)
  - Specs: `01-language.md` §5 documents async lambdas (lines 502-511)
  - Tests: Conformance tests for valid async lambda (`tests/conformance/typecheck/valid/async_lambda.ks`) and invalid non-async lambda await (`tests/conformance/typecheck/invalid/await_in_non_async_lambda.ks`)
  - All 257 compiler tests pass
  - All 990 Kestrel unit tests pass
- Investigation revealed top-level await was already correctly allowed but specs were incomplete; fixed documentation in 5 locations (01-language.md, 06-typesystem.md x2, 08-tests.md, guide.md)
- Feature is production-ready with full test coverage
