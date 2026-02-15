// Fibonacci sequence using recursion
fun fib(n: Int): Int = if (n <= 1) n else fib(n - 1) + fib(n - 2)

val f0 = fib(0)
val f1 = fib(1)
val f5 = fib(5)
val f10 = fib(10)

println(f0)
// 0
println(f1)
// 1
println(f5)
// 5
println(f10)
// 55
