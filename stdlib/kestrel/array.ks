// kestrel:array — mutable Array<T> operations backed by KArray JVM runtime.

/** Create an empty array with the given initial capacity. */
export extern fun arrayNew<V>(capacity: Int): Array<V> =
  jvm("kestrel.runtime.KRuntime#arrayNew(java.lang.Object)")

/** Convert a List<T> to an Array<T>. */
export extern fun arrayFrom<V>(list: List<V>): Array<V> =
  jvm("kestrel.runtime.KRuntime#arrayFrom(java.lang.Object)")

/** Return the element at index (0-based). Throws on out-of-bounds. */
export extern fun arrayGet<V>(arr: Array<V>, index: Int): V =
  jvm("kestrel.runtime.KRuntime#arrayGet(java.lang.Object,java.lang.Object)")

/** Overwrite the element at index. Throws on out-of-bounds. Returns (). */
export extern fun arraySet<V>(arr: Array<V>, index: Int, value: V): Unit =
  jvm("kestrel.runtime.KRuntime#arraySet(java.lang.Object,java.lang.Object,java.lang.Object):void")

/** Return the number of elements in the array. */
export extern fun arrayLength<V>(arr: Array<V>): Int =
  jvm("kestrel.runtime.KRuntime#arrayLength(java.lang.Object)")

/** Append an element to the end of the array, growing storage if needed. Returns (). */
export extern fun arrayPush<V>(arr: Array<V>, value: V): Unit =
  jvm("kestrel.runtime.KRuntime#arrayPush(java.lang.Object,java.lang.Object):void")
