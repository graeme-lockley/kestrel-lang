import * as Fs from "kestrel:io/fs"
import * as Str from "kestrel:data/string"
import * as List from "kestrel:data/list"

val tmpDir = "/tmp/kestrel_e2e_watch"
val watchFile = "${tmpDir}/test.ks"
val subDir = "${tmpDir}/sub"
val subFile = "${subDir}/child.ks"

async fun testMissingDir(): Task<Unit> = {
  val r = await Fs.watchDir("/tmp/no_such_dir_kestrel_12345", 200);
  println(match (r) { Ok(_) => "FAIL", Err(_) => "watchDir-missing-err" })
}

async fun testOpenClose(): Task<Unit> = {
  val r = await Fs.watchDir(tmpDir, 300);
  match (r) {
    Err(_) => println("FAIL")
    Ok(w) => {
      val _ = await Fs.watcherClose(w);
      println("watchDir-ok-closed")
    }
  }
}

async fun testDetectsWrite(): Task<Unit> = {
  val wr = await Fs.watchDir(tmpDir, 300);
  match (wr) {
    Err(_) => println("FAIL")
    Ok(w) => {
      val _ = await Fs.writeText(watchFile, "// hello");
      val paths = await Fs.watcherNext(w);
      val _ = await Fs.watcherClose(w);
      if (!List.isEmpty(paths) & List.any(paths, (p: String) => Str.contains("test.ks", p)))
        println("watcherNext-detects-write")
      else
        println("FAIL")
    }
  }
}

async fun testDetectsSubdir(): Task<Unit> = {
  val wr = await Fs.watchDir(tmpDir, 300);
  match (wr) {
    Err(_) => println("FAIL")
    Ok(w) => {
      val _ = await Fs.mkdirAll(subDir);
      val _ = await Fs.writeText(subFile, "// child");
      val paths = await Fs.watcherNext(w);
      val _ = await Fs.watcherClose(w);
      if (!List.isEmpty(paths))
        println("watcherNext-detects-subdir")
      else
        println("FAIL")
    }
  }
}

async fun testCloseEmptiesNext(): Task<Unit> = {
  val wr = await Fs.watchDir(tmpDir, 100);
  match (wr) {
    Err(_) => println("FAIL")
    Ok(w) => {
      val _ = await Fs.watcherClose(w);
      val paths = await Fs.watcherNext(w);
      if (List.isEmpty(paths))
        println("watcherClose-empties-next")
      else
        println("FAIL")
    }
  }
}

async fun main(): Task<Unit> = {
  val _ = await Fs.mkdirAll(tmpDir);
  await testMissingDir();
  await testOpenClose();
  await testDetectsWrite();
  await testDetectsSubdir();
  await testCloseEmptiesNext()
}

main()
