# Migrate `stack.ks` Format/Trace Intrinsics to `extern fun`

## Sequence: S02-07
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/done/E02-jvm-reflection-interop-and-intrinsic-migration.md)
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

- [x] `stdlib/kestrel/stack.ks` contains no `__format_one`, `__print_one`, or `__capture_trace` calls.
- [x] `format`, `print`, and `trace` are declared as `extern fun` in `stack.ks`.
- [x] `codegen.ts` has no `name === '__format_one'`, `name === '__print_one'`, or `name === '__capture_trace'` blocks.
- [x] `check.ts` has no `env.set('__format_one', ...)`, `env.set('__print_one', ...)`, or `env.set('__capture_trace', ...)`.
- [x] `stdlib/kestrel/stack.test.ks` passes (verifies format output, trace frames structure).
- [x] `cd compiler && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/02-stdlib.md` — `kestrel:stack` module: no API change.

## Risks / Notes

- **`KRuntime.printOne` returns `void`**: the `extern fun` for `print` declares `Unit` return type. The `externReturnDescriptorForType` maps `Unit` → `V`, and `emitExternReturnAsObject` handles void by pushing `KUnit.INSTANCE`. No manual POP needed — the framework handles it correctly.
- **`trace` return type is not a Java type**: `StackTrace<T>` is `{ value: T, frames: List<StackFrame> }` — a pure Kestrel record type alias. The `captureTrace(Object)` method returns a raw `KRecord`. `externReturnDescriptorForType` returns `Ljava/lang/Object;` for `AppType(StackTrace, ...)` since it's not a Task or known extern type. No `checkcast` needed.
- **`__format_one` and `__print_one` are already used everywhere** via `println`/`print` builtins which delegate to `KRuntime.println`/`KRuntime.print`. The intrinsics are only the single-value low-level variants in `stack.ks`. The variadic builtins are NOT in scope here.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/stack.ks` | Replace 3 wrapper `fun` bodies with `export extern fun` declarations binding `KRuntime` static methods |
| `compiler/src/typecheck/check.ts` | Remove 3 `env.set('__format_one', ...)`, `env.set('__print_one', ...)`, `env.set('__capture_trace', ...)` entries |
| `compiler/src/jvm-codegen/codegen.ts` | Remove 3 `if (name === '__format_one'|'__print_one'|'__capture_trace'...)` dispatch blocks |
| Tests | No new tests — existing `stdlib/kestrel/stack.test.ks` covers format/print/trace |
| Specs | `docs/specs/02-stdlib.md` — implementation note only; public API unchanged |

## Tasks

- [x] Replace 3 functions in `stdlib/kestrel/stack.ks` with `export extern fun` declarations
- [x] Remove 3 `env.set` intrinsic entries from `compiler/src/typecheck/check.ts`
- [x] Remove 3 `if (name === '__format_one'|'__print_one'|'__capture_trace'...)` dispatch blocks from `compiler/src/jvm-codegen/codegen.ts`
- [x] Grep for any remaining `__format_one`, `__print_one`, `__capture_trace` references; fix any found
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/stack.test.ks` (existing) | Already covers format/print/trace — no new tests required; verify suite still passes |

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md` — update `kestrel:stack` section (no public API change)

## Build notes

- 2025-06-11: Started implementation. Discovered that `ExternFunDecl` type-checking in `check.ts` was not calling `env.delete(node.name)` before `envFreeVars()` nor removing explicit type param vars from the generalization set. This caused parametric extern funs (like `format<A>` and `print<A>`) to be typed as monomorphic — their type variable leaked into the environment before generalization. Fixed in `check.ts` by mirroring the `FunDecl` pre-generalization steps. Added regression test `tests/conformance/typecheck/valid/extern_fun_parametric_polymorphism.ks`. All 256 compiler tests and 1014 Kestrel tests pass.
