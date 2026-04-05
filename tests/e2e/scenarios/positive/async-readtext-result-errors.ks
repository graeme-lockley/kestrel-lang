import * as Fs from "kestrel:io/fs"
import { NotFound, PermissionDenied, IoError } from "kestrel:io/fs"
import * as Str from "kestrel:data/string"

async fun run(): Task<Unit> = {
  val okLine =
    match (await Fs.readText("tests/fixtures/fs/read_fixture.txt")) {
      Ok(v) => if (Str.length(v) == 14) "ok" else "bad"
      Err(_) => "bad"
    };
  println(okLine);

  val missingLine =
    match (await Fs.readText("tests/fixtures/fs/__missing__.no_such")) {
      Err(NotFound) => "missing"
      Err(PermissionDenied) => "denied"
      Err(IoError(_)) => "io"
      Ok(_) => "bad"
    };
  println(missingLine);
  ()
}

run()
