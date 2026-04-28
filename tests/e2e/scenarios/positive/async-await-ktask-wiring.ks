import * as Fs from "kestrel:io/fs"
import * as Str from "kestrel:data/string"

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
