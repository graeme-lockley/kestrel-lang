import * as Fs from "kestrel:io/fs"

async fun run(): Task<Unit> = {
  val text: String = await Fs.readText("tests/fixtures/fs/read_fixture.txt");
  println(text);
  ()
}

run()
