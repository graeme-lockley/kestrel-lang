// Runtime conformance: async + await execute through JVM Task plumbing (spec 08 §2.3).
import * as Fs from "kestrel:fs"
import * as Str from "kestrel:string"
import { NotFound } from "kestrel:fs"

export exception Boom

async fun double(n: Int): Task<Int> = n * 2
async fun fail(): Task<Int> = throw Boom

async fun run(): Task<Unit> = {
	val x = await double(21);
	println(x);
	val caught = try { await fail() } catch { Boom => 7 };
	println(caught);
	val leftTask = Fs.readText("tests/fixtures/fs/read_fixture.txt");
	val rightTask = Fs.readText("tests/fixtures/fs/read_fixture_two.txt");
	val leftLen =
		match (await leftTask) {
			Ok(v) => Str.length(v),
			Err(_) => 0
		};
	val rightLen =
		match (await rightTask) {
			Ok(v) => Str.length(v),
			Err(_) => 0
		};
	println(leftLen + rightLen);
	val missingFlag =
		match (await Fs.readText("tests/fixtures/fs/__missing__.no_such")) {
			Err(NotFound) => 1,
			_ => 0
		};
	println(missingFlag);
	()
}

run()
// 42
// 7
// 28
// 1
