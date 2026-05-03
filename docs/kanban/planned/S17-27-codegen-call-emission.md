# Self-hosted codegen: `ECall` — local, imported, and namespace function calls

## Sequence: S17-27
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-26, S17-28 through S17-38, S17-44

## Summary

`ECall` is the most critical expression form and is currently a complete stub: the self-hosted
codegen evaluates the callee and all arguments, discards everything, and pushes `null`. No
function call is ever actually emitted. This means every Kestrel program compiled by the
self-hosted driver produces incorrect results or crashes at runtime.

## Current State

```kestrel
ECall(fn, args) => {
  emitExpr(ctx, fn)
  CF.mbEmit1(ctx.mb, Op.JvmOp.pop)  // callee discarded
  emitExprList(ctx, args)            // args discarded
  pushNull(ctx)                      // returns null
}
```

The TS reference has ~350 lines for call emission covering:
- **Direct local call**: `INVOKESTATIC ClassName.methodName(args...)` — requires knowing
  the method name, the JVM descriptor, and argument count.
- **Direct namespace call** (`EField(EIdent("Ns"), "method")`): `INVOKESTATIC` with the
  imported class name.
- **Indirect call** (function reference / lambda): unwrap to `KFunc` / `KTask`, call
  `invoke(Object[])`.
- **Async direct call**: wrap in `KTask`, then invoke.
- **Extern JVM calls**: use the extern binding JVM descriptor to emit the exact JVM method
  call (INVOKESTATIC / INVOKEVIRTUAL / INVOKEINTERFACE).
- **ADT constructor calls**: `NEW CtorClass; DUP; INVOKESPECIAL <init>; putField...`.

## Relationship to other stories

- **Depends on**: S17-24 (literals), S17-25 (EIdent — needed to resolve callee names),
  S17-26 (operators — prerequisite for non-trivial arguments).
- **Execution tranche priority**: this is the first runtime-sensitive story after S17-25 + S17-37.
  Real calls are required before re-enabling almost any skipped runtime-negative or positive E2E.
- **Blocks**: effectively every other codegen story and S17-44 (E2E) — no useful code can
  be generated without function calls.

## Goals

1. Detect the call shape from the callee expression:
   a. `EIdent(name)` where `name` is a known local fun → `INVOKESTATIC` direct call.
   b. `EField(EIdent(ns), method)` where `ns` is a known namespace import → `INVOKESTATIC`
      on the imported class.
   c. `EIdent(name)` where `name` is a known imported fun → `INVOKESTATIC $init;
      INVOKESTATIC ImportedClass.methodName`.
   d. ADT constructor call (arity > 0) → `NEW CtorClass; DUP; INVOKESPECIAL <init>;
      PUTFIELD` for each argument.
   e. Otherwise → indirect call via `KFunc.invoke(Object[])`.
2. Emit arguments: for direct calls push each arg onto the stack individually; for indirect
   calls build an `Object[]` array.
3. For `extern` JVM functions emit the exact JVM method call using the stored JVM descriptor.
4. Preserve correct JVM stack depth and frame state after the call.

## Acceptance Criteria

- [ ] `foo(1, 2)` where `foo` is a local function produces the correct return value.
- [ ] `List.map(lst, f)` (namespace import call) produces the correct result.
- [ ] A user-defined ADT constructor call `Cons(head, tail)` produces a valid `Cons` object.
- [ ] An `extern fun` call (e.g. `Str.length("hello")`) produces the correct JVM result.
- [ ] Indirect call through a function-reference value works correctly.
- [ ] New codegen unit tests cover each call shape.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — function call expression
- `docs/specs/07-modules.md` — namespace and import resolution

## Risks / Notes

- JVM method descriptors for Kestrel functions use `(Ljava/lang/Object;...)Ljava/lang/Object;`
  uniformly. Extern functions use JVM-specific descriptors stored in `ExternFunDecl.jvmDesc`.
  Both must be threaded through the codegen context.
- Tail-call optimization (the loop-back GOTO) is a separate story (S17-35) but must not
  conflict with direct call emission here. Emit `INVOKESTATIC` + `ARETURN` initially; the
  tail-call story converts qualifying call+return pairs into `GOTO loopHead`.
- Async call wrapping is addressed in S17-36 (`EAwait`).
- This story is the main gate for restoring the runtime-negative scenarios that currently never
  execute under the temporary startup shim. Expect it to be validated first with tiny direct-call
  fixtures, then with the runtime-negative E2Es once S17-30/S17-33 are also real.
- **Namespace classes gap**: The self-hosted `JvmCodegenOptions` type (in `codegen.ks`) has no
  `namespaceClasses` field. The TS reference uses `options.namespaceClasses` to resolve
  `ECall(EField(EIdent("Ns"), "method"), args)`. The `kti.ks` `IDNamespace` branch currently
  does not populate any codegen map for namespace aliases. Both `codegen.ks` and `kti.ks` must
  be extended to carry `namespaceClasses: Dict<String, String>` (alias → JVM class) and
  `namespaceAdtConstructors: Dict<String, Dict<String, String>>` (alias → (ctor → JVM class)).
