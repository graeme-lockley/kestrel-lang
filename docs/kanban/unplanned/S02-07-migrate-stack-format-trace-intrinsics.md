# Migrate `stack.ks` Format/Trace Intrinsics to `extern fun`

## Sequence: S02-07
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/unplanned/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01, S02-02, S02-03, S02-04, S02-05, S02-06, S02-08, S02-09, S02-10, S02-11, S02-12, S02-13

## Summary

Replace the three intrinsics in `stdlib/kestrel/stack.ks` — `__format_one`, `__print_one`, and `__capture_trace` — with `extern fun` declarations. `__capture_trace` is architecturally distinct: it is parametric (`<T>`) and its return type is a complex Kestrel record (`StackTrace<T>`). This story therefore depends on S02-03 (parametric extern fun) in addition to S02-02.

## Current State

**Three intrinsics in `stack.ks`:**
- `__format_one(x: Any): String` → `KRuntime.toString(Object): String`
- `__print_one(x: Any): Unit` → `KRuntime.printFormat(Object): void`
- `__capture_trace<T>(value: T): StackTrace<T>` → `KRuntime.captureTrace(Object): Object`

**Current `stack.ks`:**
```kestrel
// kestrel:stack — format, print (VM primitives); trace via __capture_trace (spec 02).
import * as List from "kestrel:list"

export type StackFrame = { file: String, line: Int, function: String }
export type StackTrace<T> = { value: T, frames: List<StackFrame> }

export fun format(x): String          = __format_one(x)
export fun print(x): Unit             = __print_one(x)
export fun trace<T>(value: T): StackTrace<T> = __capture_trace(value)
```

**`__capture_trace` type in `check.ts`** (lines ~1723–1740):
```typescript
env.set('__capture_trace', generalize({
  kind: 'arrow',
  params: [captureArgT],
  return: {
    kind: 'record',
    fields: [
      { name: 'value', mut: false, type: captureArgT },
      { name: 'frames', mut: false, type: { kind: 'app', name: 'List', args: [stackFrameRow] } },
    ],
  },
}, new Set()));
```

**`__format_one` type**: generic `<A>(A): String`. Uses a fresh type variable.
**`__print_one` type**: generic `<A>(A): Unit`. Uses a fresh type variable.

**`codegen.ts`** (lines ~1599–1618):
```typescript
if (name === '__format_one' && expr.args.length === 1) {
  ...INVOKESTATIC KRuntime.toString(Object): String
}
if (name === '__print_one' && expr.args.length === 1) {
  ...INVOKESTATIC KRuntime.printFormat(Object): void + push KUnit
}
if (name === '__capture_trace' && expr.args.length === 1) {
  ...INVOKESTATIC KRuntime.captureTrace(Object): Object
}
```

## Relationship to other stories

- **Depends on S02-02**: requires `extern fun`.
- **Depends on S02-03**: `__capture_trace` is parametric — `trace<T>(value: T): StackTrace<T>`. Without S02-03, the parametric extern fun cannot be declared.
- **Depends on S02-01**: `StackTrace<T>` in the return type of `trace` may need `extern type` if `StackTrace` is to be an opaque JVM type. However, `StackTrace<T>` is currently a Kestrel record type alias — not a Java type. So S02-01 is not strictly required for this migration unless the design changes.
- **Independent of S02-04, S02-05, S02-06, S02-08, S02-09, S02-10**.

## Goals

1. Replace `format(x)` with a parametric extern fun:
   ```kestrel
   export extern fun format<A>(x: A): String =
     jvm("kestrel.runtime.KRuntime#toString(java.lang.Object)")
   ```
2. Replace `print(x)` with a parametric extern fun:
   ```kestrel
   export extern fun print<A>(x: A): Unit =
     jvm("kestrel.runtime.KRuntime#printFormat(java.lang.Object)")
   ```
3. Replace `trace<T>(value: T): StackTrace<T>` with a parametric extern fun:
   ```kestrel
   export extern fun trace<T>(value: T): StackTrace<T> =
     jvm("kestrel.runtime.KRuntime#captureTrace(java.lang.Object)")
   ```
   The return type is the Kestrel record type `StackTrace<T>`, not a Java type. The codegen must handle this: `captureTrace` returns `Object` (a `KRecord` at runtime) which the Kestrel type system treats as `StackTrace<T>`. No `checkcast` is needed — the runtime guarantee is upheld by `KRuntime`.
4. Remove all three `if (name === '__format_one' | '__print_one' | '__capture_trace') { ... }` blocks from `codegen.ts`.
5. Remove all three `env.set('__format_one', ...)`, `env.set('__print_one', ...)`, `env.set('__capture_trace', ...)` bindings from `check.ts`.

## Acceptance Criteria

- [ ] `stdlib/kestrel/stack.ks` contains no `__format_one`, `__print_one`, or `__capture_trace` calls.
- [ ] `format`, `print`, and `trace` are declared as `extern fun` in `stack.ks`.
- [ ] `codegen.ts` has no `name === '__format_one'`, `name === '__print_one'`, or `name === '__capture_trace'` blocks.
- [ ] `check.ts` has no `env.set('__format_one', ...)`, `env.set('__print_one', ...)`, or `env.set('__capture_trace', ...)`.
- [ ] `stdlib/kestrel/stack.test.ks` passes (verifies format output, trace frames structure).
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/02-stdlib.md` — `kestrel:stack` module: no API change.

## Risks / Notes

- **`KRuntime.printFormat` returns `void`**: the current codegen explicitly pops the result and pushes `KUnit`. The `extern fun` for `print` must declare `Unit` as the return type, and codegen must handle void-returning methods → push `KUnit`. This is a case of the `POP + push KUnit` pattern from S02-02.
- **`trace` return type is not a Java type**: `StackTrace<T>` is `{ value: T, frames: List<StackFrame> }` — a pure Kestrel record type alias. The `captureTrace(Object)` method returns a raw `KRecord` (the Java runtime representation of a Kestrel record). The extern fun type annotation says the value conforms to `StackTrace<T>`. No JVM `checkcast` is needed because `KRecord` is the base type for all record values. This is a subtle difference from parametric extern funs returning named extern types where checkcast is needed.
- **`__format_one` and `__print_one` are already used everywhere** (via `println`/`print` built-ins which delegate to `KRuntime.println`/`KRuntime.print`). The `__format_one` and `__print_one` intrinsics are only the single-value low-level variants exposed in `stack.ks`. The variadic builtins `println(...)` are handled separately by the `println` built-in path in codegen and are NOT in scope here.
