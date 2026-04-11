// Runtime conformance: list spread elements ([...xs, a, ...ys]) must flatten correctly.

import * as Lst from "kestrel:data/list"

val a = [1, 2, 3]
val b = [5, 6]
val c = [0, ...a, 4, ...b, 7]
println(c)
// [0, 1, 2, 3, 4, 5, 6, 7]

val d = [...[], 1, 2]
println(d)
// [1, 2]

val e = [...a, ...b]
println(e)
// [1, 2, 3, 5, 6]

fun qsort(xs: List<Int>): List<Int> =
  match (xs) {
    [] => [],
    h :: t =>
      [...qsort(Lst.filter(t, (x) => x <= h)), h, ...qsort(Lst.filter(t, (x) => x > h))]
  }

println(qsort([3, 1, 4, 1, 5, 2]))
// [1, 1, 2, 3, 4, 5]
