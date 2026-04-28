import * as Fs from "kestrel:io/fs"
import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import { NotFound, DirEntry, File, Dir } from "kestrel:io/fs"

fun hasFile(entries: List<DirEntry>, name: String): Bool =
  Lst.any(entries, (e: DirEntry) => match (e) {
    File(p) => Str.contains(name, p),
    Dir(_) => False
  })

async fun run(): Task<Unit> = {
  val listed = await Fs.listDir("tests/fixtures/fs/list_sample");
  val count =
    match (listed) {
      Ok(entries) => Lst.length(entries),
      Err(_) => 0
    };
  val matched =
    match (listed) {
      Ok(entries) => {
        val a = if (hasFile(entries, "a.txt")) 1 else 0;
        val b = if (hasFile(entries, "b.txt")) 1 else 0;
        a + b
      }
      Err(_) => 0
    };
  val missing =
    match (await Fs.listDir("tests/fixtures/fs/__nope_dir_missing__")) {
      Err(NotFound) => "missing",
      _ => "bad"
    };
  println(count);
  println(matched);
  println(missing);
  ()
}

run()