fun fact(n: Int): Int = if (n == 0) 1 else n * fact(n - 1)
val x = fact(5)
