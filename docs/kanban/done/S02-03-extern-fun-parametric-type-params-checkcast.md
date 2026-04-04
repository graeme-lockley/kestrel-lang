# `extern fun` (Parametric) — Type Parameters and `checkcast` Emission

## Sequence: S02-03
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/done/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01, S02-02, S02-04, S02-05, S02-06, S02-07, S02-08, S02-09, S02-10, S02-11, S02-12, S02-13

## Summary

Extend `extern fun` (introduced in S02-02) to support type parameters. Parametric `extern fun` is the mechanism for absorbing Java type erasure: when a Java method returns `Object` at the bytecode level but the Kestrel binding author knows the runtime type, a type parameter on the `extern fun` declaration acts as a scoped cast promise. The compiler emits a `checkcast` instruction at the call site when the type parameter is instantiated. This story updates the AST, parser, typecheck, and codegen to handle the parametric form.

## Current State

After S02-02:
- `ExternFunDecl` supports plain `params` and a concrete `returnType`.
- `FunDecl` already has `typeParams?: string[]` — the pattern exists for regular functions.
- Typecheck for `FunDecl` with `typeParams` creates fresh type variables scoped to the signature.
- JVM codegen for `ExternFunDecl` emits the Java method call and leaves the JVM return value (an `Object`) on the stack. No `checkcast` is emitted.

The missing capability: when a type parameter appears in the return type of `ExternFunDecl`, the codegen must emit a `checkcast` to the bound type (if it is a concrete Kestrel reference type at the call site) after the Java method call.

## Relationship to other stories

- **Depends on S02-02**: builds directly on `ExternFunDecl`.
- **Blocks S02-11** (dict rewrite): the dict rewrite uses `extern fun jhmGet<V>(m: JHashMap, k: Any): V = jvm("...")` — this is a parametric extern fun. Without S02-03, S02-11 cannot be implemented.
- **Independent of S02-04 through S02-10** (migrations): the migration stories migrate intrinsics that all have concrete (non-parametric) types except for `stack.ks`'s `__capture_trace` (which is `<T>(value: T): StackTrace<T>`). S02-07 (stack.ks migration) depends on S02-03 for `captureTrace`.
- **Independent of S02-12** (maven) and S02-13 (extern import).

## Goals

1. **AST**: `ExternFunDecl` gains `typeParams?: string[]` (already follows `FunDecl` pattern). No structural AST change needed beyond confirming the field is present if it was omitted in S02-02.
2. **Parser**: `extern fun get<V>(m: JHashMap, k: Any): V = jvm("...")` — parse `<T, U, ...>` after the function name, before the parameter list.
3. **Typecheck**: for each type parameter name, create a fresh type variable scoped to the signature. Substitute the fresh var for the parameter name when resolving parameter and return types. On instantiation at call sites, HM type inference binds the type variable to the concrete type. This is the same mechanism already used for `FunDecl` with `typeParams`.
4. **Codegen — `checkcast` emission**: when a `CallExpr` calls a parametric `extern fun` and the inferred return type at the call site is a concrete reference type (not a type variable), emit `CHECKCAST refType` after the JVM method call instruction. When the inferred type at the call site is still a type variable (used polymorphically), do not emit `checkcast`.
5. **Codegen — primitive return types**: if the type parameter is bound to a Kestrel primitive (`Int`, `Float`, `Bool`, `Char`, `Unit`, `String`) at the call site, no `checkcast` is needed (those are already boxed objects). Emit the appropriate cast target (`Long`, `Double`, `Boolean`, `Integer`, `KUnit`, `String`).

## Acceptance Criteria

- [x] `extern fun get<V>(m: JHashMap, k: Any): V = jvm("java.util.HashMap#get(java.lang.Object)")` parses and typechecks without error.
- [x] Calling `get(myMap, "key")` where context infers `V = String` emits `CHECKCAST java/lang/String` after the `invokevirtual` call.
- [x] Calling `get(myMap, "key")` where context does not constrain `V` (polymorphic use) does NOT emit `checkcast`.
- [x] A multi-parameter type param form `extern fun zip<A, B>(a: List<A>, b: List<B>): List<(A, B)> = jvm("...")` parses and typechecks.
- [x] `stack.ks` `trace<T>(value: T): StackTrace<T>` can be declared as a parametric `extern fun<T>`.
- [x] The dict rewrite in a standalone test (may be pre-S02-11) demonstrates `jhmGet` returning a typed value without explicit casts upstream.
- [x] `cd compiler && npm test` passes.
- [x] Parse-conformance test for the parametric `extern fun` syntax.
- [x] Typecheck-conformance test: parametric `extern fun` return type unifies correctly with call context.

## Spec References

