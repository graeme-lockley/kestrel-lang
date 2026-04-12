import { Suite, group, eq, isTrue } from "kestrel:dev/test"
import * as Arr from "kestrel:data/array"
import * as BA from "kestrel:data/bytearray"
import * as CF from "kestrel:tools/compiler/classfile"

fun byteAt(bytes: ByteArray, i: Int): Int = BA.get(bytes, i)

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:tools/compiler/classfile", (s1: Suite) => {
    group(s1, "class header", (sg: Suite) => {
      val cf = CF.newClassFile("test/Hello", "java/lang/Object", 0x0021)
      val mb = CF.cfAddMethod(cf, "foo", "()V", 0x0009)
      CF.mbEmit1(mb, 0xB1)
      CF.mbSetMaxs(mb, 0, 1)
      val bytes = CF.cfToBytes(cf)
      eq(sg, "magic byte 0", byteAt(bytes, 0), 0xCA)
      eq(sg, "magic byte 1", byteAt(bytes, 1), 0xFE)
      eq(sg, "magic byte 2", byteAt(bytes, 2), 0xBA)
      eq(sg, "magic byte 3", byteAt(bytes, 3), 0xBE)
      eq(sg, "major version hi", byteAt(bytes, 6), 0x00)
      eq(sg, "major version lo", byteAt(bytes, 7), 0x33)
    })

    group(s1, "constant pool dedup", (sg: Suite) => {
      val cf = CF.newClassFile("test/A", "java/lang/Object", 0x0021)
      val utfA = CF.cfUtf8(cf, "Hello")
      val utfB = CF.cfUtf8(cf, "Hello")
      val utfC = CF.cfUtf8(cf, "World")
      eq(sg, "utf8 dedup", utfA, utfB)
      isTrue(sg, "utf8 unique", utfA != utfC)

      val c1 = CF.cfClassRef(cf, "java/lang/String")
      val c2 = CF.cfClassRef(cf, "java/lang/String")
      isTrue(sg, "class dedup", c1 == c2)

      val m1 = CF.cfMethodref(cf, "java/lang/Object", "<init>", "()V")
      val m2 = CF.cfMethodref(cf, "java/lang/Object", "<init>", "()V")
      isTrue(sg, "methodref dedup", m1 == m2)
    })

    group(s1, "method buffer", (sg: Suite) => {
      val cf = CF.newClassFile("test/M", "java/lang/Object", 0x0021)
      val mb = CF.cfAddMethod(cf, "m", "()V", 0x0009)
      eq(sg, "initial length", CF.mbLength(mb), 0)
      CF.mbEmit1(mb, 0x00)
      eq(sg, "after nop", CF.mbLength(mb), 1)
      CF.mbEmit1b(mb, 0x10, 42)
      eq(sg, "after bipush", CF.mbLength(mb), 3)
      CF.mbEmit1s(mb, 0x11, 1000)
      eq(sg, "after sipush", CF.mbLength(mb), 6)
    })

    group(s1, "backpatch style update", (sg: Suite) => {
      val cf = CF.newClassFile("test/P", "java/lang/Object", 0x0021)
      val mb = CF.cfAddMethod(cf, "jump", "()V", 0x0009)
      CF.mbEmit1(mb, 0xA7)
      CF.mbPushShort(mb, 0)
      val code = CF.mbGetCode(mb)
      Arr.set(code, 1, 0x00)
      Arr.set(code, 2, 0x05)
      eq(sg, "patched hi byte", Arr.get(code, 1), 0x00)
      eq(sg, "patched lo byte", Arr.get(code, 2), 0x05)
    })

    group(s1, "toBytes non-empty", (sg: Suite) => {
      val cf = CF.newClassFile("test/D", "java/lang/Object", 0x0031)
      val mb = CF.cfAddMethod(cf, "<init>", "()V", 0x0001)
      CF.mbEmit1(mb, 0xB1)
      CF.mbSetMaxs(mb, 0, 1)
      val bytes = CF.cfToBytes(cf)
      isTrue(sg, "serialized bytes present", BA.length(bytes) > 0)
    })
  })
