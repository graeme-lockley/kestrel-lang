// Runtime conformance: async + await execute through JVM Task plumbing (spec 08 §2.3).
async fun double(n: Int): Task<Int> = n * 2

async fun run(): Task<Unit> = {
	val x = await double(21);
	println(x);
	()
}

run()
// 42
