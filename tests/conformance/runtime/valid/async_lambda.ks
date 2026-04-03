// Runtime conformance: async lambdas return Task values and preserve captures.
async fun run(): Task<Unit> = {
	val offset = 1;
	val inc = async (x: Int) => x + offset;
	val id = async <T>(x: T) => x;
	println(await inc(42));
	println(await id(7));
	()
}

run()
// 43
// 7