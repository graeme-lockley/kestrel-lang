// Runtime conformance: arrayNew, arrayPush, arrayLength, arrayGet, arraySet
import { arrayNew, arrayPush, arrayLength, arrayGet, arraySet } from "kestrel:array"

val arr = arrayNew(4)
println(arrayLength(arr))
// 0
arrayPush(arr, 10)
arrayPush(arr, 20)
arrayPush(arr, 30)
println(arrayLength(arr))
// 3
println(arrayGet(arr, 0))
// 10
println(arrayGet(arr, 1))
// 20
println(arrayGet(arr, 2))
// 30
arraySet(arr, 1, 99)
println(arrayGet(arr, 1))
// 99
