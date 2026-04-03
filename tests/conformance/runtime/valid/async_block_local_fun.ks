// Runtime conformance: block-local async fun compiles and executes correctly.

async fun run(): Task<Unit> = {
  async fun double(n: Int): Task<Int> = n * 2
  val x = await double(21)
  println(x)

  async fun triple(n: Int): Task<Int> = {
    val d = await double(n)
    d + n
  }
  val y = await triple(10)
  println(y)

  val factor = 5
  async fun multiply(n: Int): Task<Int> = n * factor
  val z = await multiply(6)
  println(z)
}

run()
// 42
// 30
// 30
