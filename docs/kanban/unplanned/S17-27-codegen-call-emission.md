# Self-hosted codegen: `ECall` — local, imported, and namespace function calls

## Sequence: S17-27
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-26, S17-28 through S17-38, S17-42

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
- **Blocks**: effectively every other codegen story and S17-42 (E2E) — no useful code can
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
