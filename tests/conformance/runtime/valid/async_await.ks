// Runtime conformance: async + await execute through JVM Task plumbing (spec 08 §2.3).
export exception Boom

async fun double(n: Int): Task<Int> = n * 2
async fun fail(): Task<Int> = throw Boom

async fun run(): Task<Unit> = {
	val x = await double(21);
	println(x);
	val caught = try { await fail() } catch { Boom => 7 };
	println(caught);
	()
}

run()
// 42
// 7
