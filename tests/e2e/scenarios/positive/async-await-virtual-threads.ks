// E2E_SKIP_PENDING_CODEGEN: self-hosted codegen does not yet emit $init/main; re-enable in S17-37/S17-42
export exception Boom

async fun value(n: Int): Task<Int> = n + 1
async fun fail(): Task<Int> = throw Boom

async fun run(): Task<Unit> = {
  val x = await value(41);
  println(x);
  val caught = try { await fail() } catch { Boom => 7 };
  println(caught);
  ()
}

run()