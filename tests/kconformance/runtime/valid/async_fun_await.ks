// Self-hosted runtime conformance: async function declaration and await expression.
// Verifies that async fun emits the payload method + KTask wrapper, and that
// await unwraps the Task result via KTask.get().

async fun double(n: Int): Task<Int> = n * 2

async fun run(): Task<Unit> = {
  val x = await double(21);
  println(x);
  ()
}

run()
// => 42
