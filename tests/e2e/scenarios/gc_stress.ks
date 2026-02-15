// GC stress test - allocate many objects to trigger garbage collection
fun makeList(n: Int): List<Int> = if (n <= 0) [] else n :: makeList(n - 1)

fun sumList(xs: List<Int>): Int = match (xs) {
  [] => 0
  h :: t => h + sumList(t)
}

// Create multiple lists that will be garbage collected
// Using smaller sizes due to current recursion depth limitations
val list1 = makeList(20)
val sum1 = sumList(list1)
print(sum1)

val list2 = makeList(15)
val sum2 = sumList(list2)
print(sum2)

val list3 = makeList(10)
val sum3 = sumList(list3)
print(sum3)

// Create many small allocations
val small1 = makeList(5)
val small2 = makeList(5)
val small3 = makeList(5)
val small4 = makeList(5)

val finalSum = sumList(small1) + sumList(small2) + sumList(small3) + sumList(small4)
print(finalSum)
