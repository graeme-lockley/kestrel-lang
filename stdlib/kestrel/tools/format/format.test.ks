// Idempotency tests for kestrel:tools/format/formatter.
// For every .ks file in stdlib/kestrel/data/ we verify that
//   format(format(src)) == format(src)
// i.e. a second formatting pass never changes the output.

import { Suite, group, asyncGroup, eq, isTrue } from "kestrel:dev/test"
import * as Str from "kestrel:data/string"
import * as Lst from "kestrel:data/list"
import { readText } from "kestrel:io/fs"
import { getProcess } from "kestrel:sys/process"
import { all } from "kestrel:sys/task"
import { format } from "kestrel:tools/format/formatter"

// Paths of files to test, relative to the project root.
val dataFiles = [
  "stdlib/kestrel/data/array.ks",
  "stdlib/kestrel/data/basics.ks",
  "stdlib/kestrel/data/char.ks",
  "stdlib/kestrel/data/dict.ks",
  "stdlib/kestrel/data/int.ks",
  "stdlib/kestrel/data/json.ks",
  "stdlib/kestrel/data/list.ks",
  "stdlib/kestrel/data/option.ks",
  "stdlib/kestrel/data/result.ks",
  "stdlib/kestrel/data/set.ks",
  "stdlib/kestrel/data/string.ks",
  "stdlib/kestrel/data/tuple.ks"
]

async fun checkIdempotency(cwd: String, relPath: String): Task<(String, Bool, String)> = {
  val absPath = "${cwd}/${relPath}"
  val readResult = await readText(absPath)
  match (readResult) {
    Err(e) => (relPath, False, "could not read: ${e}")
    Ok(src) =>
      match (format(src)) {
        Err(e) => (relPath, False, "format pass 1 failed: ${e}")
        Ok(pass1) =>
          match (format(pass1)) {
            Err(e) => (relPath, False, "format pass 2 failed: ${e}")
            Ok(pass2) =>
              if (Str.equals(pass1, pass2))
                (relPath, True, "")
              else
                (relPath, False, "not idempotent — pass 1 and pass 2 differ")
          }
      }
  }
}

export async fun run(s: Suite): Task<Unit> = {
  await asyncGroup(s, "formatter", async (s1: Suite) => {
    await asyncGroup(s1, "idempotency over stdlib/kestrel/data", async (s2: Suite) => {
      val cwd = getProcess().cwd
      val checks = Lst.map(dataFiles, (p: String) => checkIdempotency(cwd, p))
      val results = await all(checks)
      Lst.foldl(results, (), (acc: Unit, r: (String, Bool, String)) => {
        val label = r.0
        val ok = r.1
        val msg = r.2
        isTrue(s2, label, ok)
        if (!ok) println("  DETAIL: ${msg}")
      })
    })
  })
}
