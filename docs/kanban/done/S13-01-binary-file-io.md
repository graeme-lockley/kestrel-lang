# Binary file I/O (`readBytes`/`writeBytes`/`appendBytes`)

## Sequence: S13-01
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E13 Stdlib Compiler Readiness](../epics/unplanned/E13-stdlib-compiler-readiness.md)

## Summary

Add a `ByteArray` opaque type and three binary-I/O operations (`readBytes`, `writeBytes`, `appendBytes`) to `kestrel:io/fs`. These are the foundational primitive enabling the Kestrel compiler to emit JVM `.class` files, which are binary. Without this, the codegen output path cannot be implemented.

## Current State

`stdlib/kestrel/io/fs.ks` provides only text-based I/O: `readText`, `writeText`. There is no binary read/write, and no `ByteArray` type in the stdlib or language. KRuntime.java has no byte-array read/write methods. The `data/array` module provides a mutable `Array<T>` backed by `ArrayList`, but it is not typed as `byte[]` and cannot be passed to binary file-write operations efficiently.

## Goals

1. Introduce a `ByteArray` opaque type in `kestrel:io/fs` backed by Java `byte[]`.
2. Export `readBytes(path: String): Task<Result<ByteArray, FsError>>` — reads the entire file as raw bytes.
3. Export `writeBytes(path: String, bytes: ByteArray): Task<Result<Unit, FsError>>` — writes a `ByteArray` to a file, creating or overwriting it.
4. Export `appendBytes(path: String, bytes: ByteArray): Task<Result<Unit, FsError>>` — appends a `ByteArray` to a file.
5. Export `byteArrayLength(bytes: ByteArray): Int` — length of byte array.
6. Export `byteArrayGet(bytes: ByteArray, index: Int): Int` — get byte (0–255) at index.
7. Export `byteArraySet(bytes: ByteArray, index: Int, value: Int): Unit` — set byte in-place.
8. Export `byteArrayNew(size: Int): ByteArray` — create zeroed byte array of given size.
9. Export `byteArrayFromList(xs: List<Int>): ByteArray` — create `ByteArray` from list of ints (0–255 each).
10. Export `byteArrayToList(bytes: ByteArray): List<Int>` — convert `ByteArray` to list of ints.

## Acceptance Criteria

- A JVM `.class` file can be read via `readBytes`, then written byte-for-byte via `writeBytes`, and the result is binary-identical to the original.
- `byteArrayGet`/`byteArraySet` give access to individual bytes (0–255).
- `byteArrayNew(n)` creates a zeroed array of length n.
- All operations return appropriate `FsError` values on failure (not-found, permission-denied, etc.).
- Unit tests exercise round-trip read/write and get/set.

## Spec References

- `docs/specs/02-stdlib.md` (io/fs section)

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime | Add `byteArrayNew`, `byteArrayGet`, `byteArraySet`, `byteArrayLength`, `byteArrayFromList`, `byteArrayToList`, `readBytesAsync`, `writeBytesAsync`, `appendBytesAsync` to `KRuntime.java` |
| Stdlib | Add `ByteArray` opaque type + 9 helper fns + `readBytes`/`writeBytes`/`appendBytes` to `stdlib/kestrel/io/fs.ks` |
| Tests | New conformance runtime test `tests/conformance/runtime/valid/fs_bytes.ks` |
| Docs | Add `ByteArray` type and all byte I/O functions to `docs/specs/02-stdlib.md` io/fs section |

## Tasks

- [x] `runtime/jvm/src/kestrel/runtime/KRuntime.java`: add `byteArrayNew`, `byteArrayGet`, `byteArraySet`, `byteArrayLength`, `byteArrayFromList`, `byteArrayToList`
- [x] `runtime/jvm/src/kestrel/runtime/KRuntime.java`: add `readBytesAsync`, `writeBytesAsync`, `appendBytesAsync`
- [x] `stdlib/kestrel/io/fs.ks`: add `extern type JByteArray`, extern bindings, `opaque type ByteArray`, and export all functions
- [x] `tests/conformance/runtime/valid/fs_bytes.ks`: test round-trip readBytes/writeBytes, get/set, fromList/toList
- [x] `cd runtime/jvm && bash build.sh`
- [x] `cd compiler && npm run build && npm test`
- [x] `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance runtime | `tests/conformance/runtime/valid/fs_bytes.ks` | `byteArrayNew`, `byteArrayGet`/`Set`, `fromList`/`toList`, round-trip `readBytes`/`writeBytes` |

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md` — add `ByteArray` opaque type and all byte I/O functions to io/fs section

## Build notes

**2025:** Implemented `ByteArray` as `extern type JByteArray = jvm("java.lang.Object")` — **not** `jvm("byte[]")`. The JVM descriptor for `byte[]` is `[B`; wrapping it in `L[B;` is not valid. Using `java.lang.Object` as the declared type works because `byte[]` IS-A `java.lang.Object` at runtime, and all KRuntime methods that accept or return `byte[]` are declared with `Object` return/param types so the generated `invokestatic` descriptors match.

**Key lesson:** `byte[]` return type in Java methods causes `NoSuchMethodError` at runtime. The generated code uses `Ljava/lang/Object;` as the descriptor for any `JByteArray` return, so the Java method must also declare `Object` (not `byte[]`) as its return type. Fixed by changing `byteArrayNew`, `byteArrayFromList`, `byteArrayConcat`, `byteArraySlice` to return `Object` (which is assignment-compatible with `byte[]` in Java).

**Key lesson:** `()` as a trailing expression in a block does NOT work unless the preceding expression ends with a semicolon. Without semicolons, the parser reads `expr\n()` as `expr()` (function application). Use a `println` call as the trailing expression, or add a `;` after the last statement if needed.

## Risks / Notes

- `ByteArray` must be an opaque type to prevent direct Java `byte[]` exposure to Kestrel code. Use the same opaque-type pattern as `Array<T>`.
- Byte values in Kestrel are `Int` (0–255); the JVM stores them as signed bytes (-128 to 127); mask with `& 0xFF` when converting.
- S13-05 (crypto) and S13-14 (atomic write) depend on this story.
