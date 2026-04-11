// Runtime conformance: ByteArray binary I/O
import * as BA from "kestrel:data/bytearray"
import { readBytes, writeBytes, appendBytes, deleteFile, fileExists } from "kestrel:io/fs"
import * as Lst from "kestrel:data/list"

async fun run(): Task<Unit> = {
  val arr = BA.new(4)
  println(BA.length(arr))
  // 4

  BA.set(arr, 0, 65)
  BA.set(arr, 1, 66)
  BA.set(arr, 2, 67)
  BA.set(arr, 3, 68)
  println(BA.get(arr, 0))
  // 65
  println(BA.get(arr, 3))
  // 68

  val xs = [1, 2, 3, 255]
  val arr2 = BA.fromList(xs)
  val back = BA.toList(arr2)
  println(back)
  // [1, 2, 3, 255]

  val a = BA.fromList([10, 20])
  val b = BA.fromList([30, 40])
  val c = BA.concat(a, b)
  println(BA.toList(c))
  // [10, 20, 30, 40]

  val sl = BA.slice(c, 1, 3)
  println(BA.toList(sl))
  // [20, 30]

  val tmpPath = "/tmp/kestrel_test_bytes.bin"
  val _del = await deleteFile(tmpPath)
  val data = BA.fromList([0, 1, 2, 127, 128, 255])
  val wr = await writeBytes(tmpPath, data)
  println(wr)
  // Ok(())

  val readResult = await readBytes(tmpPath)
  match (readResult) {
    Err(e) => println("FAIL")
    Ok(readData) => {
      val readList = BA.toList(readData)
      println(readList)
      // [0, 1, 2, 127, 128, 255]
    }
  }

  val app = BA.fromList([100, 200])
  val _app = await appendBytes(tmpPath, app)
  val readResult2 = await readBytes(tmpPath)
  match (readResult2) {
    Err(_) => println("FAIL")
    Ok(rd2) => {
      val lst2 = BA.toList(rd2)
      println(Lst.length(lst2))
      // 8
    }
  }

  val _cleanup = await deleteFile(tmpPath)
  println("done")
  // done
}

run()
