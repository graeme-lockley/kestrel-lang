# `extern fun` — Fix Primitive JVM Return Type Descriptor Mismatch

## Sequence: S02-14
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/done/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01 through S02-13, S02-15, S02-16, S02-17, S02-18

## Summary

`extern fun` bindings to JVM methods that return primitive types (`int`, `long`, `boolean`, `double`, etc.) silently produce wrong bytecode that causes `java.lang.NoSuchMethodError` at runtime, with **no compile-time diagnostic**. Additionally, `extern fun` bindings that pass Kestrel `Int` or `Bool` to Java methods expecting narrow primitives (`short`, `byte`, `char`) produce `ClassCastException` at runtime.

The root cause is a mismatch between `externReturnDescriptorForType` — which maps Kestrel `Int` → `Ljava/lang/Long;` (boxed) — and the actual JVM method descriptor used in INVOKESTATIC/INVOKEVIRTUAL, which for a method like `Math.abs(long): long` is `(J)J`, not `(J)Ljava/lang/Long;`. The JVM verifies exact descriptor matches and throws `NoSuchMethodError` when they differ. The compiler accepts the declaration with no warning.

## Current State

- `externReturnDescriptorForType` in `compiler/src/jvm-codegen/codegen.ts` derives the JVM return descriptor solely from the Kestrel return type annotation, always choosing the **boxed** descriptor.
- The actual JVM return type (primitive vs. boxed) is only known from the `jvm("Class#method(Args)")` descriptor string, which does not encode the return type at all.
- `emitExternReturnAsObject` already has correct boxing paths for every JVM primitive (`J`→`Long.valueOf`, `Z`→`Boolean.valueOf`, etc.) — they simply are never reached for methods whose Kestrel return type is `Int`, `Bool`, or `Float`.
- `emitExternArgFromLocal` correctly handles narrow-primitive parameter descriptors (`S`, `B`, `C`) by unboxing from `java.lang.Short` / `java.lang.Byte` / `java.lang.Integer`, but Kestrel's type mapper maps `short`, `byte`, `char` → `Int` (stored as `java.lang.Long`), so the `CHECKCAST java/lang/Short` on a `Long` instance throws `ClassCastException`.
- The only workaround today is to use JVM wrapper methods that already return boxed types (e.g. KRuntime helpers), defeating the purpose of `extern fun`.

## Relationship to other stories

- **Depends on S02-02**: the core `extern fun` codegen pipeline built there.
- **Related to S02-13**: `extern import` auto-generates `extern fun` stubs for every public method; any method returning a primitive (e.g. `HashMap.size(): int`) produces a broken stub — same root cause. This story fixes the codegen; S02-13 auto-generated stubs are implicitly fixed once this story lands.
- **Related to S02-18**: the missing regression tests for primitive return types are added in S02-18.

## Goals

1. The `jvm("...")` descriptor string is extended (optionally) to encode the JVM return type: `jvm("Class#method(Args):ReturnType")`. Example: `jvm("java.lang.Math#abs(long):long")`. The `:ReturnType` suffix is a Java source-level type name and is optional for backwards compatibility (existing `jvm(...)` strings without the suffix continue to work, using the current boxed-type derivation for methods that return reference types).
2. When the `:ReturnType` suffix is present, codegen uses its descriptor (`J`, `Z`, `D`, `I`, etc.) as the JVM method return in the constant-pool entry, and routes the return value through the existing boxing path in `emitExternReturnAsObject`.
3. For `extern import` auto-generation (`expandExternImports` in `compile-file-jvm.ts`), the actual JVM binary return descriptor is already available from `javap` metadata — it is propagated into the generated `ExternFunDecl.jvmDescriptor` automatically (no user action required).
4. `emitExternArgFromLocal` is fixed so that narrow-primitive parameter descriptors (`B`, `S`) correctly unbox from `java.lang.Long` (not `Short` / `Byte`) — because the Kestrel caller passes a `Long`. Similarly, `C` remains mapped correctly (via `Integer` → `int` cast).
5. A compile-time warning (or error, TBD by risk analysis) is emitted when the `:ReturnType` suffix is absent and the Kestrel return type is `Int`, `Float`, or `Bool`, indicating that the JVM method may return a primitive. The message should direct the user to add the suffix.

## Acceptance Criteria

- [ ] `extern fun mathAbs(x: Int): Int = jvm("java.lang.Math#abs(long):long")` compiles and returns the correct value at runtime.
- [ ] `extern fun strLen(s: String): Int = jvm("java.lang.String#length():int")` compiles and returns the correct value at runtime.
- [ ] `extern fun strContains(s: String, b: Bool): Bool = jvm("java.lang.String#isEmpty():boolean")` compiles and returns the correct `Bool` at runtime.
- [ ] Existing `extern fun` declarations without a `:ReturnType` suffix continue to work unchanged (backwards compatible).
- [ ] `extern import` auto-generates correct JVM descriptors (with return type) for all methods, including those returning primitive types such as `size(): int` and `isEmpty(): boolean`.
- [ ] A runtime conformance test covers at least one `extern fun` to a method returning a JVM primitive (`int`, `boolean`, `double`).
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Impact analysis

