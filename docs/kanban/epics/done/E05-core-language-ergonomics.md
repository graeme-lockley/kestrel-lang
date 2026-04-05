# Epic E05: Core Language Ergonomics

## Status

Done

## Summary

Improves day-to-day language ergonomics with a built-in mutable array type.

## Stories

- [x] [S05-01-array-builtin-type.md](../../done/S05-01-array-builtin-type.md)

## Dependencies

- E02 (JVM Interop — extern Bindings and Intrinsic Migration) must be complete. S05-01 relies entirely on `extern type`/`extern fun` machinery and `KRuntime` static helpers established in E02.
- E05 consists of a single story (S05-01).

## Design Context

### Array<T> — ArrayList strategy (informed by E02)

E02 established `extern type` + `extern fun` + `KRuntime` static helpers as the standard pattern for binding JVM collections. `kestrel:dict` over `java.util.HashMap` is the reference implementation. `Array<T>` follows the same pattern using `java.util.ArrayList`:

- `extern type JArrayList = jvm("java.util.ArrayList")` — opaque internal handle.
- `KRuntime` static helpers (`arrayListNew`, `arrayListGet`, `arrayListSet`, `arrayListAdd`, `arrayListSize`, `arrayListFromList`, `arrayListToList`) wrap the boxed Long→int index conversion and void-discarding for `set`/`add` return values.
- `opaque type Array<T> = JArrayList` hides the JVM type from callers.
- **No new JVM instructions or custom heap-object kinds are required.** The existing `extern fun` codegen path handles everything.
- `Array<T>` is **mutable in place** (`set`, `push` mutate the same object). This is unlike `Dict` which copies on write; arrays are expected to be used in mutable contexts.

## Epic Completion Criteria

- `stdlib/kestrel/array.ks` implemented and tested via `array.test.ks`.
- All conformance and unit tests pass.
- `docs/specs/01-language.md` and `docs/specs/02-stdlib.md` updated.
