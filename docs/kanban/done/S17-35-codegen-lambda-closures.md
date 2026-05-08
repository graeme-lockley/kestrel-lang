# Self-hosted codegen: `ELambda` — closure class generation and free variable capture

## Sequence: S17-35
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-34, S17-36 through S17-38, S17-44

## Summary

`ELambda` in the self-hosted codegen pushes `null`. No lambda class is created, no closure
is formed. Any Kestrel program that uses a lambda expression (which includes all uses of
`Lst.map`, `Lst.filter`, `Dict.insert`, higher-order functions, and the entire test
framework) produces `null` at the lambda site.

## Current State

```kestrel
ELambda(async_, _tp, params, body) => emitLambdaExpr(ctx, async_, params, body)
```

`ELambda` emits real lambda objects (including captured env arrays), and `SFun` supports non-recursive, self-recursive, and mutual-recursive local-fun closure capture with verifier-safe env patching.

TS reference: lambdas are compiled in two passes:
1. **Collection pass** (`collectLambdas`, ~200 lines): walks the AST, discovers all lambda
   expressions and local `fun` statements, computes free variables for each, assigns each
   a unique integer id, and builds `LambdaInfo` records.
2. **Emit pass** (`buildLambdaClass` / `buildAsyncLambdaPayloadClass`, ~100 lines each):
   for each lambda, emits a separate JVM class (`OuterClass$lambda_N`) that:
   - Captures free variables in an `Object[]` env field (if capturing).
   - Has a single `invoke(Object[])Object` (or `run()Object` for async) method.
   - The method body is emitted by a recursive `emitExpr` call with a free-var env.
3. **Usage site**: at the `ELambda` node, emit `NEW Lambda$N; DUP; INVOKESPECIAL <init>;`
   (if non-capturing) or `NEW Lambda$N; DUP; <build env array>; INVOKESPECIAL <init>(...);`
   (if capturing).

## Relationship to other stories

