import { Suite, group, eq, isTrue } from "kestrel:dev/test"
import * as CF from "kestrel:tools/compiler/classfile"
import * as CG from "kestrel:tools/compiler/codegen"
import * as BA from "kestrel:data/bytearray"
import { ELit, EIdent, EBinary, EIf, ERecord, ETuple, EMatch, ELambda, ECall, EBlock, ETemplate, TmplLit, TmplExpr, PWild } from "kestrel:dev/parser/ast"

type TestCtx = { cf: CF.ClassFileBuilder, mb: CF.MethodBuilder, ctx: CG.CodegenContext }

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
  })
