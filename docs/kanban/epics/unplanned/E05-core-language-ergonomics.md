# Epic E05: Core Language Ergonomics

## Status

Unplanned

## Summary

Improves day-to-day language ergonomics with explicit discard semantics and a built-in mutable array type.

## Stories

- [S05-01-array-builtin-type.md](../../unplanned/S05-01-array-builtin-type.md)
- [S05-02-ignore-keyword-for-discarding-values.md](../../unplanned/S05-02-ignore-keyword-for-discarding-values.md)

## Dependencies

- E02 (JVM Interop — extern Bindings and Intrinsic Migration) must be complete. S05-01 relies entirely on `extern type`/`extern fun` machinery and `KRuntime` static helpers established in E02.
- No ordering dependency between S05-01 and S05-02.

## Design Context

### Array<T> — ArrayList strategy (informed by E02)

E02 established `extern type` + `extern fun` + `KRuntime` static helpers as the standard pattern for binding JVM collections. `kestrel:dict` over `java.util.HashMap` is the reference implementation. `Array<T>` follows the same pattern using `java.util.ArrayList`:

- `extern type JArrayList = jvm("java.util.ArrayList")` — opaque internal handle.
- `KRuntime` static helpers (`arrayListNew`, `arrayListGet`, `arrayListSet`, `arrayListAdd`, `arrayListSize`, `arrayListFromList`, `arrayListToList`) wrap the boxed Long→int index conversion and void-discarding for `set`/`add` return values.
- `opaque type Array<T> = JArrayList` hides the JVM type from callers.
- **No new JVM instructions or custom heap-object kinds are required.** The existing `extern fun` codegen path handles everything.
- `Array<T>` is **mutable in place** (`set`, `push` mutate the same object). This is unlike `Dict` which copies on write; arrays are expected to be used in mutable contexts.

### `ignore` — required discard (not optional sugar)

A bare non-`Unit` expression in statement position is a **compile error**. `ignore expr` is the required form to explicitly discard a non-Unit result. This is a stronger rule than "optional warning":

- Type checker rejects any expression-as-statement whose type ≠ `Unit` unless wrapped in `ignore`.
- `ignore` applied to a `Unit` expression is also an error (unnecessary noise).
- The last expression in a block is the block's return value and is exempt from this rule.
- This rule applies uniformly: function bodies, inner blocks, top-level expressions.
- Impact on existing code: the stdlib already avoids this problem by wrapping JVM calls with `void`-returning `KRuntime` helpers. Any residual violations must be fixed before S05-02 closes.

## Epic Completion Criteria

- `stdlib/kestrel/array.ks` implemented and tested via `array.test.ks`.
- `ignore` keyword implemented end-to-end: lexer, parser, typechecker (hard error for bare non-Unit), codegen (pop instruction).
- Bare non-Unit expression-as-statement is a compile error with a clear diagnostic.
- All conformance and unit tests pass.
- `docs/specs/01-language.md`, `docs/specs/02-stdlib.md`, and `docs/specs/10-compile-diagnostics.md` updated.
