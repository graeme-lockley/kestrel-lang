# `extern fun` (Non-Parametric) — AST, Parser, Typecheck, and JVM Codegen

## Sequence: S02-02
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/unplanned/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01, S02-03, S02-04, S02-05, S02-06, S02-07, S02-08, S02-09, S02-10, S02-11, S02-12, S02-13

## Summary

Introduce `extern fun` as a new top-level declaration that binds a Kestrel function name to a specific Java method (static, instance, or constructor). This story covers the non-parametric form only — type parameters on `extern fun` are handled separately in S02-03. The implementation spans all four compiler layers (AST, parser, typecheck, JVM codegen). After this story, any Kestrel module can declare `extern fun`s calling Java/Kotlin methods without needing a new compiler intrinsic.

## Current State

- No `ExternFunDecl` AST node exists. Function declarations are `FunDecl` with a mandatory `body: Expr`. There is no syntax for a primitive `= jvm("...")` binding form.
- Parser has no `extern fun` production. `parseFunDecl` always expects a body expression after the signature.
- Typecheck has no handling for `ExternFunDecl`. Function type is inferred from the body; here the type must come from the signature alone.
- JVM codegen (`compiler/src/jvm-codegen/codegen.ts`) has no dispatch for `ExternFunDecl`. All top-level function codegen goes through `FunDecl` processing, which walks a body expression. There is no path for emitting a direct `invokestatic`/`invokevirtual`/`invokespecial` without a Kestrel body.
- Call sites: `CallExpr` with an `IdentExpr` callee resolves to a `KFunctionRef` (higher-order value) or emits `INVOKESTATIC className.methodName descriptor`. For `extern fun`, calls must instead emit the corresponding JVM instruction for the bound Java method. The existing `funNames` map in codegen drives this — `extern fun` names must be included in it.

## Relationship to other stories

- **Depends on S02-01**: `ExternFunDecl` parameters and return types may reference `extern type` names. Without S02-01's typecheck registration those names are unresolved unknowns.
- **Blocks S02-04 through S02-10** (all migration stories): every stdlib migration requires `extern fun` declarations to replace the old `__*` calls.
- **Blocks S02-11** (`kestrel:dict`): the dict rewrite uses `extern fun` for all HashMap methods.
- **Independent of S02-03** (parametric): simple `extern fun` without type parameters can be built and landed before S02-03.

## Goals

1. **`ExternFunDecl` AST node**: fields `name: string`, `params: Param[]`, `returnType: Type`, `jvmDescriptor: string` (the string inside `jvm("...")`), `exported: boolean`.
2. **Parser**: `extern fun foo(x: SomeType): RetType = jvm("pkg.Class#method(ArgType)")` and `export extern fun ...` forms. Reject missing `= jvm(...)`.
3. **Typecheck**: register `name` as a function with type `(params) -> returnType` in the environment. Generalize (allow it to be polymorphic) based on signature. No body to infer — the type comes entirely from the declared signature. Type-check that all parameter types and return type are resolvable.
4. **JVM codegen — descriptor parsing**: parse the `jvm("...")` string into:
   - `ownerClass: string` (dot-form → internal slash-form)
   - `methodName: string`
   - `argTypes: string[]` (Java descriptor args)
   - A flag: `static | instance | constructor`
   - Static: `methodName` is not `<init>` and Kestrel param count == Java arg count.
   - Instance: `methodName` is not `<init>` and Kestrel param count == Java arg count + 1 (first Kestrel param is the receiver).
   - Constructor: `methodName` is `<init>` (return type is the class itself).
5. **JVM codegen — call site emission**: when a `CallExpr` calls an `extern fun` name:
   - Emit args; for instance methods emit receiver first then args.
   - Emit `INVOKESTATIC`, `INVOKEVIRTUAL`, or `INVOKESPECIAL` as appropriate.
   - Handle `Unit` return: if Kestrel return type is `Unit` but JVM method returns non-void, emit `POP` to discard.
   - Handle `NEW` + `INVOKESPECIAL` for constructors.
6. **Higher-order use**: when an `extern fun` name appears as a value (not in call position), it should be lifted into a `KFunctionRef` like ordinary functions (reflection-based; the function arity from the Kestrel signature is used).
7. **Export**: `export extern fun` names appear in the module's exported surface.

## Acceptance Criteria

- [ ] `ExternFunDecl` is defined in `compiler/src/ast/nodes.ts` and included in `TopLevelDecl`.
- [ ] Parser accepts `extern fun length(s: String): Int = jvm("java.lang.String#length()")` without error.
- [ ] Parser accepts `export extern fun length(s: String): Int = jvm("java.lang.String#length()")`.
- [ ] Parser rejects `extern fun foo(x: Int): Int` (no `= jvm(...)`) with a clear error.
- [ ] Typecheck registers extern fun in the environment with the declared type.
- [ ] Typecheck error when a parameter or return type references an unresolved name.
- [ ] JVM codegen emits correct bytecode for a static extern fun (`jvm("Cls#staticMethod(ArgType)")`).
- [ ] JVM codegen emits correct bytecode for an instance extern fun where first param is the receiver.
- [ ] JVM codegen emits correct `NEW` + `INVOKESPECIAL` for constructor `jvm("Cls#<init>(ArgTypes)")`.
- [ ] `Unit` return discards the JVM return value with `POP` if the JVM method returns a non-void type.
- [ ] A runtime-conformance test exercises a non-parametric `extern fun` end-to-end.
- [ ] `cd compiler && npm test` passes.

## Spec References

- `docs/specs/01-language.md` — add `extern fun` to the declarations section, document the `jvm("...")` binding form and the static/instance/constructor dispatch rules.
- `docs/specs/06-typesystem.md` — note that `extern fun` injects a typed binding without a body; the declared type is treated as ground truth.

