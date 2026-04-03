import * as Fs from "kestrel:fs"
import { NotFound } from "kestrel:fs"
import * as Str from "kestrel:string"

async fun run(): Task<Unit> = {
  val ok =
    match (await Fs.readText("tests/fixtures/fs/read_fixture.txt")) {
      Ok(v) => v,
      Err(_) => ""
    };
  println(if (Str.length(ok) == 14) "ok" else "bad");
  val missing =
    match (await Fs.readText("tests/fixtures/fs/__missing__.no_such")) {
      Err(NotFound) => 1,
      _ => 0
    };
  println(missing);
  ()
}

run()