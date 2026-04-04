// Runtime conformance: arrayFrom converts List<T> to Array<T>
import { arrayFrom, arrayLength, arrayGet } from "kestrel:array"

val arr = arrayFrom([10, 20, 30])
println(arrayLength(arr))
// 3
println(arrayGet(arr, 0))
// 10
println(arrayGet(arr, 1))
// 20
println(arrayGet(arr, 2))
// 30
