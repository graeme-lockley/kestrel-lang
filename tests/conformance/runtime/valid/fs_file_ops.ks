// Runtime conformance: fileExists, deleteFile, renameFile
import { fileExists, deleteFile, renameFile, writeText } from "kestrel:io/fs"

async fun run(): Task<Unit> = {
  val tmp1 = "/tmp/kestrel_fs_ops_test_a.txt"
  val tmp2 = "/tmp/kestrel_fs_ops_test_b.txt"

  val _ = await deleteFile(tmp2)
  val _w = await writeText(tmp1, "hello")

  val e1 = await fileExists(tmp1)
  println(e1)
  // True

  val e2 = await fileExists(tmp2)
  println(e2)
  // False

  val r = await renameFile(tmp1, tmp2)
  println(r)
  // Ok(())

  val e3 = await fileExists(tmp1)
  println(e3)
  // False

  val e4 = await fileExists(tmp2)
  println(e4)
  // True

  val d = await deleteFile(tmp2)
  println(d)
  // Ok(())

  val e5 = await fileExists(tmp2)
  println(e5)
  // False
}

run()