- **INVOKEINTERFACE encoding**: The indirect call path emits `INVOKEINTERFACE` via
  `Op.JvmOp.invokeinterface` (opcode 185), followed by a 2-byte interface method ref index
  and two padding bytes (nargs, 0). Use `CF.mbEmit1s` + `CF.mbPushByte`×2, or the
  `CF.cfIfaceMethodref` constant-pool builder.
- **Temp slot collisions**: The indirect call path requires at least two temp local slots
  (CALLEE_TEMP = 60, ARG_TEMP_BASE = 61…) mirroring the TS reference. Allocate using
  `ctx.nextLocal` (`bindLocal`) rather than hard-coded slots to avoid conflicts with
  in-flight locals.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/tools/compiler/codegen.ks` | Replace ~6-line `ECall` stub in `emitExpr` with full ~120-line implementation. Add helper functions: `emitDirectCall`, `emitIndirectCall`, `emitBuiltinCall`, `emitAdtCtorCall`. Add `namespaceClasses: Dict<String, String>` and `namespaceAdtConstructors: Dict<String, Dict<String, String>>` fields to `JvmCodegenOptions` type and `emptyJvmCodegenOptions()`. |
| `stdlib/kestrel/tools/compiler/kti.ks` | Add `namespaceClasses` and `namespaceAdtConstructors` fields to `DepBindingBundle` type and `emptyDepBundle()`. Populate both fields in the `IDNamespace` branch of `loadDepBindings`: map the alias to the dep's JVM class name and collect the dep's ADT constructor-to-class map. |
| `stdlib/kestrel/tools/compiler/driver.ks` | Pass `namespaceClasses` and `namespaceAdtConstructors` from `depBindings` when constructing `JvmCodegenOptions` in the compile path. |
| `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Add test groups: local direct call emits correct INVOKESTATIC sequence; ADT ctor call (`Some`/`Cons`/user-defined) emits NEW+DUP+args+INVOKESPECIAL; indirect call emits INVOKEINTERFACE; `println` emits `KRuntime.println`; namespace call emits correct INVOKESTATIC for namespace class. |
| `tests/conformance/runtime/valid/` | Add new runtime fixtures: `call_direct.ks`, `call_namespace.ks`, `call_indirect.ks`, `call_adt_ctor.ks` — each with `println` golden output lines. |
| Compatibility | Purely additive at the codegen level. The stub produced `null`; real emission is a behavioural fix. No existing passing tests should regress. Many currently-failing runtime conformance and E2E tests may start passing. |

## Tasks

- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks`: add `namespaceClasses: Dict<String, String>` and `namespaceAdtConstructors: Dict<String, Dict<String, String>>` fields to `JvmCodegenOptions`; update `emptyJvmCodegenOptions()` to initialise both to empty dicts.
- [ ] In `stdlib/kestrel/tools/compiler/kti.ks`: add `namespaceClasses: Dict<String, String>` and `namespaceAdtConstructors: Dict<String, Dict<String, String>>` fields to `DepBindingBundle` type and `emptyDepBundle()`; in the `IDNamespace` branch of `loadDepBindings`, populate `namespaceClasses` (alias → `depClassName`) and `namespaceAdtConstructors` (alias → `depCtorOwners` map filtered to this dep).
- [ ] In `stdlib/kestrel/tools/compiler/driver.ks`: extend the `JvmCodegenOptions` record literal to pass `namespaceClasses = depBindings.namespaceClasses` and `namespaceAdtConstructors = depBindings.namespaceAdtConstructors`.
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks` `emitExpr` ECall branch — implement built-in constructor specials: `Some(v)` → `NEW KSome; DUP; arg; INVOKESPECIAL <init>(Object)V`; `Cons(h,t)` → store head/tail, `NEW KCons; DUP; ALOAD head; ALOAD tail; INVOKESPECIAL <init>(Object,KList)V`; `Err(v)` → `NEW KErr; DUP; arg; INVOKESPECIAL <init>`; `Ok(v)` → `NEW KOk; DUP; arg; INVOKESPECIAL <init>`.
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks` `emitExpr` ECall branch — implement user-defined ADT constructor calls: look up `adtClassByConstructor` and `adtConstructorArity`; emit `NEW ctorClass; DUP; push args; INVOKESPECIAL <init>(Object×n)V`.
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks` `emitExpr` ECall branch — implement built-in function calls: `println`/`print` → build Object[] via `ANEWARRAY`; `INVOKESTATIC KRuntime.println/print([Object)V`; push `KUnit.INSTANCE`; `exit(v)` → push arg; `INVOKESTATIC KRuntime.exit(Object)V`; push `KUnit.INSTANCE`; `concat(a,b)` → push two args; `INVOKESTATIC KRuntime.concat(Object,Object)String`.
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks` `emitExpr` ECall branch — implement direct local-function calls: when `ECall(EIdent(name), args)` and `Dict.member(mctx.funArities, name)`, emit `$init` if cross-class (not needed for same class), push args individually, `INVOKESTATIC className.jvmMangleName(name)(objectMethodDesc(arity))`.
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks` `emitExpr` ECall branch — implement named-imported function calls: when `Dict.member(mctx.options.importedNameToClass, name)`, call `emitInitCall(ctx, importedClass)`, push args, `INVOKESTATIC importedClass.jvmMangleName(origName)(objectMethodDesc(arity))`.
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks` `emitExpr` ECall branch — implement namespace calls for `ECall(EField(EIdent(ns), method), args)`: look up `nsClass = mctx.options.namespaceClasses.get(ns)`; if found, first check `namespaceAdtConstructors` for a ctor match (emit `NEW + INVOKESPECIAL`); otherwise call `emitInitCall(ctx, nsClass)`, push args, `INVOKESTATIC nsClass.jvmMangleName(method)(objectMethodDesc(arity))`.
- [ ] In `stdlib/kestrel/tools/compiler/codegen.ks` `emitExpr` ECall branch — implement indirect call fallback: `emitExpr` callee → `ASTORE calleeTemp`; push args → `ASTORE argTemp[i]` (right-to-left); `LDC_W n; ANEWARRAY Object; DUP; LDC_W i; ALOAD argTemp[i]; AASTORE` for each arg; `ALOAD calleeTemp; CHECKCAST KFunction; SWAP; INVOKEINTERFACE KFunction.apply([Object)Object nargs=2 0`.
- [ ] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`: add test group "local direct call" — build a `ModuleContext` with a known fun in `funArities`, emit `ECall(EIdent("myFun"), [ELit("int","1")])`, verify bytecode contains INVOKESTATIC opcode (0xB8 = 184).
- [ ] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`: add test group "ADT ctor call" — emit `ECall(EIdent("Some"), [ELit("int","1")])`, verify NEW (0xBB = 187) and INVOKESPECIAL (0xB7 = 183) opcodes are present.
- [ ] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`: add test group "println call" — emit `ECall(EIdent("println"), [ELit("string","hello")])`, verify INVOKESTATIC (184) is present and class bytes are valid.
- [ ] In `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`: add test group "indirect call" — emit `ECall(ELambda(False,[],[{name="x",type_=None}],EIdent("x")), [ELit("int","5")])`, verify INVOKEINTERFACE opcode (0xB9 = 185) is present.
- [ ] Add `tests/conformance/runtime/valid/call_direct.ks` — a module that defines a local fun and calls it; includes `println` + `//` stdout golden.
- [ ] Add `tests/conformance/runtime/valid/call_namespace.ks` — a module that does `import * as Str from "kestrel:data/string"` and calls `Str.length("hello")`; includes `println` + golden.
- [ ] Add `tests/conformance/runtime/valid/call_indirect.ks` — a module that passes a function reference and calls it; includes `println` + golden.
- [ ] Add `tests/conformance/runtime/valid/call_adt_ctor.ks` — a module that defines a user ADT and constructs it; pattern-matches result; includes `println` + golden.
- [ ] Run `cd compiler && npm run build && npm test`
- [ ] Run `./scripts/kestrel test`
- [ ] Run `./scripts/run-e2e.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel codegen unit | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | "local direct call": ECall(EIdent("f"), [arg]) where f is in `funArities` emits INVOKESTATIC (opcode 184) |
| Kestrel codegen unit | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | "ADT ctor call": ECall(EIdent("Some"), [arg]) emits NEW (187) and INVOKESPECIAL (183) |
| Kestrel codegen unit | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | "println call": ECall(EIdent("println"), [ELit(...)]) emits INVOKESTATIC KRuntime.println and leaves KUnit |
| Kestrel codegen unit | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | "indirect call": ECall(lambda, [arg]) emits INVOKEINTERFACE (185) for KFunction.apply |
| Conformance runtime | `tests/conformance/runtime/valid/call_direct.ks` | Direct local call: `fun add(a, b) = a + b; println(add(3, 4))` → golden `7` |
| Conformance runtime | `tests/conformance/runtime/valid/call_namespace.ks` | Namespace call: `import * as Str from "kestrel:data/string"; println(Str.length("hello"))` → golden `5` |
| Conformance runtime | `tests/conformance/runtime/valid/call_indirect.ks` | Indirect call: pass function reference, invoke through it → golden correct value |
| Conformance runtime | `tests/conformance/runtime/valid/call_adt_ctor.ks` | User ADT constructor and pattern-match → golden correct value |

## Documentation and specs to update

- [ ] `docs/specs/01-language.md` — verify call expression section reflects all call shapes now supported (local, namespace, imported, indirect); no prose changes expected but confirm spec is accurate.
- [ ] `docs/specs/07-modules.md` — verify namespace import call section matches new codegen behaviour (`ECall(EField(EIdent(ns), method), args)` path); no changes expected but confirm.
