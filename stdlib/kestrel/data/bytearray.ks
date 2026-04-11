//! Mutable, O(1)-indexed byte sequences backed by a primitive JVM `byte[]`.
//!
//! `ByteArray` is the right choice when you need efficient binary I/O or
//! byte-level manipulation. Elements are unsigned bytes stored as `Int` values
//! in the range 0–255.
//!
//! For generic mutable sequences of arbitrary element types see
//! `kestrel:data/array`.  For high-level file I/O see `kestrel:io/fs`.

extern type JByteArray = jvm("java.lang.Object")

extern fun jbaNew(size: Int): JByteArray =
  jvm("kestrel.runtime.KRuntime#byteArrayNew(java.lang.Object)")
extern fun jbaLength(arr: JByteArray): Int =
  jvm("kestrel.runtime.KRuntime#byteArrayLength(java.lang.Object)")
extern fun jbaGet(arr: JByteArray, index: Int): Int =
  jvm("kestrel.runtime.KRuntime#byteArrayGet(java.lang.Object,java.lang.Object)")
extern fun jbaSet(arr: JByteArray, index: Int, value: Int): Unit =
  jvm("kestrel.runtime.KRuntime#byteArraySet(java.lang.Object,java.lang.Object,java.lang.Object)")
extern fun jbaFromList(xs: List<Int>): JByteArray =
  jvm("kestrel.runtime.KRuntime#byteArrayFromList(java.lang.Object)")
extern fun jbaToList(arr: JByteArray): List<Int> =
  jvm("kestrel.runtime.KRuntime#byteArrayToList(java.lang.Object)")
extern fun jbaConcat(a: JByteArray, b: JByteArray): JByteArray =
  jvm("kestrel.runtime.KRuntime#byteArrayConcat(java.lang.Object,java.lang.Object)")
extern fun jbaSlice(arr: JByteArray, start: Int, end: Int): JByteArray =
  jvm("kestrel.runtime.KRuntime#byteArraySlice(java.lang.Object,java.lang.Object,java.lang.Object)")

/// An opaque, mutable sequence of bytes backed by a primitive JVM `byte[]`.
opaque type ByteArray = JByteArray

/// Create a new `ByteArray` of the given `size`, zero-initialised.
export fun new(size: Int): ByteArray = jbaNew(size)

/// Return the number of bytes in `bytes`.
export fun length(bytes: ByteArray): Int = jbaLength(bytes)

/// Return the byte at `index` as an `Int` in the range 0–255.
export fun get(bytes: ByteArray, index: Int): Int = jbaGet(bytes, index)

/// Overwrite the byte at `index` with `value` (0–255) in place.
export fun set(bytes: ByteArray, index: Int, value: Int): Unit = jbaSet(bytes, index, value)

/// Build a `ByteArray` from a list of `Int` values (each 0–255).
export fun fromList(xs: List<Int>): ByteArray = jbaFromList(xs)

/// Convert `bytes` to an immutable list of `Int` values (each 0–255).
export fun toList(bytes: ByteArray): List<Int> = jbaToList(bytes)

/// Return a new `ByteArray` containing all bytes of `a` followed by all bytes of `b`.
export fun concat(a: ByteArray, b: ByteArray): ByteArray = jbaConcat(a, b)

/// Return a new `ByteArray` containing bytes in the half-open range `[start, end)`.
export fun slice(bytes: ByteArray, start: Int, end: Int): ByteArray = jbaSlice(bytes, start, end)