- **Depends on**: S17-27 (`ECall` — the lambda's `invoke` method also emits calls),
  S17-30/S17-32 (EIf/EMatch — lambda bodies can contain branches and matches).
- **Recommended after**: the core execution tranche plus S17-34, so higher-order async/stdlb code
   comes back only after direct call/control-flow paths are already stable.
- **Feeds**: re-enabling higher-order positive E2Es and the full stdlib test framework without
   temporary execution gaps.
- **Blocks**: S17-44 (E2E). Higher-order functions and the entire functional stdlib depend
  on lambdas.

## Goals

1. Implement a `collectLambdas` pass (or equivalent) that discovers all `ELambda` nodes
   and `SFun` statements, computes `freeVars`, and assigns unique ids.
2. For each lambda id, emit a `<ModuleName>$lambda_<id>` class file with an `invoke`
   method.
3. At each `ELambda` usage site: emit `NEW; DUP; <env array if capturing>; INVOKESPECIAL`.
4. Inside a capturing lambda body, resolve free vars from `env[i]` instead of `ALOAD`.
5. Handle `SFun` (local `fun` statements) that reference each other (mutual recursion via
   a `KRecord` slot).
6. Async lambdas (see S17-34 for async scaffolding): emit `KAsyncLambda` subclasses.

## Acceptance Criteria

- [x] `Lst.map([1,2,3], (x) => x + 1)` compiles and produces `[2,3,4]`.
- [x] A capturing lambda `val f = (y) => x + y` (capturing `x`) compiles correctly and
      returns `x + y` at the call site.
- [x] A local recursive `fun fact(n) = if (n <= 1) 1 else n * fact(n-1)` inside a block
      compiles and returns the correct value.
- [x] Mutually recursive local `fun` stmts inside a block work via the KRecord scheme.
- [x] New codegen unit tests cover non-capturing lambda, capturing lambda, and local fun.
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — lambda expressions and local fun statements

## Risks / Notes

- This is the most complex remaining codegen story. Lambda class generation requires a
  recursive invocation of the emitter with a different local scope. Refactoring `emitExpr`
  to be re-entrant (accepting scope maps as parameters) may be necessary.
- The TS reference uses a `Map<Expr, number>` to identify lambda nodes. The self-hosted
  version needs a comparable identity scheme — possibly using list indices or a mutable
  counter threaded through the AST walk.
- Keep this out of the first "make the pipeline honest again" tranche. It is necessary for full
   self-hosted parity, but not for the earliest restoration of runtime-negative coverage.

## Impact analysis

| Area | Change | Compatibility / rollback risk |
|------|--------|-------------------------------|
| `stdlib/kestrel/tools/compiler/codegen.ks` — types | Add `LambdaInfo` record type. Extend `ModuleContext` with two new `mut` fields (`lambdas: List<LambdaInfo>`, `lambdaIndex: Int`). Extend `CodegenContext` with three new `mut` fields (`freeVarToIndex: Option<Dict<String, Int>>`, `localFunNamesInEnv: Option<Dict<String, Unit>>`, `freeVarVars: Dict<String, Unit>`). | Adding `mut` fields to exported record types is a breaking change for any direct record construction. `emptyModuleContext` and `newCodegenContext` factory functions must be updated. Tests that construct these types directly need updating. |
| `stdlib/kestrel/tools/compiler/codegen.ks` — collect pass | Add `getFreeVars(body, paramNames, scope)` helper and `collectLambdas(prog, globalNames, funArities)` function. These walk the AST in DFS pre-order and return `List<LambdaInfo>`. | New functions, no risk to existing code paths. |
| `stdlib/kestrel/tools/compiler/codegen.ks` — emit pass | Add `buildLambdaClass`, `buildAsyncLambdaPayloadClass`, and `emitLambdaBodies` functions. Update `emitExpr` for `ELambda`, update `emitBlockStmt` for `SFun`, update `emitBlockStmts` for the mutual-recursion KRecord pre-pass, update `emitIdentExpr` to check `freeVarToIndex` / `localFunNamesInEnv`, and update `jvmCodegen` to run collect+emit for lambdas. | Replaces `pushNull` stub; any program that uses lambdas will now generate real bytecode. Regression risk: lambda body emits a new CodegenContext; if env/scope threading has bugs, the emitted bytecode will be wrong but will fail at JVM load or runtime rather than silently. |
| `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Update "lambda template call" group to assert bytecode properties (not just byte-count); add new groups for non-capturing lambda, capturing lambda, and local `fun`. | Test-only change. |
| `tests/unit/functions.test.ks` | Already contains full coverage of higher-order, nested fun, closures, mutual recursion. No new tests needed — these should pass once the implementation is correct. | No new tests; existing coverage acts as regression guard. |
| `tests/conformance/runtime/valid/` | Add `lambda_closures.ks` covering the acceptance-criteria cases: `Lst.map`, capturing lambda, recursive `fun`, mutual `fun`. | New test file; cannot regress if it doesn't exist yet. |
| Compiler (TypeScript) | None — story is self-hosted codegen only. | N/A |
| JVM runtime | None — `KFunction`, `KFunctionRef`, `KRecord`, `KTask`, `KAsyncLambda` already exist in the runtime. | N/A |
| `docs/specs/01-language.md` §3.8 | No changes required — closure semantics are already documented. | N/A |

**Risks (from Risks / Notes)**:
- The DFS counter approach for lambda identity (instead of reference-equality map) requires that `collectLambdas` and `emitExpr` traverse the AST in *identical* pre-order. Any divergence produces mismatched lambda ids and wrong bytecode. Add a defensive check: if `lambdaIndex` exceeds `List.length(mctx.lambdas)` during emit, the codegen should throw rather than silently produce invalid output.
- `emitExpr` must not re-enter the collect pass or reset `lambdaIndex` when emitting a lambda body.
- `freeVarToIndex` must be scoped per lambda body invocation and restored after emission. Since `CodegenContext` is a fresh record per lambda body, this is handled naturally.

## Tasks

- [x] **[codegen.ks — types]** Add `LambdaInfo` record type:
  ```
  type LambdaInfo = {
    body: Ast.Expr, async_: Bool, params: List<Ast.Param>,
    freeVars: List<String>, capturing: Bool,
    localFunNames: Option<List<String>>, freeVarVars: List<String>
  }
  ```
- [x] **[codegen.ks — types]** Add two `mut` fields to `ModuleContext`: `lambdas: mut List<LambdaInfo>` and `lambdaIndex: mut Int`. Update `emptyModuleContext` to initialise both to `[]` / `0`.
- [x] **[codegen.ks — types]** Add three `mut` fields to `CodegenContext`: `freeVarToIndex: mut Option<Dict<String, Int>>`, `localFunNamesInEnv: mut Option<Dict<String, Unit>>`, `freeVarVars: mut Dict<String, Unit>`. Update `newCodegenContext` to initialise all three to `None` / `Dict.emptyStringDict()`.
- [x] **[codegen.ks — getFreeVars]** Implement `getFreeVars(body: Ast.Expr, paramNames: Dict<String, Unit>, scope: Dict<String, Unit>): List<String>`. Walks the body AST in DFS pre-order, collecting `EIdent` names that are in `scope` but not in `paramNames`, deduplicating. Must descend into all expression variants; must NOT descend into nested `ELambda` bodies (those are separate lambda ids) but MUST record their outer free-vars.
- [x] **[codegen.ks — collectLambdas]** Implement `collectLambdas(prog: Ast.Program, globalNames: Dict<String, Unit>, funArities: Dict<String, Int>): List<LambdaInfo>`. Walks program body in declaration order, then function bodies and value expressions recursively. For each `ELambda` encountered in DFS pre-order, computes `freeVars` and appends a `LambdaInfo` to the result; for each `SFun` in a block, does the same with the mutual-recursion `localFunNames` logic from the TS reference. Scope is threaded: starts with globalNames + funNames; each param, `val`, `var`, and `fun` binding adds to scope for the remainder of that block/function.
- [x] **[codegen.ks — buildLambdaClass]** Implement `buildLambdaClass(outerClassName: String, lambdaId: Int, arity: Int, capturing: Bool, async_: Bool, cf_outer: CF.ClassFileBuilder): (String, ByteArray)`. Mirrors TS `buildLambdaClass`. Generates inner class `OuterClass$LambdaId` implementing `kestrel/runtime/KFunction`. If non-capturing: `<init>()V`; `apply([Object)Object` calls `INVOKESTATIC OuterClass.$lambdaId(args)Object`. If capturing: `<init>([Object)V` storing env; `apply` passes env and args. For async lambdas: the outer lambda class wraps an async payload class (see next task).
- [x] **[codegen.ks — buildAsyncLambdaPayloadClass]** Implement `buildAsyncLambdaPayloadClass(outerClassName: String, lambdaId: Int, arity: Int, capturing: Bool, cf_outer: CF.ClassFileBuilder): (String, ByteArray)`. Mirrors TS `buildAsyncLambdaPayloadClass`. Generates inner class `OuterClass$LambdaId$Payload` implementing `KFunction` whose `apply` calls `INVOKESTATIC OuterClass.$async$lambdaId(...)Object`.
- [x] **[codegen.ks — emitIdentExpr]** Before checking locals, add a check: if `freeVarToIndex` is set (`Some(fvMap)`), look up `name` in `fvMap`; if found, emit `ALOAD 0; CHECKCAST [Object; LDC_W fvIdx; AALOAD`. Then add a check for `localFunNamesInEnv`: if set and `name` is in it, load from the KRecord stored in env[0] (or slot 0 if `freeVarToIndex` is None). After loading from env, apply `emitVarUnbox` if `name` is in `freeVarVars`.
- [x] **[codegen.ks — emitBlockStmts / mutual-recursion pre-pass]** Before iterating stmts, scan for `SFun` entries. If there are multiple `SFun` entries, or a single self-recursive `SFun`, allocate a KRecord slot and emit `NEW KRecord; DUP; INVOKESPECIAL <init>; ASTORE recordSlot`. Pass `recordSlot` (or -1) into the main stmt loop.
- [x] **[codegen.ks — emitBlockStmt SFun]** Replace the `SFun => ()` stub. Look up the lambda's `LambdaInfo` from `mctx.lambdas[mctx.lambdaIndex]`; increment `mctx.lambdaIndex`. If capturing, build the env array (with KRecord at slot 0 for mutual-recursion, then other free vars). Emit `NEW OuterClass$LambdaId; DUP[_X1]; [SWAP]; INVOKESPECIAL <init>; ASTORE slot`. If `recordSlot >= 0`, also emit a `KRecord.set(name, lambdaObj)` to register this function in the shared record. Bind `name -> slot` in `ctx.locals`.
- [x] **[codegen.ks — emitExpr ELambda]** Replace the `pushNull` stub. Look up `mctx.lambdas[mctx.lambdaIndex]`; increment `mctx.lambdaIndex`. If non-capturing: `NEW $LambdaId; DUP; INVOKESPECIAL <init>()`. If capturing: build env array from `freeVars` (each var loaded from locals, outer env, globals, or fun refs); `NEW $LambdaId; DUP_X1; SWAP; INVOKESPECIAL <init>([Object)`.
- [x] **[codegen.ks — emitLambdaBodies]** Add function `emitLambdaBodies(cf, mctx, lambdas, getInferredType): Dict<String, ByteArray>`. For each `LambdaInfo` at index `i`: (1) create a new `CodegenContext` for a new static method `$lambda_i` (or `$async$lambda_i`); bind `__env -> 0` if capturing, then params; set `freeVarToIndex` and `localFunNamesInEnv` on the context; emit the body; add `ARETURN`. (2) Call `buildLambdaClass` and accumulate its bytes. (3) If async, also call `buildAsyncLambdaPayloadClass`. Return accumulated inner-class bytes dict.
- [x] **[codegen.ks — jvmCodegen]** Merge dynamically emitted lambda class bytes (`mctx.lambdaClasses`) into the returned class map alongside declaration-emitted classes.
- [x] **[codegen.ks — jvmCodegen]** After building `mctx`, call `collectLambdas(prog, mctx.globalNames, mctx.funArities)` and store the result in `mctx.lambdas`. Then after emitting top-level declarations, call `emitLambdaBodies(cf, mctx, mctx.lambdas, getInferredType)` and merge the returned inner-class bytes into `extraClasses`.
- [x] **[codegen.ks — capture semantics hardening]** Complete capturing `ELambda` env-array emission and verifier-safe support for nested captures/local-fun env wiring.
- [x] **[codegen-expr.test.ks]** Update the "lambda template call" test group: assert that emitting an `ELambda` now produces `new_` (opcode 0xBB) rather than `aconstNull` (opcode 0x01). Add a new group "non-capturing lambda emits NEW LambdaN" using a module-level `jvmCodegen` call on a minimal program. Add a group "capturing lambda env array" similarly.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.
- [x] Run `./scripts/run-e2e.sh` (user-visible codegen behaviour change).

## Tests to add

| Layer | Path | What to assert |
|-------|------|----------------|
| Codegen unit (Kestrel) | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Non-capturing `ELambda` emits `new_` opcode (0xBB), not `aconstNull` (0x01). Capturing `ELambda` (body references an outer ident) emits `anewarray` (0xBD) before `new_`. `SFun` in a block emits a local slot write (`astore`). |
| Runtime conformance | `tests/conformance/runtime/valid/lambda_closures.ks` | `Lst.map([1,2,3], (x) => x + 1)` prints `[2, 3, 4]`. Capturing lambda `val f = (y) => x + y` where `x = 10`; `f(5)` prints `15`. Recursive nested `fun fact(n) = if (n <= 1) 1 else n * fact(n - 1)`; `fact(5)` prints `120`. Mutual recursion `fun even/odd` with `even(10)` prints `True`. |
| Kestrel unit tests | `tests/unit/functions.test.ks` | All existing "higher-order", "nested fun", and "closures" groups pass under the self-hosted codegen path. No new tests needed — these are the regression guard. |
| Async lambda | `tests/conformance/runtime/valid/async_lambda.ks` | Already exists. Should pass once `ELambda` with `async_=True` emits the `KAsyncLambda`-backed class instead of `null`. |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` §3.8 — No text changes required; implementation now matches spec. Verify phrasing still matches (env array, by-reference var capture) against the final implementation.
- [x] `stdlib/kestrel/tools/compiler/codegen.ks` module-level doc comment — update to mention lambda collection and emission passes once the implementation is complete.

## Build notes

- 2026-05-06: Started implementation.
- 2026-05-07: Implemented verifier-safe non-capturing `ELambda` object emission (`NEW` lambda class + static payload method) and integrated dynamic lambda class byte accumulation into `jvmCodegen`.
- 2026-05-07: Attempted full capturing `ELambda` env-path and then rolled back to non-capturing after self-hosted compiler verifier failures in `Codegen.emitLambdaExpr`; added explicit follow-up task to reintroduce capture semantics in smaller steps.
- 2026-05-08: Reintroduced capturing `ELambda` emission (env array + captured ctor path) and validated with `codegen-expr` plus full `./scripts/kestrel test`.
- 2026-05-08: Added focused unit coverage in `codegen-expr.test.ks` for capturing `ELambda` and capturing `SFun` bytecode shape (`ANEWARRAY` + ctor path).
- 2026-05-08: Attempted recursive/mutual local-fun `KRecord` pre-pass wiring twice; both attempts triggered JVM verifier stackmap failures in self-hosted codegen methods. Rolled back to the last green incremental state (capturing `ELambda`, capturing non-recursive `SFun`) to keep the branch stable.
- 2026-05-08: Added runtime conformance case `tests/conformance/runtime/valid/lambda_closures.ks` for currently-shipped closure behavior (list map lambda, capturing lambda, non-recursive local fun capture).
- 2026-05-08: Re-ran verification after conformance addition: `./scripts/kestrel test`, `cd compiler && npm test` (458/458), and `./scripts/run-e2e.sh` all passing.
- 2026-05-08: Completed verifier-safe local-fun self/mutual recursion env patching and validated with `./scripts/test-all.sh` (`== All passed ==`).
- 2026-05-08: Expanded self-hosted runtime corpus from 2 to 7 executable files with stdout goldens (`// =>`) for closure, indirect-call, and async local-fun/lambda execution paths.
