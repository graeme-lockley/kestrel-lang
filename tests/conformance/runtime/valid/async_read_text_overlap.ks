import * as Fs from "kestrel:io/fs"
import * as Str from "kestrel:data/string"

async fun run(): Task<Unit> = {
	val leftTask = Fs.readText("tests/fixtures/fs/read_fixture.txt");
	val rightTask = Fs.readText("tests/fixtures/fs/read_fixture_two.txt");
	val left =
		match (await leftTask) {
			Ok(v) => v,
			Err(_) => ""
		};
	val right =
		match (await rightTask) {
			Ok(v) => v,
			Err(_) => ""
		};
	println(Str.length(left));
	println(Str.length(right));
	()
}

run()
// 14
// 14