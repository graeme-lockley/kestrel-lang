import * as BA from "kestrel:data/bytearray"
import { writeTextAtomic, writeBytesAtomic, readText, readBytes, deleteFile } from "kestrel:io/fs"

async fun run(): Task<Unit> = {
  val path = "/tmp/kestrel_test_atomic_write.txt"
  val wr = await writeTextAtomic(path, "hello atomic")
  println(wr)
  // Ok(())
  val rd = await readText(path)
  match (rd) {
    Err(_) => println("read failed")
    Ok(s) => println(s)
  }
  // hello atomic
  val _ = await deleteFile(path)

  val bpath = "/tmp/kestrel_test_atomic_bytes.bin"
  val bytes = BA.fromList([72, 101, 108, 108, 111])
  val bwr = await writeBytesAtomic(bpath, bytes)
  println(bwr)
  // Ok(())
  val brd = await readBytes(bpath)
  match (brd) {
    Err(_) => println("read bytes failed")
    Ok(bs) => println(BA.toList(bs))
  }
  // [72, 101, 108, 108, 111]
  val _ = await deleteFile(bpath)
}

run()
