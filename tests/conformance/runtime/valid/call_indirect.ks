fun apply(f: (Int) -> Int, x: Int): Int = f(x)
fun double(n: Int): Int = n * 2

println(apply(double, 5))
// 10
println(apply((x: Int) => x + 1, 9))
// 10
