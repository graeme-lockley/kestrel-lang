// E2E_SKIP_PENDING_CODEGEN: self-hosted codegen does not yet emit $init/main; re-enable in S17-37/S17-42
async fun run(): Task<Unit> = {
  val offset = 1
  val inc = async (x: Int) => x + offset
  val id = async <T>(x: T) => x
  println(await inc(42));
  println(await id(7));
  ()
}

run()