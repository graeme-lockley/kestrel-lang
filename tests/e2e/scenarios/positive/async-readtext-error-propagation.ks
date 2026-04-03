import * as Fs from "kestrel:fs"
import * as Str from "kestrel:string"

async fun run(): Task<Unit> = {
  val ok = await Fs.readText("tests/fixtures/fs/read_fixture.txt");
  println(if (Str.length(ok) == 14) "ok" else "bad");
  val caught = try {
    await Fs.readText("tests/fixtures/fs/__missing__.no_such");
    0
  } catch {
    e => 1
  };
  println(caught);
  ()
}

run()