- `docs/specs/01-language.md` — `extern fun` section: document type parameters and the cast-promise semantics.
- `docs/specs/06-typesystem.md` — note that `extern fun` type parameters are not universally quantified in the usual HM sense: they are an assertion by the author that the runtime value conforms to the instantiated type. The trust is scoped to the extern declaration.

## Risks / Notes

- **Checkcast is unsound in theory but safe in practice**: the `checkcast` instruction will throw `ClassCastException` at runtime if the actual return value does not match. Kestrel cannot statically verify this — it trusts the `extern fun` author. This is the same trust that Java generics ask for in unchecked casts. Document this clearly in the spec.
- **When NOT to emit checkcast**: if the parametric return type is `Any` (or an unresolved type variable), no `checkcast` should be emitted. Emitting an incorrect checkcast would throw a spurious `ClassCastException`. The safest rule: only emit `checkcast` when the type variable is instantiated to a *concrete* named reference type (not `Any`, not a still-open type variable).
- **`Any` type**: Kestrel does not currently have a first-class `Any` type, but the epic design uses `Any` in examples (`extern fun jhmGet<V>(m: JHashMap, k: Any): V`). This may require introducing `Any` as a special type alias for `java.lang.Object` in the typecheck environment. Clarify this before implementing — it is a potential S02-01 or S02-02 prerequisite or a new constraint on this story.
- **Interaction with async extern fun**: a parametric `extern fun` that returns `Task<V>` would require the codegen to know the method returns `KTask` (not `Object`). This is the same `taskDescriptor` distinction already in the codebase. Parametric async extern funs are out of scope for this story.

## Impact analysis

| Area | Change |
|------|--------|
| AST | Extend `ExternFunDecl` with optional `typeParams` (matching `FunDecl`). |
| Parser | Parse `extern fun name<T, U>(...)` generic parameter lists before params. |
| Typecheck | Introduce extern-fun signature scope for type params (mirroring generic `FunDecl` behavior) and keep unknown-type validation compatible with local extern type params. |
| JVM codegen | Emit `CHECKCAST` at call sites when a parametric extern fun return resolves to a concrete reference type. |
| Conformance/tests | Add parse and typecheck conformance for parametric extern fun syntax and inference behavior. |
| Specs | Update language/typesystem docs to describe parametric extern cast-promise semantics. |

## Tasks

- [x] Add `typeParams?: string[]` to `ExternFunDecl` in `compiler/src/ast/nodes.ts`.
- [x] Extend extern fun parser path in `compiler/src/parser/parse.ts` to parse `<T, ...>` after function name.
- [x] Update extern fun typecheck branch in `compiler/src/typecheck/check.ts` to resolve signature types with a scoped type-parameter map.
- [x] Adjust extern fun unknown-type validation in `compiler/src/typecheck/check.ts` so local extern type params are treated as known names.
- [x] Add parametric extern binding metadata in `compiler/src/jvm-codegen/codegen.ts` and emit `CHECKCAST` when inferred call-site return type is concrete.
- [x] Ensure no `CHECKCAST` is emitted for unresolved/open type variables.
- [x] Add parse integration coverage in `compiler/test/integration/parse.test.ts` for `extern fun get<T>(...)` form.
- [x] Add typecheck conformance fixtures for parametric extern fun inference success/failure.
- [x] Update `docs/specs/01-language.md` and `docs/specs/06-typesystem.md` for parametric extern fun behavior.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Parse integration | `compiler/test/integration/parse.test.ts` | Accept generic extern fun declarations with multiple type params. |
| Parse conformance | `tests/conformance/parse/valid/*.ks` | Lock grammar for parametric extern fun declarations. |
| Typecheck conformance (valid) | `tests/conformance/typecheck/valid/*.ks` | Verify instantiated return typing (`V` inferred to concrete context type). |
| Typecheck conformance (invalid) | `tests/conformance/typecheck/invalid/*.ks` | Verify bad instantiations or unknown generic names fail with diagnostics. |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — document extern fun type parameter syntax.
- [x] `docs/specs/06-typesystem.md` — document cast-promise semantics and runtime `CHECKCAST` behavior for parametric extern returns.

## Build notes

- 2026-04-04: Started implementation.
- 2026-04-04: Added generic parameter parsing and signature-scoped type resolution for `ExternFunDecl`.
- 2026-04-04: Added call-site `CHECKCAST` emission for concrete parametric extern returns based on inferred call type.
- 2026-04-04: Added parse and conformance fixtures for parametric extern syntax/typecheck behavior.
- 2026-04-04: Verification passed with `cd compiler && npm run build && npm test` and `cd /Users/graemelockley/Projects/kestrel && ./scripts/kestrel test`.