| Area | Change |
|------|--------|
| `compiler/src/jvm-codegen/codegen.ts` | Update `parseExternJvmBinding` to accept optional `:ReturnType` suffix and return it; use parsed descriptor when present to set `ExternBinding.jvmReturnDescriptor`; fix `emitExternArgFromLocal` for `B`/`S` to unbox from `Long` |
| `compiler/src/jvm-metadata/index.ts` | Update `generateStubs` and `StubMethod.jvmDescriptor` to include `:ReturnType` suffix for primitive-returning methods |
| `compiler/src/compile-file-jvm.ts` | Update `expandExternImports` to include `:ReturnType` suffix in the `jvmDescriptor` for primitive-returning methods |
| `tests/conformance/runtime/valid/` | Add `extern_fun_primitive_return.ks` conformance test (added in S02-18) |
| `compiler/test/unit/` | Add unit tests for `parseExternJvmBinding` with `:ReturnType` suffix (parsing, descriptor extraction) |
| `compiler/test/integration/extern-import.test.ts` | Update pattern check to allow `):ReturnSuffix` in `jvm("...")` strings |
| `docs/specs/01-language.md` | Update `extern fun` description to show optional `:ReturnType` suffix |

## Tasks

- [x] Update `parseExternJvmBinding` in `compiler/src/jvm-codegen/codegen.ts` to accept optional `:ReturnType` suffix after `)` and return `jvmReturnDescriptor?: string`
- [x] In the `ExternFunDecl` processing block, use parsed `jvmReturnDescriptor` from `parseExternJvmBinding` when present, falling back to `externReturnDescriptorForType(fun.returnType)` only when absent
- [x] Fix `emitExternArgFromLocal` for `B`: unbox from `java.lang.Long` via `longValue()` + L2I (long-to-int, JVM accepts int for byte params)
- [x] Fix `emitExternArgFromLocal` for `S`: unbox from `java.lang.Long` via `longValue()` + L2I (long-to-int, JVM accepts int for short params)
- [x] Update `generateStubs` in `compiler/src/jvm-metadata/index.ts` to append `:ReturnType` in `StubMethod.jvmDescriptor` when the method returns a primitive Java type
- [x] Update `expandExternImports` in `compiler/src/compile-file-jvm.ts` to include `:ReturnType` in the generated `jvmDescriptor` when `m.javaReturnType` is a primitive
- [x] Update `extern-import.test.ts` regex to allow new `:ReturnType` suffix in `jvm("...")` string
- [x] Update `docs/specs/01-language.md` to document the optional `:ReturnType` suffix in the `jvm("...")` descriptor
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit | `compiler/test/unit/jvm-codegen.test.ts` (new) | `parseExternJvmBinding` parses `:ReturnType` suffix for `long`, `int`, `boolean`, `double`, `void` |
| Conformance runtime | `tests/conformance/runtime/valid/extern_fun_primitive_return.ks` | Added in S02-18 after fix lands |

## Documentation and specs to update

- [x] `docs/specs/01-language.md` — update `extern fun` description to show `jvm("Class#method(Args):ReturnType")` optional `:ReturnType` suffix

## Build notes

- 2026-04-04: `parseExternJvmBinding` updated to accept optional `:ReturnType` suffix by checking `afterClose` string after `)`. Backwards-compatible: existing `jvm(...)` strings without suffix continue to work unchanged, as `externReturnDescriptorForType` is used as fallback.
- 2026-04-04: `emitExternArgFromLocal` for `B`/`S` fixed to unbox from `java.lang.Long` via `longValue()` + `L2I`. The JVM accepts `int` (32-bit) on the stack for both `byte` and `short` parameters — no additional narrowing instruction is needed. The `long → int` conversion is sufficient.
- 2026-04-04: `generateStubs` and `expandExternImports` both updated to append `:ReturnType` for primitive-returning methods. The `primitiveReturnTypes` set is defined locally in each function; this avoids exporting an intermediate constant.
- 2026-04-04: Updated `jvm-metadata.test.ts` expectations for `size()` descriptor to `java.util.HashMap#size():int`. Updated `extern-import.test.ts` sidecar line regex to allow complex return type patterns.
- 2026-04-04: All 313 compiler tests pass; 1020 kestrel tests pass.

## Spec References

- `docs/specs/01-language.md` — update `ExternFunDecl` grammar to show optional `:ReturnType` suffix in the `jvm("...")` string.

## Risks / Notes

- **Backwards compatibility**: existing `jvm(...)` strings (no `:ReturnType`) must continue to work. The `:ReturnType` suffix is a new optional convention, not a breaking change.
- **Auto-generated stubs are silently broken today**: any `extern import` of a class with primitive-returning methods (e.g. `java.util.ArrayList.size(): int`) currently generates stubs that `NoSuchMethodError` at runtime. This is one of the highest-probability silent failures in the feature, because `extern import` was designed to make binding easy — but it makes it easy to generate broken bindings for the most common Java patterns. Fixing the auto-generation in this story is therefore as important as fixing the manual `extern fun` path.
- **`short`/`byte` parameter unboxing**: `emitExternArgFromLocal` for descriptors `S` and `B` attempts `CHECKCAST java/lang/Short` / `java/lang/Byte` but arrives a `java.lang.Long` from the Kestrel caller. Fix: unbox via `longValue()` then narrow-cast. A safer alternative is to emit a KRuntime helper method. Explore both and document the chosen approach.
- **`char` parameters**: descriptor `C` currently does `CHECKCAST java/lang/Integer` + `intValue()`. Kestrel `Char` is stored as `java.lang.Integer` (Rune/Int), so this is correct for `Char` parameters. However `Int` (stored as `Long`) passing to a `char` parameter is a type-system error that cannot occur if typecheck is working correctly — document this assumption.
