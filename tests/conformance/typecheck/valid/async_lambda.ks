// Async lambda typing, generics, and higher-order use
fun use(f: Int -> Task<Int>, x: Int): Task<Int> = f(x)

val inc = async (x: Int) => x + 1
val id = async <T>(x: T) => x

async fun run(): Task<Int> = {
  val a = await use(inc, 41)
  val b = await id(1)
  a + b
}