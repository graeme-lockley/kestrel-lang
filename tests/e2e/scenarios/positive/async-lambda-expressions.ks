async fun run(): Task<Unit> = {
  val offset = 1
  val inc = async (x: Int) => x + offset
  val id = async <T>(x: T) => x
  println(await inc(42));
  println(await id(7));
  ()
}

run()