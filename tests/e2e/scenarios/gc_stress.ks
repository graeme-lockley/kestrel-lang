// GC stress test - allocate many lists to trigger garbage collection
fun makeList(n: Int): List<Int> = if (n <= 0) [] else n :: makeList(n - 1)

// Create multiple large lists that will be garbage collected
val list1 = makeList(50)
val list2 = makeList(50)
val list3 = makeList(50)

// Only the final one is kept, others should be GC'd
val final = makeList(5)
