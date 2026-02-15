// Runtime conformance: GC stress (spec 08 §2.5). Many short-lived allocations; no leaks.
fun makeList(n: Int): List<Int> = if (n <= 0) [] else n :: makeList(n - 1)

fun sumList(xs: List<Int>): Int = match (xs) {
  [] => 0
  h :: t => h + sumList(t)
}

val list1 = makeList(20)
val sum1 = sumList(list1)
println(sum1)
// 210
val list2 = makeList(15)
val sum2 = sumList(list2)
println(sum2)
// 120
val finalSum = sumList(makeList(5)) + sumList(makeList(5))
println(finalSum)
// 30
