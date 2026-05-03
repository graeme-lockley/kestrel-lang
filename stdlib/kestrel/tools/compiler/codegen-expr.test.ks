import { Suite, group, eq, isTrue } from "kestrel:dev/test"
import * as CF from "kestrel:tools/compiler/classfile"
import * as CG from "kestrel:tools/compiler/codegen"
import * as BA from "kestrel:data/bytearray"
import * as Arr from "kestrel:data/array"
import * as Lst from "kestrel:data/list"
import { ELit, EIdent, EBinary, EIf, ERecord, ETuple, EMatch, ELambda, ECall, EBlock, ETemplate, TmplLit, TmplExpr, PWild } from "kestrel:dev/parser/ast"

type TestCtx = { cf: CF.ClassFileBuilder, mb: CF.MethodBuilder, ctx: CG.CodegenContext }

// Return the byte at position i in the method's code buffer.
fun codeAt(mb: CF.MethodBuilder, i: Int): Int = Arr.get(CF.mbGetCode(mb), i)

// True iff `haystack` starts with all bytes of `prefix`.
fun seqStartsWith(xs: List<Int>, prefix: List<Int>): Bool =
  match (prefix) {
    [] => True
    p :: restP => match (xs) {
      [] => False
      x :: restX => if (x == p) seqStartsWith(restX, restP) else False
    }
  }

// True iff `needle` appears as a contiguous subsequence anywhere in `haystack`.
fun containsSeq(haystack: List<Int>, needle: List<Int>): Bool =
  if (Lst.isEmpty(needle)) True
  else match (haystack) {
    [] => False
    _ :: rest =>
      if (seqStartsWith(haystack, needle)) True
      else containsSeq(rest, needle)
  }

fun baseContext(): TestCtx = {
  val cf = CF.newClassFile("test/CodegenExpr", "java/lang/Object", 0x0021)
  val mb = CF.cfAddMethod(cf, "emit", "()Ljava/lang/Object;", 0x0009)
  { cf = cf, mb = mb, ctx = CG.newCodegenContext(cf, mb) }
}

fun finish(cf: CF.ClassFileBuilder, mb: CF.MethodBuilder): ByteArray = {
  CF.mbEmit1(mb, 0xB0) // areturn
  CF.mbSetMaxs(mb, 6, 8)
  CF.cfToBytes(cf)
}

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:tools/compiler/codegen-expr", (s1: Suite) => {
    group(s1, "literals and binary", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, ELit("int", "42"))
      CG.emitExpr(t.ctx, EBinary("+", ELit("int", "1"), ELit("int", "2")))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "class bytes exist", BA.length(bytes) > 0)
    })

    group(s1, "if and block", (sg: Suite) => {
      val t = baseContext()
      val block = { stmts = [], result = ELit("int", "5") }
      CG.emitExpr(t.ctx, EIf(ELit("true", "True"), EBlock(block), Some(ELit("int", "0"))))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "if emits", BA.length(bytes) > 0)
    })

    group(s1, "record tuple match", (sg: Suite) => {
      val t = baseContext()
      val rec = ERecord(None, [{ name = "x", mut_ = False, value = ELit("int", "1") }])
      val tup = ETuple([ELit("int", "1"), ELit("int", "2")])
      val m = EMatch(ELit("int", "1"), [{ pattern = PWild, body = ELit("int", "3") }])
      CG.emitExpr(t.ctx, rec)
      CG.emitExpr(t.ctx, tup)
      CG.emitExpr(t.ctx, m)
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "structured forms emit", BA.length(bytes) > 0)
    })

    group(s1, "lambda template call", (sg: Suite) => {
      val t = baseContext()
      val lam = ELambda(False, [], [{ name = "x", type_ = None }], EIdent("x"))
      val tpl = ETemplate([TmplLit("a="), TmplExpr(ELit("int", "1"))])
      val call = ECall(lam, [ELit("int", "9")])
      CG.emitExpr(t.ctx, lam)
      CG.emitExpr(t.ctx, tpl)
      CG.emitExpr(t.ctx, call)
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "lambda/template/call emit", BA.length(bytes) > 0)
      eq(sg, "runtime const exported", CG.RUNTIME, "kestrel/runtime/KRuntime")
    })

    group(s1, "float literal", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, ELit("float", "3.14"))
      // Opcode sequence: ldc2W(20) at offset 0, invokestatic(184) at offset 3
      eq(sg, "float: opcode[0] is ldc2W", codeAt(t.mb, 0), 20)
      eq(sg, "float: opcode[3] is invokestatic", codeAt(t.mb, 3), 184)
      val bytes = finish(t.cf, t.mb)
      // Constant-pool: "java/lang/Double" UTF-8 entry must be present (from Double.valueOf ref)
      // ASCII for "Double": [68, 111, 117, 98, 108, 101]
      isTrue(sg, "float: pool contains Double ref",
        containsSeq(BA.toList(bytes), [68, 111, 117, 98, 108, 101]))
    })

    group(s1, "string literal", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, ELit("string", "hello"))
      // Opcode sequence: ldcW(19) at offset 0
      eq(sg, "string: opcode[0] is ldcW", codeAt(t.mb, 0), 19)
      val bytes = finish(t.cf, t.mb)
      // Constant-pool: UTF-8 bytes for "hello" = [104, 101, 108, 108, 111]
      isTrue(sg, "string: pool contains hello utf8",
        containsSeq(BA.toList(bytes), [104, 101, 108, 108, 111]))
    })

    group(s1, "char literal plain", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, ELit("char", "a"))
      // Opcode sequence: ldcW(19) at offset 0, invokestatic(184) at offset 3
      eq(sg, "char plain: opcode[0] is ldcW", codeAt(t.mb, 0), 19)
      eq(sg, "char plain: opcode[3] is invokestatic", codeAt(t.mb, 3), 184)
      val bytes = finish(t.cf, t.mb)
      // Constant-pool: cpInteger(3) entry for code point 97 ('a') = [3, 0, 0, 0, 97]
      isTrue(sg, "char plain: pool contains int constant 97",
        containsSeq(BA.toList(bytes), [3, 0, 0, 0, 97]))
    })

    group(s1, "char literal escape", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, ELit("char", "\\n"))
      // Opcode sequence: ldcW(19) at offset 0, invokestatic(184) at offset 3
      eq(sg, "char esc: opcode[0] is ldcW", codeAt(t.mb, 0), 19)
      eq(sg, "char esc: opcode[3] is invokestatic", codeAt(t.mb, 3), 184)
      val bytes = finish(t.cf, t.mb)
      // Constant-pool: cpInteger(3) entry for code point 10 ('\n') = [3, 0, 0, 0, 10]
      isTrue(sg, "char esc: pool contains int constant 10",
        containsSeq(BA.toList(bytes), [3, 0, 0, 0, 10]))
    })

    group(s1, "unit literal", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, ELit("unit", ""))
      // Opcode sequence: getstatic(178) at offset 0
      eq(sg, "unit: opcode[0] is getstatic", codeAt(t.mb, 0), 178)
      val bytes = finish(t.cf, t.mb)
      // Constant-pool: UTF-8 for "INSTANCE" = [73, 78, 83, 84, 65, 78, 67, 69]
      isTrue(sg, "unit: pool contains INSTANCE utf8",
        containsSeq(BA.toList(bytes), [73, 78, 83, 84, 65, 78, 67, 69]))
    })
  })
