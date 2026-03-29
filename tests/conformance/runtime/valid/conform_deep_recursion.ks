fun down(n: Int): Int = if (n <= 0) 0 else 1 + down(n - 1)

println(down(200))
// 200
