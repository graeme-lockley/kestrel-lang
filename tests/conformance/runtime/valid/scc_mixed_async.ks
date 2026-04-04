// Runtime conformance: mixed SCC — sync members trampolined, async member uses payload/wrapper.

fun isEven(n: Int): Bool =
  if (n == 0) True
  else isOdd(n - 1)

fun isOdd(n: Int): Bool =
  if (n == 0) False
  else isEven(n - 1)

async fun asyncCheck(n: Int): Task<Bool> = isEven(n)

async fun run(): Task<Unit> = {
  val result = await asyncCheck(100000);
  println(result)
}

run()
// True
