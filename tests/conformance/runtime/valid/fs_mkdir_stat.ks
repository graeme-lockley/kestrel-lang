// Runtime conformance: mkdirAll, stat, touchFile
import { mkdirAll, stat, touchFile, deleteFile, fileExists } from "kestrel:io/fs"

async fun run(): Task<Unit> = {
  val tmpDir = "/tmp/kestrel_conform_mkdir_stat"
  val _del = await deleteFile(tmpDir)
  val mr = await mkdirAll(tmpDir)
  println(mr)
  // Ok(())

  val mr2 = await mkdirAll(tmpDir)
  println(mr2)
  // Ok(())

  val tmpFile = "/tmp/kestrel_conform_mkdir_stat/hello.txt"
  val tr = await touchFile(tmpFile)
  println(tr)
  // Ok(())

  val sr = await stat(tmpFile)
  match (sr) {
    Err(_) => println("FAIL")
    Ok(s) => {
      println(s.size)
      // 0
      println(s.isFile)
      // True
      println(s.isDir)
      // False
    }
  }

  val dr = await stat(tmpDir)
  match (dr) {
    Err(_) => println("FAIL")
    Ok(d) => {
      println(d.isDir)
      // True
    }
  }

  val sr2 = await stat("/tmp/__no_such_file_kestrel__")
  match (sr2) {
    Err(e) => println("NotFound")
    Ok(_) => println("FAIL")
  }
  // NotFound

  println("done")
  // done
}

run()
