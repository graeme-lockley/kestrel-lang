// Self-hosted runtime conformance: async lambdas execute and preserve capture.
async fun run(): Task<Unit> = {
  val offset = 1;
  val inc = async (x: Int) => x + offset;
  val id = async (x: Int) => x;
  println(await inc(42));
  println(await id(7));
  ()
}

run()
// => 43
// => 7
