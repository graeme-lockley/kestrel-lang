// Fibonacci sequence using recursion
fun fib(n: Int): Int = if (n <= 1) n else fib(n - 1) + fib(n - 2)

val f0 = fib(0)
val f1 = fib(1)
val f5 = fib(5)
val f10 = fib(10)

print(f0)
print(f1)
print(f5)
print(f10)
