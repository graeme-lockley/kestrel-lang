import * as Fs from "kestrel:io/fs"
import * as Str from "kestrel:data/string"

async fun run(): Task<Unit> = {
  val leftTask = Fs.readText("tests/fixtures/fs/read_fixture.txt");
  val rightTask = Fs.readText("tests/fixtures/fs/read_fixture_two.txt");

  val left = await leftTask;
  val right = await rightTask;

  val leftLen =
    match (left) {
      Ok(v) => Str.length(v),
      Err(_) => 0
    };
  val rightLen =
    match (right) {
      Ok(v) => Str.length(v),
      Err(_) => 0
    };
  val totalLength = leftLen + rightLen;

  val leftOk =
    match (left) {
      Ok(_) => 1,
      Err(_) => 0
    };
  val rightOk =
    match (right) {
      Ok(_) => 1,
      Err(_) => 0
    };
  val okCount = leftOk + rightOk;

  println(totalLength);
  println(okCount);
  ()
}

run()
