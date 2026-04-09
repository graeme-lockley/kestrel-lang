// Runtime conformance: basic Array<T> create/push/get/length at runtime.
import { new as newArr, push, get, length, set, fromList, toList } from "kestrel:data/array"

val a = newArr()
push(a, 10)
push(a, 20)
push(a, 30)
println(length(a))
// 3
println(get(a, 0))
// 10
println(get(a, 2))
// 30
set(a, 1, 99)
println(get(a, 1))
// 99
val xs = toList(fromList([5, 6, 7]))
println(xs)
// [5, 6, 7]
