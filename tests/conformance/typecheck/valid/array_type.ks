// Typecheck conformance: Array<T> type annotation and opaque type round-trip.
extern type JArrayList = jvm("java.util.ArrayList")

extern fun jarrNew(): JArrayList =
  jvm("kestrel.runtime.KRuntime#arrayListNew()")

extern fun jarrGet<T>(arr: JArrayList, index: Int): T =
  jvm("kestrel.runtime.KRuntime#arrayListGet(java.lang.Object,java.lang.Object)")

extern fun jarrPush<T>(arr: JArrayList, value: T): Unit =
  jvm("kestrel.runtime.KRuntime#arrayListAdd(java.lang.Object,java.lang.Object)")

extern fun jarrLength(arr: JArrayList): Int =
  jvm("kestrel.runtime.KRuntime#arrayListSize(java.lang.Object)")

opaque type Array<T> = JArrayList

fun makeIntArray(): Array<Int> = {
  val a: Array<Int> = jarrNew()
  jarrPush(a, 1)
  jarrPush(a, 2)
  a
}

fun getFirst(a: Array<Int>): Int = jarrGet(a, 0)
