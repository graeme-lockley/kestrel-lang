// Runtime conformance: listDir returns DirEntry ADT values
import * as Fs from "kestrel:io/fs"
import * as Lst from "kestrel:data/list"
import { File, Dir, DirEntry } from "kestrel:io/fs"

async fun run(): Task<Unit> = {
  match (await Fs.listDir("tests/fixtures/fs/list_sample")) {
    Ok(entries) => {
      val fileCount = Lst.length(Lst.filter(entries, (e: DirEntry) => match (e) { File(_) => True, Dir(_) => False }));
      val dirCount = Lst.length(Lst.filter(entries, (e: DirEntry) => match (e) { File(_) => False, Dir(_) => True }));
      println(fileCount);
      println(dirCount);
      ()
    },
    Err(_) => {
      println("error");
      ()
    }
  }
}

run()
// 2
// 0
