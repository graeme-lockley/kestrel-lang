import * as Fs from "kestrel:fs"
import * as Str from "kestrel:string"

async fun run(): Task<Unit> = {
  val t =
    match (await Fs.readText("tests/fixtures/fs/read_fixture.txt")) {
      Ok(v) => v,
      Err(_) => ""
    };
  println(Str.length(t));
  ()
}

run()
