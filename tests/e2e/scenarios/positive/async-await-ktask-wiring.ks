import * as Fs from "kestrel:fs"
import * as Str from "kestrel:string"

async fun run(): Task<Unit> = {
  val t = await Fs.readText("tests/fixtures/fs/read_fixture.txt");
  println(Str.length(t));
  ()
}

run()