## Risks / Notes

- **Descriptor parser complexity**: Valid JVM descriptors have a specific canonical form (`Lpkg/Class;` for reference types, `I`, `J`, `D`, etc. for primitives, `[T` for arrays). However, the `extern fun` descriptor format in the Kestrel epic uses a human-readable form: `jvm("java.util.HashMap#put(java.lang.Object,java.lang.Object)")`. The compiler must convert this to real JVM internal form. This parser needs careful implementation and test coverage.
- **Instance vs. static disambiguation**: The heuristic "if Kestrel param count = Java arg count + 1 → instance" is fragile if the programmer writes the wrong number of params. Emit a clear compile-time error (not a cryptic NoSuchMethodError at runtime) when instance/static classification disagrees with the Kestrel signature.
- **Return type boxing**: Java methods returning primitive `int`, `long`, `boolean` etc. need boxing to Kestrel's `Long`, `Boolean`, etc. When the Kestrel return type is declared `Int`, the codegen must emit an `invokestatic Long.valueOf(J)` after a `long`-returning method. The `jvm("...")` descriptor does not carry the JVM return type — the Kestrel return type declaration drives the unboxing/boxing decision.
  - **Practical concern**: most methods being bound go through `KRuntime` which already returns boxed types. For direct JDK method bindings (S02-11 dict rewrite), this matters greatly.
- **`async` + `extern fun`**: this story explicitly covers only synchronous `extern fun`. Async extern functions (ones returning `Task<T>`) are a plausible extension but are not in scope here — they require the same codegen distinction that `taskDescriptor` vs `descriptor` already handles, but wired through the `ExternFunDecl` path. Defer to S02-02 follow-up or S02-03.
- **`KFunctionRef` for higher-order extern fun**: the existing `KFunctionRef.of(Class, String, int)` uses reflection. Wrapping an `extern fun` in a `KFunctionRef` therefore still uses reflection at the point of first-class value creation; only direct calls are zero-reflection. This is acceptable for the current implementation.

## Impact analysis

| Area | Change |
|------|--------|
| AST | Add `ExternFunDecl` node and include it in `TopLevelDecl` so `extern fun` can be represented without a body expression. |
| Lexer/Parser | Parse `extern fun` in local/export forms and enforce `= jvm("...")` RHS shape with targeted parse diagnostics. |
| Typecheck | Register extern functions directly from declared signatures (including unresolved-type diagnostics) and include exported extern funs in module export maps. |
| JVM codegen | Add extern binding metadata pass and call-site lowering for static/instance/constructor Java dispatch (`INVOKESTATIC`, `INVOKEVIRTUAL`, `NEW` + `INVOKESPECIAL`). |
| Runtime interop boundary | Add JVM descriptor parsing helpers (owner/member/arg list + call kind) and return-value shaping (`POP` for Unit mismatch). |
| Tests | Add parser + codegen/integration coverage for `extern fun` syntax and generated call behavior; add conformance runtime smoke. |
| Specs | Update language/typesystem specs for declaration form and bodyless typed-binding semantics. |

## Tasks

- [ ] Add `ExternFunDecl` to `compiler/src/ast/nodes.ts` and include it in `TopLevelDecl`.
- [ ] Extend parser logic in `compiler/src/parser/parse.ts` to parse `extern fun` and `export extern fun` signatures with `= jvm("...")` and emit clear errors for missing/invalid RHS.
- [ ] Extend type registration and export collection in `compiler/src/typecheck/check.ts` so extern funs are typed from signatures and exported like ordinary functions.
- [ ] Add JVM binding parser/helper(s) in `compiler/src/jvm-codegen/` for `jvm("Class#method(args)")` forms, class internal-name conversion, and call-kind classification.
- [ ] Wire extern function metadata into codegen symbol tables in `compiler/src/jvm-codegen/codegen.ts` so call sites can distinguish extern/static/instance/constructor targets.
- [ ] Implement extern call emission in `compiler/src/jvm-codegen/codegen.ts` for static, instance, and constructor invocations, including Unit return discard via `POP` when needed.
- [ ] Ensure first-class references to extern fun names still lower to `KFunctionRef` with correct arity in `compiler/src/jvm-codegen/codegen.ts`.
- [ ] Add parser/integration tests in `compiler/test/integration/parse.test.ts` for valid and invalid extern fun declarations.
- [ ] Add codegen/runtime coverage in compiler integration tests for direct extern static/instance/constructor calls.
- [ ] Add conformance fixture(s) under `tests/conformance/runtime/valid/` and/or typecheck conformance for extern fun non-parametric usage.
- [ ] Update `docs/specs/01-language.md` and `docs/specs/06-typesystem.md` for extern fun syntax/typing semantics.
- [ ] Run `cd compiler && npm run build && npm test`.
- [ ] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest parser integration | `compiler/test/integration/parse.test.ts` | Parse `extern fun` and `export extern fun`, and reject declarations missing `= jvm(...)`. |
| Vitest codegen integration | `compiler/test/integration/jvm-*.test.ts` | Validate generated bytecode dispatch for static, instance, and constructor extern bindings. |
| Runtime conformance | `tests/conformance/runtime/valid/*.ks` | Exercise end-to-end extern fun call behavior from source through JVM runtime. |
| Typecheck conformance | `tests/conformance/typecheck/valid/*.ks` / `invalid/*.ks` | Ensure signature-only typing works and unresolved type references fail with diagnostics. |

## Documentation and specs to update

- [ ] `docs/specs/01-language.md` — add `extern fun` declaration grammar and `jvm("...")` binding form semantics.
- [ ] `docs/specs/06-typesystem.md` — specify that extern fun introduces a typed function binding from declaration signature without body inference.
