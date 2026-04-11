import { listDirAll, collectFilesByExtension, mkdirAll, writeText, DirEntry, Dir, File, FsError, NotFound } from "kestrel:io/fs"
import { member, length } from "kestrel:data/list"

async fun run(): Task<Unit> = {
  val root = "/tmp/kestrel_conform_recursive_listdir"
  val _m0 = await mkdirAll("${root}/a/b")
  val _m1 = await mkdirAll("${root}/empty")

  val _w0 = await writeText("${root}/root.txt", "r")
  val _w1 = await writeText("${root}/a/x.kti", "x")
  val _w2 = await writeText("${root}/a/b/y.kti", "y")
  val _w3 = await writeText("${root}/a/b/z.txt", "z")

  val allr = await listDirAll(root)
  match (allr) {
    Err(_) => println("FAIL")
    Ok(entries) => {
      println(member(entries, Dir("${root}/a")))
      // True
      println(member(entries, Dir("${root}/a/b")))
      // True
      println(member(entries, File("${root}/root.txt")))
      // True
      println(member(entries, File("${root}/a/x.kti")))
      // True
      println(member(entries, File("${root}/a/b/y.kti")))
      // True
    }
  }

  val kti = await collectFilesByExtension(root, ".kti")
  match (kti) {
    Err(_) => println("FAIL")
    Ok(paths) => {
      println(length(paths))
      // 2
      println(member(paths, "${root}/a/x.kti"))
      // True
      println(member(paths, "${root}/a/b/y.kti"))
      // True
    }
  }

  val missingAll = await listDirAll("${root}/nope")
  match (missingAll) {
    Err(NotFound) => println("NotFound")
    _ => println("FAIL")
  }
  // NotFound

  val missingExt = await collectFilesByExtension("${root}/nope", ".kti")
  match (missingExt) {
    Err(NotFound) => println("NotFound")
    _ => println("FAIL")
  }
  // NotFound

  val empty = await listDirAll("${root}/empty")
  match (empty) {
    Ok(xs) => println(length(xs))
    Err(_) => println("FAIL")
  }
  // 0
}

run()
