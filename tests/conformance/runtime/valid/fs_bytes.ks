// Runtime conformance: ByteArray binary I/O
import {
  byteArrayNew, byteArrayLength, byteArrayGet, byteArraySet,
  byteArrayFromList, byteArrayToList, byteArrayConcat, byteArraySlice,
  readBytes, writeBytes, appendBytes, deleteFile, fileExists
} from "kestrel:io/fs"
import * as Lst from "kestrel:data/list"

async fun run(): Task<Unit> = {
  // byteArrayNew / length / get / set
  val arr = byteArrayNew(4)
  println(byteArrayLength(arr))
  // 4

  byteArraySet(arr, 0, 65)
  byteArraySet(arr, 1, 66)
  byteArraySet(arr, 2, 67)
  byteArraySet(arr, 3, 68)
  println(byteArrayGet(arr, 0))
  // 65
  println(byteArrayGet(arr, 3))
  // 68

  // fromList / toList round-trip
  val xs = [1, 2, 3, 255]
  val arr2 = byteArrayFromList(xs)
  val back = byteArrayToList(arr2)
  println(back)
  // [1, 2, 3, 255]

  // concat
  val a = byteArrayFromList([10, 20])
  val b = byteArrayFromList([30, 40])
  val c = byteArrayConcat(a, b)
  println(byteArrayToList(c))
  // [10, 20, 30, 40]

  // slice
  val sl = byteArraySlice(c, 1, 3)
  println(byteArrayToList(sl))
  // [20, 30]

  // readBytes / writeBytes round-trip
  val tmpPath = "/tmp/kestrel_test_bytes.bin"
  val _del = await deleteFile(tmpPath)
  val data = byteArrayFromList([0, 1, 2, 127, 128, 255])
  val wr = await writeBytes(tmpPath, data)
  println(wr)
  // Ok(())

  val readResult = await readBytes(tmpPath)
  match (readResult) {
    Err(e) => println("FAIL")
    Ok(readData) => {
      val readList = byteArrayToList(readData)
      println(readList)
      // [0, 1, 2, 127, 128, 255]
    }
  }

  // appendBytes
  val app = byteArrayFromList([100, 200])
  val _app = await appendBytes(tmpPath, app)
  val readResult2 = await readBytes(tmpPath)
  match (readResult2) {
    Err(_) => println("FAIL")
    Ok(rd2) => {
      val lst2 = byteArrayToList(rd2)
      println(Lst.length(lst2))
      // 8
    }
  }

  val _cleanup = await deleteFile(tmpPath)
  ()
}

run()
