import * as Fs from "kestrel:fs"
import * as Lst from "kestrel:list"
import * as Str from "kestrel:string"
import { NotFound } from "kestrel:fs"

fun entryContains(entries: List<String>, needle: String): Bool =
  Lst.any(entries, (entry: String) => Str.contains(needle, entry))

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
        val a = if (entryContains(entries, "a.txt\tfile")) 1 else 0;
        val b = if (entryContains(entries, "b.txt\tfile")) 1 else 0;
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