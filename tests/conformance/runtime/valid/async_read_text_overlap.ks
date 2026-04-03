import * as Fs from "kestrel:fs"
import * as Str from "kestrel:string"

async fun run(): Task<Unit> = {
	val leftTask = Fs.readText("tests/fixtures/fs/read_fixture.txt");
	val rightTask = Fs.readText("tests/fixtures/fs/read_fixture_two.txt");
	val left = await leftTask;
	val right = await rightTask;
	println(Str.length(left));
	println(Str.length(right));
	()
}

run()
// 14
// 14