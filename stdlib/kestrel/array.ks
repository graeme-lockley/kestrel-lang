// kestrel:array — mutable, O(1)-indexed sequence backed by java.util.ArrayList.
// Array<T> is mutable in place: set and push operate on the same object.
// Use fromList / toList to convert between Array<T> and the immutable List<T>.

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

export fun new<T>(): Array<T> = jarrNew()

export fun get<T>(arr: Array<T>, index: Int): T = jarrGet(arr, index)

export fun set<T>(arr: Array<T>, index: Int, value: T): Unit = jarrSet(arr, index, value)

export fun push<T>(arr: Array<T>, value: T): Unit = jarrPush(arr, value)

export fun length<T>(arr: Array<T>): Int = jarrLength(arr)

export fun fromList<T>(list: List<T>): Array<T> = jarrFromList(list)

export fun toList<T>(arr: Array<T>): List<T> = jarrToList(arr)
