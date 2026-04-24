//! Mutable, O(1)-indexed sequences backed by `java.util.ArrayList`.
//!
//! `Array<T>` provides constant-time random access and in-place mutation — the right
//! choice when you need to build a collection incrementally, fill slots at known
//! indices, or avoid the allocation overhead of recursive list construction.
//! For functional, immutable sequences use [`kestrel:data/list`](/docs/kestrel:data/list) instead.
//!
//! All mutating operations (`set`, `push`) act on the same underlying object in
//! place. Copying is explicit: `fromList(toList(arr))`.
//! Convert freely between `Array<T>` and `List<T>` using `fromList` and `toList`.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as Arr from "kestrel:data/array"
//!
//! val xs = Arr.fromList([10, 20, 30])
//! Arr.set(xs, 1, 99)
//! Arr.push(xs, 42)
//! val n = Arr.length(xs)      // 4
//! val first = Arr.get(xs, 0)  // 10
//! val asList = Arr.toList(xs) // [10, 99, 30, 42]
//! ```
//!

import * as List from "kestrel:data/list"

extern type JArrayList = jvm("java.util.ArrayList")

extern fun jarrNew(): JArrayList =
  jvm("kestrel.runtime.KRuntime#arrayListNew()")

extern fun jarrCopy(arr: JArrayList): JArrayList =
  jvm("kestrel.runtime.KRuntime#arrayListCopy(java.lang.Object)")

extern fun jarrGet<T>(arr: JArrayList, index: Int): T =
  jvm("kestrel.runtime.KRuntime#arrayListGet(java.lang.Object,java.lang.Object)")

extern fun jarrSet<T>(arr: JArrayList, index: Int, value: T): Unit =
  jvm("kestrel.runtime.KRuntime#arrayListSet(java.lang.Object,java.lang.Object,java.lang.Object)")

extern fun jarrPush<T>(arr: JArrayList, value: T): Unit =
  jvm("kestrel.runtime.KRuntime#arrayListAdd(java.lang.Object,java.lang.Object)")

extern fun jarrLength(arr: JArrayList): Int =
  jvm("kestrel.runtime.KRuntime#arrayListSize(java.lang.Object)")

extern fun jarrFromList<T>(list: List<T>): JArrayList =
  jvm("kestrel.runtime.KRuntime#arrayListFromList(java.lang.Object)")

extern fun jarrToList<T>(arr: JArrayList): List<T> =
  jvm("kestrel.runtime.KRuntime#arrayListToList(java.lang.Object)")

opaque type Array<T> = JArrayList

/// Create a new empty `Array<T>`.
export fun new<T>(): Array<T> = jarrNew()

/// Return the element at `index`. Throws `IndexOutOfBoundsException` if out of range.
export fun get<T>(arr: Array<T>, index: Int): T = jarrGet(arr, index)

/// Overwrite the element at `index` in place. Throws if `index` is out of range.
export fun set<T>(arr: Array<T>, index: Int, value: T): Unit = jarrSet(arr, index, value)

/// Append `value` to the end of `arr`, growing its length by one.
export fun push<T>(arr: Array<T>, value: T): Unit = jarrPush(arr, value)

/// Number of elements currently in `arr`.
export fun length<T>(arr: Array<T>): Int = jarrLength(arr)

/// Build a new `Array<T>` from an immutable list (O(n)).
export fun fromList<T>(list: List<T>): Array<T> = jarrFromList(list)

/// Convert `arr` to an immutable list (O(n)). The array is not modified.
export fun toList<T>(arr: Array<T>): List<T> = jarrToList(arr)
