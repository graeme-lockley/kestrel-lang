import * as Fs from "kestrel:fs"
import { NotFound } from "kestrel:fs"
import * as Str from "kestrel:string"

async fun run(): Task<Unit> = {
  val path = "tests/fixtures/fs/tmp_e2e_write.txt";

  // Success path: write then read back
  val writeResult = await Fs.writeText(path, "e2e-ok\n");
  val writeOk =
    match (writeResult) {
      Ok(_) => "write-ok",
      Err(_) => "write-err"
    };
  println(writeOk);

  val readBack =
    match (await Fs.readText(path)) {
      Ok(v) => Str.trim(v),
      Err(_) => "read-err"
    };
  println(readBack);

  // Failure path: missing parent directory
  val badPath = "tests/fixtures/fs/__no_parent__/out.txt";
  val failResult =
    match (await Fs.writeText(badPath, "x")) {
      Err(NotFound) => "write-not-found",
      _ => "unexpected"
    };
  println(failResult);

  ()
}

run()
