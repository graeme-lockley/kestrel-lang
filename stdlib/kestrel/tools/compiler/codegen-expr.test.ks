import { Suite, group, eq, isTrue } from "kestrel:dev/test"
import * as CF from "kestrel:tools/compiler/classfile"
import * as CG from "kestrel:tools/compiler/codegen"
import * as BA from "kestrel:data/bytearray"
import * as Arr from "kestrel:data/array"
import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Ty from "kestrel:dev/typecheck/types"
import { ELit, EIdent, EBinary, EUnary, EIf, EWhile, ERecord, ETuple, EMatch, ELambda, ECall, EBlock, ETemplate, TmplLit, TmplExpr, PWild, PVar, PLit, PCon, PList, PCons, PTuple, EField, SVal, SVar, SAssign, SExpr, SFun, SBreak, SContinue, EList, ECons, EPipe, LElem, EThrow, ETry, EAwait, EIs, ENever, ATPrim } from "kestrel:dev/parser/ast"
import * as Ast from "kestrel:dev/parser/ast"

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
  { cf = cf, mb = mb, ctx = CG.newCodegenContext(cf, mb, CG.emptyModuleContext("test/CodegenExpr"), CG.noTypeInfo) }
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

    group(s1, "if: then/else branch emits ifeq", (sg: Suite) => {
      // if (True) 1 else 2  — must emit IFEQ (opcode 153) for real conditional branching
      val t = baseContext()
      CG.emitExpr(t.ctx, EIf(ELit("true", "True"), ELit("int", "1"), Some(ELit("int", "2"))))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      isTrue(sg, "if emits ifeq opcode (153)", containsSeq(code, [153]))
    })

    group(s1, "if: no-else arm emits KUnit getstatic", (sg: Suite) => {
      // if (True) println() — no else; KUnit.INSTANCE is loaded via getstatic (opcode 178)
      val t = baseContext()
      CG.emitExpr(t.ctx, EIf(ELit("true", "True"), ELit("unit", ""), None))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      isTrue(sg, "no-else arm emits ifeq opcode (153)", containsSeq(code, [153]))
      // getstatic = 178 (0xB2), present for KUnit.INSTANCE in the else path
      isTrue(sg, "no-else arm emits getstatic (178) for KUnit", containsSeq(code, [178]))
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
      eq(sg, "lambda: opcode[0] is NEW", codeAt(t.mb, 0), 187)
      isTrue(sg, "lambda: does not emit aconstNull at start", codeAt(t.mb, 0) != 1)
      CG.emitExpr(t.ctx, tpl)
      CG.emitExpr(t.ctx, call)
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "lambda/template/call emit", BA.length(bytes) > 0)
      eq(sg, "runtime const exported", CG.RUNTIME, "kestrel/runtime/KRuntime")
    })

    group(s1, "capturing lambda emits env array", (sg: Suite) => {
      val t = baseContext()
      CG.emitBlockStmt(t.ctx, SVal("x", None, ELit("int", "7")))
      val lam = ELambda(False, [], [{ name = "y", type_ = None }], EBinary("+", EIdent("x"), EIdent("y")))
      CG.emitExpr(t.ctx, lam)
      val code = Arr.toList(CF.mbGetCode(t.mb))
      // ANEWARRAY = 189 for captured environment object[]
      isTrue(sg, "capturing lambda: emits ANEWARRAY(189)", containsSeq(code, [189]))
      // INVOKESPECIAL = 183 for captured ctor <init>([Object)
      isTrue(sg, "capturing lambda: emits INVOKESPECIAL(183)", containsSeq(code, [183]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "capturing lambda: class bytes exist", BA.length(bytes) > 0)
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

    group(s1, "EIdent None produces getstatic KNone", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, EIdent("None"))
      // getstatic(178) at offset 0
      eq(sg, "None: opcode[0] is getstatic", codeAt(t.mb, 0), 178)
      val bytes = finish(t.cf, t.mb)
      // UTF-8 bytes for "KNone" = [75, 78, 111, 110, 101]
      isTrue(sg, "None: pool contains KNone utf8",
        containsSeq(BA.toList(bytes), [75, 78, 111, 110, 101]))
    })

    group(s1, "EIdent Nil produces getstatic KNil", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, EIdent("Nil"))
      eq(sg, "Nil: opcode[0] is getstatic", codeAt(t.mb, 0), 178)
      val bytes = finish(t.cf, t.mb)
      // UTF-8 bytes for "KNil" = [75, 78, 105, 108]
      isTrue(sg, "Nil: pool contains KNil utf8",
        containsSeq(BA.toList(bytes), [75, 78, 105, 108]))
    })

    group(s1, "EIdent global val produces getstatic", (sg: Suite) => {
      val cf2 = CF.newClassFile("test/CodegenExpr", "java/lang/Object", 0x0021)
      val mb2 = CF.cfAddMethod(cf2, "emit", "()Ljava/lang/Object;", 0x0009)
      val opts = CG.emptyJvmCodegenOptions()
      val mctxWithGlobal = {
        className = "test/ModuleG",
        globalNames = Dict.insert(Dict.emptyStringDict(), "myVal", ()),
        globalVarNames = Dict.emptyStringDict(),
        funArities = Dict.emptyStringDict(),
        adtClassByConstructor = Dict.emptyStringDict(),
        adtConstructorArity = Dict.emptyStringDict(),
        options = opts,
        mut diagnostics = [],
        mut lambdas = [],
        mut lambdaIndex = 0,
        mut lambdaClasses = Dict.emptyStringDict()
      }
      val ctx2 = CG.newCodegenContext(cf2, mb2, mctxWithGlobal, CG.noTypeInfo)
      CG.emitExpr(ctx2, EIdent("myVal"))
      eq(sg, "global val: opcode[0] is getstatic", codeAt(mb2, 0), 178)
    })

    group(s1, "EIdent global fun produces invokestatic KFunctionRef", (sg: Suite) => {
      val cf3 = CF.newClassFile("test/CodegenExpr", "java/lang/Object", 0x0021)
      val mb3 = CF.cfAddMethod(cf3, "emit", "()Ljava/lang/Object;", 0x0009)
      val opts = CG.emptyJvmCodegenOptions()
      val mctxWithFun = {
        className = "test/ModuleF",
        globalNames = Dict.emptyStringDict(),
        globalVarNames = Dict.emptyStringDict(),
        funArities = Dict.insert(Dict.emptyStringDict(), "myFun", 2),
        adtClassByConstructor = Dict.emptyStringDict(),
        adtConstructorArity = Dict.emptyStringDict(),
        options = opts,
        mut diagnostics = [],
        mut lambdas = [],
        mut lambdaIndex = 0,
        mut lambdaClasses = Dict.emptyStringDict()
      }
      val ctx3 = CG.newCodegenContext(cf3, mb3, mctxWithFun, CG.noTypeInfo)
      CG.emitExpr(ctx3, EIdent("myFun"))
      val bytes3 = finish(cf3, mb3)
      // invokestatic(184) must appear somewhere for KFunctionRef.of
      isTrue(sg, "global fun: invokestatic(184) appears in bytecode",
        containsSeq(BA.toList(bytes3), [184]))
    })

    group(s1, "int add", (sg: Suite) => {
      val cf2 = CF.newClassFile("test/CodegenExpr", "java/lang/Object", 0x0021)
      val mb2 = CF.cfAddMethod(cf2, "emit", "()Ljava/lang/Object;", 0x0009)
      val intTypeInfo: (Ast.Expr) -> Option<Ty.InternalType> = (_: Ast.Expr) => Some(Ty.tInt)
      val ctx2 = CG.newCodegenContext(cf2, mb2, CG.emptyModuleContext("test/CodegenExpr"), intTypeInfo)
      CG.emitExpr(ctx2, EBinary("+", ELit("int", "1"), ELit("int", "2")))
      val bytes = finish(cf2, mb2)
      // invokestatic(184) must appear for KMath.add
      isTrue(sg, "int add: invokestatic(184) in bytecode",
        containsSeq(BA.toList(bytes), [184]))
      // UTF-8 bytes for "KMath" = [75, 77, 97, 116, 104]
      isTrue(sg, "int add: pool contains KMath",
        containsSeq(BA.toList(bytes), [75, 77, 97, 116, 104]))
    })

    group(s1, "string concat", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, EBinary("++", ELit("string", "hello"), ELit("string", "world")))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "concat: invokestatic(184) in bytecode",
        containsSeq(BA.toList(bytes), [184]))
      // UTF-8 bytes for "concat" = [99, 111, 110, 99, 97, 116]
      isTrue(sg, "concat: pool contains concat",
        containsSeq(BA.toList(bytes), [99, 111, 110, 99, 97, 116]))
    })

    group(s1, "equality ==", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, EBinary("==", ELit("int", "1"), ELit("int", "1")))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "eq: invokestatic(184) in bytecode",
        containsSeq(BA.toList(bytes), [184]))
      // UTF-8 bytes for "equals" = [101, 113, 117, 97, 108, 115]
      isTrue(sg, "eq: pool contains equals",
        containsSeq(BA.toList(bytes), [101, 113, 117, 97, 108, 115]))
    })

    group(s1, "inequality !=", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, EBinary("!=", ELit("int", "1"), ELit("int", "2")))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "ne: bytecode non-empty", BA.length(bytes) > 0)
      // UTF-8 bytes for "equals" = [101, 113, 117, 97, 108, 115]
      isTrue(sg, "ne: pool contains equals",
        containsSeq(BA.toList(bytes), [101, 113, 117, 97, 108, 115]))
    })

    group(s1, "comparison <", (sg: Suite) => {
      val cf2 = CF.newClassFile("test/CodegenExpr", "java/lang/Object", 0x0021)
      val mb2 = CF.cfAddMethod(cf2, "emit", "()Ljava/lang/Object;", 0x0009)
      val intTypeInfo: (Ast.Expr) -> Option<Ty.InternalType> = (_: Ast.Expr) => Some(Ty.tInt)
      val ctx2 = CG.newCodegenContext(cf2, mb2, CG.emptyModuleContext("test/CodegenExpr"), intTypeInfo)
      CG.emitExpr(ctx2, EBinary("<", ELit("int", "1"), ELit("int", "2")))
      val bytes = finish(cf2, mb2)
      isTrue(sg, "lt: invokestatic(184) in bytecode",
        containsSeq(BA.toList(bytes), [184]))
      // UTF-8 bytes for "$less" = [36, 108, 101, 115, 115]
      isTrue(sg, "lt: pool contains mangled-less",
        containsSeq(BA.toList(bytes), [36, 108, 101, 115, 115]))
    })

    group(s1, "unary not", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, EUnary("!", ELit("true", "True")))
      val bytes = finish(t.cf, t.mb)
      // getstatic(178) for Boolean.TRUE and Boolean.FALSE
      isTrue(sg, "not: getstatic(178) in bytecode",
        containsSeq(BA.toList(bytes), [178]))
      // UTF-8 bytes for "FALSE" = [70, 65, 76, 83, 69]
      isTrue(sg, "not: pool contains FALSE",
        containsSeq(BA.toList(bytes), [70, 65, 76, 83, 69]))
    })

    group(s1, "unary negate int", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, EUnary("-", ELit("int", "5")))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "neg: invokestatic(184) in bytecode",
        containsSeq(BA.toList(bytes), [184]))
      // UTF-8 bytes for "KMath" = [75, 77, 97, 116, 104]
      isTrue(sg, "neg: pool contains KMath",
        containsSeq(BA.toList(bytes), [75, 77, 97, 116, 104]))
    })

    group(s1, "short-circuit and", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, EBinary("&", ELit("true", "True"), ELit("true", "True")))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "and: bytecode non-empty", BA.length(bytes) > 0)
      // UTF-8 bytes for "FALSE" = [70, 65, 76, 83, 69]
      isTrue(sg, "and: pool contains FALSE for short-circuit",
        containsSeq(BA.toList(bytes), [70, 65, 76, 83, 69]))
    })

    group(s1, "short-circuit or", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, EBinary("|", ELit("false", "False"), ELit("true", "True")))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "or: bytecode non-empty", BA.length(bytes) > 0)
      // UTF-8 bytes for "TRUE" = [84, 82, 85, 69]
      isTrue(sg, "or: pool contains TRUE for short-circuit",
        containsSeq(BA.toList(bytes), [84, 82, 85, 69]))
    })

    group(s1, "local direct call", (sg: Suite) => {
      // Build a ModuleContext with a known local function 'myFun' of arity 2.
      val cf = CF.newClassFile("test/CallDirect", "java/lang/Object", 0x0021)
      val mb = CF.cfAddMethod(cf, "emit", "()Ljava/lang/Object;", 0x0009)
      val mctx = {
        className = "test/CallDirect",
        globalNames = Dict.emptyStringDict(),
        globalVarNames = Dict.emptyStringDict(),
        funArities = Dict.insert(Dict.emptyStringDict(), "myFun", 2),
        adtClassByConstructor = Dict.emptyStringDict(),
        adtConstructorArity = Dict.emptyStringDict(),
        options = CG.emptyJvmCodegenOptions(),
        mut diagnostics = [],
        mut lambdas = [],
        mut lambdaIndex = 0,
        mut lambdaClasses = Dict.emptyStringDict()
      }
      val ctx = CG.newCodegenContext(cf, mb, mctx, CG.noTypeInfo)
      CG.emitExpr(ctx, ECall(EIdent("myFun"), [ELit("int", "1"), ELit("int", "2")]))
      CF.mbEmit1(mb, 0xB0)
      CF.mbSetMaxs(mb, 8, 16)
      val bytes = CF.cfToBytes(cf)
      isTrue(sg, "direct call: class bytes exist", BA.length(bytes) > 0)
      // INVOKESTATIC = 184 (0xB8)
      isTrue(sg, "direct call: contains INVOKESTATIC(184)",
        containsSeq(BA.toList(bytes), [184]))
      // UTF-8 for "myFun" = [109, 121, 70, 117, 110]
      isTrue(sg, "direct call: pool contains myFun",
        containsSeq(BA.toList(bytes), [109, 121, 70, 117, 110]))
    })

    group(s1, "self tail call lowers to loop GOTO", (sg: Suite) => {
      val cf = CF.newClassFile("test/TailSelf", "java/lang/Object", 0x0021)
      val mb = CF.cfAddMethod(cf, "emit", "()Ljava/lang/Object;", 0x0009)
      val mctx = {
        className = "test/TailSelf",
        globalNames = Dict.emptyStringDict(),
        globalVarNames = Dict.emptyStringDict(),
        funArities = Dict.insert(Dict.emptyStringDict(), "sum", 2),
        adtClassByConstructor = Dict.emptyStringDict(),
        adtConstructorArity = Dict.emptyStringDict(),
        options = CG.emptyJvmCodegenOptions(),
        mut diagnostics = [],
        mut lambdas = [],
        mut lambdaIndex = 0,
        mut lambdaClasses = Dict.emptyStringDict()
      }
      val ctx = CG.newCodegenContext(cf, mb, mctx, CG.noTypeInfo)
      ctx.tailCtx := Some({ funcName = "sum", paramSlots = [0, 1], loopHead = 0 })
      CG.emitExpr(ctx, ECall(EIdent("sum"), [ELit("int", "4"), ELit("int", "5")]))
      val code = Arr.toList(CF.mbGetCode(mb))
      val bytes = finish(cf, mb)
      isTrue(sg, "self-tail: emits GOTO(167)", containsSeq(code, [167]))
      isTrue(sg, "self-tail: emits ASTORE0(75)", containsSeq(code, [75]))
      isTrue(sg, "self-tail: emits ASTORE1(76)", containsSeq(code, [76]))
      // UTF-8 bytes for "sum" = [115, 117, 109]; direct tail lowering should avoid a methodref to sum.
      isTrue(sg, "self-tail: no direct sum method symbol in pool", !containsSeq(BA.toList(bytes), [115, 117, 109]))
    })

    group(s1, "mutual recursion call stays INVOKESTATIC", (sg: Suite) => {
      val cf = CF.newClassFile("test/TailMutual", "java/lang/Object", 0x0021)
      val mb = CF.cfAddMethod(cf, "emit", "()Ljava/lang/Object;", 0x0009)
      val mctx = {
        className = "test/TailMutual",
        globalNames = Dict.emptyStringDict(),
        globalVarNames = Dict.emptyStringDict(),
        funArities = Dict.insert(Dict.insert(Dict.emptyStringDict(), "even", 1), "odd", 1),
        adtClassByConstructor = Dict.emptyStringDict(),
        adtConstructorArity = Dict.emptyStringDict(),
        options = CG.emptyJvmCodegenOptions(),
        mut diagnostics = [],
        mut lambdas = [],
        mut lambdaIndex = 0,
        mut lambdaClasses = Dict.emptyStringDict()
      }
      val ctx = CG.newCodegenContext(cf, mb, mctx, CG.noTypeInfo)
      ctx.tailCtx := Some({ funcName = "even", paramSlots = [0], loopHead = 0 })
      CG.emitExpr(ctx, ECall(EIdent("odd"), [ELit("int", "9")]))
      val code = Arr.toList(CF.mbGetCode(mb))
      isTrue(sg, "mutual-tail fallback: emits INVOKESTATIC(184)", containsSeq(code, [184]))
    })

    group(s1, "if tail then-arm remains verifier-safe", (sg: Suite) => {
      val cf = CF.newClassFile("test/TailIf", "java/lang/Object", 0x0021)
      val mb = CF.cfAddMethod(cf, "emit", "()Ljava/lang/Object;", 0x0009)
      val mctx = {
        className = "test/TailIf",
        globalNames = Dict.emptyStringDict(),
        globalVarNames = Dict.emptyStringDict(),
        funArities = Dict.insert(Dict.emptyStringDict(), "sum", 2),
        adtClassByConstructor = Dict.emptyStringDict(),
        adtConstructorArity = Dict.emptyStringDict(),
        options = CG.emptyJvmCodegenOptions(),
        mut diagnostics = [],
        mut lambdas = [],
        mut lambdaIndex = 0,
        mut lambdaClasses = Dict.emptyStringDict()
      }
      val ctx = CG.newCodegenContext(cf, mb, mctx, CG.noTypeInfo)
      ctx.tailCtx := Some({ funcName = "sum", paramSlots = [0, 1], loopHead = 0 })
      val tailThen = ECall(EIdent("sum"), [ELit("int", "1"), ELit("int", "2")])
      CG.emitExpr(ctx, EIf(ELit("true", "True"), tailThen, Some(ELit("int", "0"))))
      val code = Arr.toList(CF.mbGetCode(mb))
      isTrue(sg, "if-tail: emits IFEQ(153)", containsSeq(code, [153]))
      isTrue(sg, "if-tail: emits GOTO(167)", containsSeq(code, [167]))
      val bytes = finish(cf, mb)
      isTrue(sg, "if-tail: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "ADT ctor call - Some", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, ECall(EIdent("Some"), [ELit("int", "42")]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "Some: class bytes exist", BA.length(bytes) > 0)
      // NEW = 187 (0xBB)
      isTrue(sg, "Some: contains NEW(187)", containsSeq(BA.toList(bytes), [187]))
      // INVOKESPECIAL = 183 (0xB7)
      isTrue(sg, "Some: contains INVOKESPECIAL(183)", containsSeq(BA.toList(bytes), [183]))
      // UTF-8 bytes for "KSome" = [75, 83, 111, 109, 101]
      isTrue(sg, "Some: pool contains KSome",
        containsSeq(BA.toList(bytes), [75, 83, 111, 109, 101]))
    })

    group(s1, "println call", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, ECall(EIdent("println"), [ELit("string", "hello")]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "println: class bytes exist", BA.length(bytes) > 0)
      // INVOKESTATIC = 184 (0xB8)
      isTrue(sg, "println: contains INVOKESTATIC(184)",
        containsSeq(BA.toList(bytes), [184]))
      // UTF-8 bytes for "println" = [112, 114, 105, 110, 116, 108, 110]
      isTrue(sg, "println: pool contains println",
        containsSeq(BA.toList(bytes), [112, 114, 105, 110, 116, 108, 110]))
      // GETSTATIC = 178 for KUnit.INSTANCE
      isTrue(sg, "println: contains GETSTATIC(178) for KUnit",
        containsSeq(BA.toList(bytes), [178]))
    })

    group(s1, "indirect call", (sg: Suite) => {
      val t = baseContext()
      val lam = ELambda(False, [], [{name = "x", type_ = None}], EIdent("x"))
      CG.emitExpr(t.ctx, ECall(lam, [ELit("int", "5")]))
      CF.mbEmit1(t.mb, 0xB0)
      CF.mbSetMaxs(t.mb, 8, 16)
      val bytes = CF.cfToBytes(t.cf)
      isTrue(sg, "indirect: class bytes exist", BA.length(bytes) > 0)
      // INVOKEINTERFACE = 185 (0xB9)
      isTrue(sg, "indirect: contains INVOKEINTERFACE(185)",
        containsSeq(BA.toList(bytes), [185]))
      // UTF-8 bytes for "KFunction" = [75, 70, 117, 110, 99, 116, 105, 111, 110]
      isTrue(sg, "indirect: pool contains KFunction",
        containsSeq(BA.toList(bytes), [75, 70, 117, 110, 99, 116, 105, 111, 110]))
    })

    group(s1, "ERecord no-spread creates KRecord", (sg: Suite) => {
      val t = baseContext()
      val rec = ERecord(None, [{ name = "x", mut_ = False, value = ELit("int", "1") }, { name = "y", mut_ = False, value = ELit("int", "2") }])
      CG.emitExpr(t.ctx, rec)
      val bytes = finish(t.cf, t.mb)
      // NEW = 187 (0xBB)
      isTrue(sg, "ERecord no-spread: contains NEW(187)", containsSeq(BA.toList(bytes), [187]))
      // UTF-8 bytes for "KRecord" = [75, 82, 101, 99, 111, 114, 100]
      isTrue(sg, "ERecord no-spread: pool contains KRecord utf8",
        containsSeq(BA.toList(bytes), [75, 82, 101, 99, 111, 114, 100]))
      // INVOKEVIRTUAL = 182 for set
      isTrue(sg, "ERecord no-spread: contains INVOKEVIRTUAL(182)", containsSeq(BA.toList(bytes), [182]))
      // UTF-8 bytes for "set" = [115, 101, 116]
      isTrue(sg, "ERecord no-spread: pool contains set utf8",
        containsSeq(BA.toList(bytes), [115, 101, 116]))
    })

    group(s1, "ERecord spread calls copy", (sg: Suite) => {
      val t = baseContext()
      // Spread from a local; put base in locals first via SVal
      val baseRec = ERecord(None, [{ name = "a", mut_ = False, value = ELit("int", "10") }])
      CG.emitBlockStmt(t.ctx, SVal("base", None, baseRec))
      val spread = ERecord(Some(EIdent("base")), [{ name = "b", mut_ = False, value = ELit("int", "20") }])
      CG.emitExpr(t.ctx, spread)
      val bytes = finish(t.cf, t.mb)
      // UTF-8 bytes for "copy" = [99, 111, 112, 121]
      isTrue(sg, "ERecord spread: pool contains copy utf8",
        containsSeq(BA.toList(bytes), [99, 111, 112, 121]))
      // CHECKCAST = 192
      isTrue(sg, "ERecord spread: contains CHECKCAST(192)", containsSeq(BA.toList(bytes), [192]))
    })

    group(s1, "EField emits get invokevirtual", (sg: Suite) => {
      val t = baseContext()
      // Store a record in a local, then access a field
      val rec = ERecord(None, [{ name = "x", mut_ = False, value = ELit("int", "42") }])
      CG.emitBlockStmt(t.ctx, SVal("r", None, rec))
      CG.emitExpr(t.ctx, EField(EIdent("r"), "x"))
      val bytes = finish(t.cf, t.mb)
      // INVOKEVIRTUAL = 182 for get
      isTrue(sg, "EField: contains INVOKEVIRTUAL(182)", containsSeq(BA.toList(bytes), [182]))
      // UTF-8 bytes for "get" = [103, 101, 116]
      isTrue(sg, "EField: pool contains get utf8",
        containsSeq(BA.toList(bytes), [103, 101, 116]))
      // CHECKCAST = 192
      isTrue(sg, "EField: contains CHECKCAST(192)", containsSeq(BA.toList(bytes), [192]))
    })

    group(s1, "SVar boxes in KRecord", (sg: Suite) => {
      val t = baseContext()
      CG.emitBlockStmt(t.ctx, SVar("n", None, ELit("int", "0")))
      val bytes = finish(t.cf, t.mb)
      // NEW = 187 for KRecord boxing
      isTrue(sg, "SVar: contains NEW(187)", containsSeq(BA.toList(bytes), [187]))
      // UTF-8 bytes for "KRecord" = [75, 82, 101, 99, 111, 114, 100]
      isTrue(sg, "SVar: pool contains KRecord utf8",
        containsSeq(BA.toList(bytes), [75, 82, 101, 99, 111, 114, 100]))
      // INVOKEVIRTUAL = 182 for set
      isTrue(sg, "SVar: contains INVOKEVIRTUAL(182)", containsSeq(BA.toList(bytes), [182]))
    })

    group(s1, "SAssign var-local updates KRecord box", (sg: Suite) => {
      val t = baseContext()
      CG.emitBlockStmt(t.ctx, SVar("n", None, ELit("int", "0")))
      CG.emitBlockStmt(t.ctx, SAssign(EIdent("n"), ELit("int", "1")))
      val bytes = finish(t.cf, t.mb)
      // CHECKCAST = 192 for KRecord
      isTrue(sg, "SAssign var-local: contains CHECKCAST(192)", containsSeq(BA.toList(bytes), [192]))
      // INVOKEVIRTUAL = 182 for set
      isTrue(sg, "SAssign var-local: contains INVOKEVIRTUAL(182)", containsSeq(BA.toList(bytes), [182]))
      // UTF-8 bytes for "set" = [115, 101, 116]
      isTrue(sg, "SAssign var-local: pool contains set utf8",
        containsSeq(BA.toList(bytes), [115, 101, 116]))
    })

    group(s1, "SAssign field-expr updates KRecord field", (sg: Suite) => {
      val t = baseContext()
      // Store a record in a local
      val rec = ERecord(None, [{ name = "x", mut_ = False, value = ELit("int", "0") }])
      CG.emitBlockStmt(t.ctx, SVal("r", None, rec))
      CG.emitBlockStmt(t.ctx, SAssign(EField(EIdent("r"), "x"), ELit("int", "99")))
      val bytes = finish(t.cf, t.mb)
      // CHECKCAST = 192 for KRecord
      isTrue(sg, "SAssign field: contains CHECKCAST(192)", containsSeq(BA.toList(bytes), [192]))
      // INVOKEVIRTUAL = 182 for set
      isTrue(sg, "SAssign field: contains INVOKEVIRTUAL(182)", containsSeq(BA.toList(bytes), [182]))
      // UTF-8 bytes for "set" = [115, 101, 116]
      isTrue(sg, "SAssign field: pool contains set utf8",
        containsSeq(BA.toList(bytes), [115, 101, 116]))
    })

    group(s1, "SFun capturing outer val emits env array", (sg: Suite) => {
      val t = baseContext()
      CG.emitBlockStmt(t.ctx, SVal("x", None, ELit("int", "3")))
      CG.emitBlockStmt(t.ctx, SFun(False, "f", [], [{ name = "y", type_ = None }], ATPrim("Int"), EBinary("+", EIdent("x"), EIdent("y"))))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      // ANEWARRAY = 189 for captured environment object[]
      isTrue(sg, "SFun capture: emits ANEWARRAY(189)", containsSeq(code, [189]))
      // INVOKESPECIAL = 183 for lambda ctor
      isTrue(sg, "SFun capture: emits INVOKESPECIAL(183)", containsSeq(code, [183]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "SFun capture: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "SFun self-recursive emits env self-cell update", (sg: Suite) => {
      val t = baseContext()
      val factBody = EIf(
        EBinary("<=", EIdent("n"), ELit("int", "1")),
        ELit("int", "1"),
        Some(EBinary("*", EIdent("n"), ECall(EIdent("fact"), [EBinary("-", EIdent("n"), ELit("int", "1"))])))
      )
      CG.emitBlockStmt(t.ctx, SFun(False, "fact", [], [{ name = "n", type_ = None }], ATPrim("Int"), factBody))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      // ANEWARRAY = 189 for captured environment object[]
      isTrue(sg, "SFun self-rec: emits ANEWARRAY(189)", containsSeq(code, [189]))
      // AASTORE = 83 used to patch env[self] with the constructed lambda object
      isTrue(sg, "SFun self-rec: emits AASTORE(83)", containsSeq(code, [83]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "SFun self-rec: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "SFun mutual recursion emits env patch stores", (sg: Suite) => {
      val t = baseContext()
      val evenBody = EIf(
        EBinary("==", EIdent("n"), ELit("int", "0")),
        ELit("true", "True"),
        Some(ECall(EIdent("odd"), [EBinary("-", EIdent("n"), ELit("int", "1"))]))
      )
      val oddBody = EIf(
        EBinary("==", EIdent("n"), ELit("int", "0")),
        ELit("false", "False"),
        Some(ECall(EIdent("even"), [EBinary("-", EIdent("n"), ELit("int", "1"))]))
      )
      CG.emitExpr(t.ctx, EBlock({
        stmts = [
          SFun(False, "even", [], [{ name = "n", type_ = None }], ATPrim("Bool"), evenBody),
          SFun(False, "odd", [], [{ name = "n", type_ = None }], ATPrim("Bool"), oddBody)
        ],
        result = ELit("unit", "")
      }))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      // AASTORE = 83 for deferred env slot patching of local-fun references
      isTrue(sg, "SFun mutual: emits AASTORE(83)", containsSeq(code, [83]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "SFun mutual: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "EList empty", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, EList([]))
      // GETSTATIC = 178 must be emitted for KNil.INSTANCE
      eq(sg, "EList empty: opcode[0] is getstatic(178)", codeAt(t.mb, 0), 178)
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EList empty: bytes emitted", BA.length(bytes) > 0)
      // UTF-8 bytes for "KNil" = [75, 78, 105, 108]
      isTrue(sg, "EList empty: pool contains KNil utf8",
        containsSeq(BA.toList(bytes), [75, 78, 105, 108]))
    })

    group(s1, "EList non-empty", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, EList([LElem(ELit("int", "1")), LElem(ELit("int", "2"))]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EList non-empty: bytes emitted", BA.length(bytes) > 0)
      // Must not start with aconstNull (opcode 1)
      isTrue(sg, "EList non-empty: does not start with aconstNull", codeAt(t.mb, 0) != 1)
      // NEW = 187 for KCons
      isTrue(sg, "EList non-empty: contains NEW(187)", containsSeq(BA.toList(bytes), [187]))
      // INVOKESPECIAL = 183 for KCons.<init>
      isTrue(sg, "EList non-empty: contains INVOKESPECIAL(183)",
        containsSeq(BA.toList(bytes), [183]))
    })

    group(s1, "ECons", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, ECons(ELit("int", "1"), EList([])))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "ECons: bytes emitted", BA.length(bytes) > 0)
      // Must not start with aconstNull (opcode 1)
      isTrue(sg, "ECons: does not start with aconstNull", codeAt(t.mb, 0) != 1)
      // INVOKESPECIAL = 183 for KCons.<init>
      isTrue(sg, "ECons: contains INVOKESPECIAL(183)",
        containsSeq(BA.toList(bytes), [183]))
      // UTF-8 bytes for "KCons" = [75, 67, 111, 110, 115]
      isTrue(sg, "ECons: pool contains KCons utf8",
        containsSeq(BA.toList(bytes), [75, 67, 111, 110, 115]))
    })

    group(s1, "ETuple real", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, ETuple([ELit("int", "10"), ELit("int", "20")]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "ETuple real: bytes emitted", BA.length(bytes) > 0)
      // Must not start with aconstNull
      isTrue(sg, "ETuple real: does not start with aconstNull", codeAt(t.mb, 0) != 1)
      // NEW = 187 for KRecord
      isTrue(sg, "ETuple real: contains NEW(187)", containsSeq(BA.toList(bytes), [187]))
      // UTF-8 bytes for "0" (positional field key) = [48]
      isTrue(sg, "ETuple real: pool contains field-key 0",
        containsSeq(BA.toList(bytes), [48]))
      // INVOKEVIRTUAL = 182 for KRecord.set
      isTrue(sg, "ETuple real: contains INVOKEVIRTUAL(182)",
        containsSeq(BA.toList(bytes), [182]))
    })

    group(s1, "ETemplate real", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, ETemplate([TmplLit("x="), TmplExpr(ELit("int", "7"))]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "ETemplate real: bytes emitted", BA.length(bytes) > 0)
      // Must not start with aconstNull
      isTrue(sg, "ETemplate real: does not start with aconstNull", codeAt(t.mb, 0) != 1)
      // NEW = 187 for StringBuilder
      isTrue(sg, "ETemplate real: contains NEW(187)", containsSeq(BA.toList(bytes), [187]))
      // UTF-8 bytes for "StringBuilder" = [83, 116, 114, 105, 110, 103, 66, 117, 105, 108, 100, 101, 114]
      isTrue(sg, "ETemplate real: pool contains StringBuilder utf8",
        containsSeq(BA.toList(bytes), [83, 116, 114, 105, 110, 103, 66, 117, 105, 108, 100, 101, 114]))
      // INVOKEVIRTUAL = 182 for toString
      isTrue(sg, "ETemplate real: contains INVOKEVIRTUAL(182)",
        containsSeq(BA.toList(bytes), [182]))
      // UTF-8 bytes for "toString" = [116, 111, 83, 116, 114, 105, 110, 103]
      isTrue(sg, "ETemplate real: pool contains toString utf8",
        containsSeq(BA.toList(bytes), [116, 111, 83, 116, 114, 105, 110, 103]))
    })

    group(s1, "EPipe forward", (sg: Suite) => {
      val t = baseContext()
      // Set up a module context that knows about fun "double" with arity 1
      val cf2 = CF.newClassFile("test/CodegenExpr", "java/lang/Object", 0x0021)
      val mb2 = CF.cfAddMethod(cf2, "emit", "()Ljava/lang/Object;", 0x0009)
      val opts = CG.emptyJvmCodegenOptions()
      val mctxWithFun = {
        className = "test/CodegenExpr",
        globalNames = Dict.emptyStringDict(),
        globalVarNames = Dict.emptyStringDict(),
        funArities = Dict.insert(Dict.emptyStringDict(), "double", 1),
        adtClassByConstructor = Dict.emptyStringDict(),
        adtConstructorArity = Dict.emptyStringDict(),
        options = opts,
        mut diagnostics = [],
        mut lambdas = [],
        mut lambdaIndex = 0,
        mut lambdaClasses = Dict.emptyStringDict()
      }
      val ctx2 = CG.newCodegenContext(cf2, mb2, mctxWithFun, CG.noTypeInfo)
      CG.emitExpr(ctx2, EPipe("|>", ELit("int", "3"), EIdent("double")))
      val bytes = finish(cf2, mb2)
      isTrue(sg, "EPipe forward: bytes emitted", BA.length(bytes) > 0)
      // Must not start with aconstNull
      isTrue(sg, "EPipe forward: does not start with aconstNull", codeAt(mb2, 0) != 1)
    })

    group(s1, "EWhile: basic loop emits ifeq and goto", (sg: Suite) => {
      // while (True) { } — always-true condition, empty body.
      // Expect: CHECKCAST(192) for Boolean unboxing, IFEQ(153) for exit test,
      //         GOTO(167) for back-edge, GETSTATIC(178) for KUnit result.
      val t = baseContext()
      val emptyBlock = { stmts = [], result = ELit("unit", "") }
      CG.emitExpr(t.ctx, EWhile(ELit("true", "True"), emptyBlock))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      isTrue(sg, "EWhile: emits ifeq opcode (153)",  containsSeq(code, [153]))
      isTrue(sg, "EWhile: emits goto opcode (167)",  containsSeq(code, [167]))
      isTrue(sg, "EWhile: emits getstatic (178) for KUnit", containsSeq(code, [178]))
      // Must not push aconstNull (1) as the result
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EWhile: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "EWhile: SBreak exits loop", (sg: Suite) => {
      // while (True) { break }  — one SBreak inside the body.
      // Expect an extra GOTO (for break) whose target is the exit position.
      val t = baseContext()
      val breakBlock = { stmts = [SBreak], result = ELit("unit", "") }
      CG.emitExpr(t.ctx, EWhile(ELit("true", "True"), breakBlock))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      // At least two GOTO opcodes: break jump + back-edge.
      val gotoCount = Lst.length(Lst.filter(code, (b: Int) => b == 167))
      isTrue(sg, "EWhile break: at least two GOTO opcodes", gotoCount >= 2)
      // GETSTATIC(178) for KUnit result
      isTrue(sg, "EWhile break: emits getstatic (178) for KUnit", containsSeq(code, [178]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EWhile break: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "EWhile: SContinue jumps to loop head", (sg: Suite) => {
      // while (True) { continue }  — one SContinue inside the body.
      // Expect a GOTO that targets the loop head offset (0).
      val t = baseContext()
      val continueBlock = { stmts = [SContinue], result = ELit("unit", "") }
      CG.emitExpr(t.ctx, EWhile(ELit("true", "True"), continueBlock))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      // GOTO(167) for continue + back-edge; at least two
      val gotoCount = Lst.length(Lst.filter(code, (b: Int) => b == 167))
      isTrue(sg, "EWhile continue: at least two GOTO opcodes", gotoCount >= 2)
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EWhile continue: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "EMatch PWild — no INSTANCEOF emitted", (sg: Suite) => {
      // match (42) { _ => 99 }  — PWild arm: unconditional, no type test
      val t = baseContext()
      val arm = { pattern = PWild, body = ELit("int", "99") }
      CG.emitExpr(t.ctx, EMatch(ELit("int", "42"), [arm]))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      // GOTO(167) emitted for arm end-jump
      isTrue(sg, "EMatch PWild: emits GOTO(167)", containsSeq(code, [167]))
      // No INSTANCEOF(193) — PWild has no type guard
      val hasInstanceof = Lst.length(Lst.filter(code, (b: Int) => b == 193)) > 0
      isTrue(sg, "EMatch PWild: no INSTANCEOF opcode", !hasInstanceof)
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EMatch PWild: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "EMatch PVar — binding stored via ASTORE", (sg: Suite) => {
      // match (42) { x => x }  — PVar arm: bind scrutinee to x, then EIdent("x")
      val t = baseContext()
      val arm = { pattern = PVar("x"), body = ELit("int", "99") }
      CG.emitExpr(t.ctx, EMatch(ELit("int", "42"), [arm]))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      // ASTORE(58) to store scrutinee in dedicated slot
      isTrue(sg, "EMatch PVar: emits ASTORE(58)", containsSeq(code, [58]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EMatch PVar: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "EMatch PLit int — invokestatic equals + ifeq", (sg: Suite) => {
      // match (42) { 1 => 10; _ => 99 }  — PLit arm emits equality check and IFEQ guard
      val t = baseContext()
      val arm1 = { pattern = PLit("int", "1"), body = ELit("int", "10") }
      val arm2 = { pattern = PWild, body = ELit("int", "99") }
      CG.emitExpr(t.ctx, EMatch(ELit("int", "42"), [arm1, arm2]))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      // INVOKESTATIC(184) for Runtime.equals
      isTrue(sg, "EMatch PLit: emits INVOKESTATIC(184)", containsSeq(code, [184]))
      // IFEQ(153) for the equality guard
      isTrue(sg, "EMatch PLit: emits IFEQ(153)", containsSeq(code, [153]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EMatch PLit: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "EMatch PCon None — instanceof KNone + ifeq", (sg: Suite) => {
      // match (e) { None => 0; _ => 1 }  — None arm emits INSTANCEOF(193) test
      val t = baseContext()
      val arm1 = { pattern = PCon("None", []), body = ELit("int", "0") }
      val arm2 = { pattern = PWild, body = ELit("int", "1") }
      CG.emitExpr(t.ctx, EMatch(ELit("unit", ""), [arm1, arm2]))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      isTrue(sg, "EMatch PCon None: emits INSTANCEOF(193)", containsSeq(code, [193]))
      isTrue(sg, "EMatch PCon None: emits IFEQ(153)", containsSeq(code, [153]))
      isTrue(sg, "EMatch PCon None: emits GOTO(167)", containsSeq(code, [167]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EMatch PCon None: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "EMatch PCon Some(v) — instanceof + checkcast + getfield", (sg: Suite) => {
      // match (e) { Some(v) => v; _ => 0 }  — Some arm: INSTANCEOF, CHECKCAST, GETFIELD for value
      val t = baseContext()
      val someField = { name = "value", pattern = Some(PVar("v")) }
      val arm1 = { pattern = PCon("Some", [someField]), body = ELit("int", "0") }
      val arm2 = { pattern = PWild, body = ELit("int", "1") }
      CG.emitExpr(t.ctx, EMatch(ELit("unit", ""), [arm1, arm2]))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      isTrue(sg, "EMatch PCon Some: emits INSTANCEOF(193)", containsSeq(code, [193]))
      isTrue(sg, "EMatch PCon Some: emits IFEQ(153)", containsSeq(code, [153]))
      // CHECKCAST(192) and GETFIELD(180) for extracting value field
      isTrue(sg, "EMatch PCon Some: emits CHECKCAST(192)", containsSeq(code, [192]))
      isTrue(sg, "EMatch PCon Some: emits GETFIELD(180)", containsSeq(code, [180]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EMatch PCon Some: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "EMatch PList [] — instanceof KNil + ifeq", (sg: Suite) => {
      // match ([]) { [] => 0; _ => 1 }  — empty list pattern emits INSTANCEOF for KNil
      val t = baseContext()
      val arm1 = { pattern = PList([], None), body = ELit("int", "0") }
      val arm2 = { pattern = PWild, body = ELit("int", "1") }
      CG.emitExpr(t.ctx, EMatch(ELit("unit", ""), [arm1, arm2]))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      isTrue(sg, "EMatch PList []: emits INSTANCEOF(193)", containsSeq(code, [193]))
      isTrue(sg, "EMatch PList []: emits IFEQ(153)", containsSeq(code, [153]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EMatch PList []: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "EMatch PCons h::t — instanceof KCons + getfields", (sg: Suite) => {
      // match (e) { h :: t => h; _ => 0 }  — PCons arm: INSTANCEOF KCons, CHECKCAST, GETFIELD x2
      val t = baseContext()
      val arm1 = { pattern = PCons(PVar("h"), PVar("t")), body = ELit("int", "0") }
      val arm2 = { pattern = PWild, body = ELit("int", "1") }
      CG.emitExpr(t.ctx, EMatch(ELit("unit", ""), [arm1, arm2]))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      isTrue(sg, "EMatch PCons: emits INSTANCEOF(193)", containsSeq(code, [193]))
      isTrue(sg, "EMatch PCons: emits IFEQ(153)", containsSeq(code, [153]))
      isTrue(sg, "EMatch PCons: emits CHECKCAST(192)", containsSeq(code, [192]))
      isTrue(sg, "EMatch PCons: emits GETFIELD(180)", containsSeq(code, [180]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EMatch PCons: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "EThrow emits ATHROW", (sg: Suite) => {
      // EThrow(ELit("int","1")) should emit NEW KException, DUP_X1, SWAP, INVOKESPECIAL, ATHROW.
      val t = baseContext()
      CG.emitExpr(t.ctx, EThrow(ELit("int", "1")))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      isTrue(sg, "EThrow: emits NEW(187)", containsSeq(code, [187]))
      isTrue(sg, "EThrow: emits DUP_X1(90)", containsSeq(code, [90]))
      isTrue(sg, "EThrow: emits SWAP(95)", containsSeq(code, [95]))
      isTrue(sg, "EThrow: emits INVOKESPECIAL(183)", containsSeq(code, [183]))
      isTrue(sg, "EThrow: emits ATHROW(191)", containsSeq(code, [191]))
    })

    group(s1, "ETry no-throw path returns body value", (sg: Suite) => {
      // try { 42 } catch (e) { _ => 0 }  — no-throw: GOTO jumps past handler; ATHROW at rethrow end.
      val t = baseContext()
      val catchArm = { pattern = PWild, body = ELit("int", "0") }
      val tryBlock = { stmts = [], result = ELit("int", "42") }
      CG.emitExpr(t.ctx, ETry(tryBlock, Some("e"), [catchArm]))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      isTrue(sg, "ETry no-throw: emits GOTO(167)", containsSeq(code, [167]))
      isTrue(sg, "ETry no-throw: emits ATHROW(191)", containsSeq(code, [191]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "ETry no-throw: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "ETry catch arm dispatch — INVOKESTATIC normalizeCaught", (sg: Suite) => {
      // try { 1 } catch { _ => 99 }  — handler always calls normalizeCaught (INVOKESTATIC).
      val t = baseContext()
      val catchArm = { pattern = PWild, body = ELit("int", "99") }
      val tryBlock = { stmts = [], result = ELit("int", "1") }
      CG.emitExpr(t.ctx, ETry(tryBlock, None, [catchArm]))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      isTrue(sg, "ETry catch dispatch: emits INVOKESTATIC(184)", containsSeq(code, [184]))
      isTrue(sg, "ETry catch dispatch: emits CHECKCAST(192)", containsSeq(code, [192]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "ETry catch dispatch: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "ETry nested — two rethrow ATHROW opcodes", (sg: Suite) => {
      // Nested try: inner try as body of outer catch arm.
      // Each ETry emits one rethrow ATHROW so two nested tries yield at least two ATHROW opcodes.
      val t = baseContext()
      val innerArm = { pattern = PWild, body = ELit("int", "0") }
      val innerBlock = { stmts = [], result = ELit("int", "2") }
      val innerTry = ETry(innerBlock, None, [innerArm])
      val outerArm = { pattern = PWild, body = innerTry }
      val outerBlock = { stmts = [], result = ELit("int", "1") }
      CG.emitExpr(t.ctx, ETry(outerBlock, None, [outerArm]))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      val athrowCount = Lst.foldl(code, 0, (acc: Int, b: Int) => if (b == 191) acc + 1 else acc)
      isTrue(sg, "ETry nested: at least two ATHROW(191) opcodes", athrowCount >= 2)
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "ETry nested: class bytes produced", BA.length(bytes) > 0)
    });

    group(s1, "EIs Int emits instanceof + boolean branch", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, EIs(ELit("int", "7"), ATPrim("Int")))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      isTrue(sg, "EIs Int: emits INSTANCEOF(193)", containsSeq(code, [193]))
      isTrue(sg, "EIs Int: emits IFEQ(153)", containsSeq(code, [153]))
      isTrue(sg, "EIs Int: emits GOTO(167)", containsSeq(code, [167]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EIs Int: pool contains Long utf8", containsSeq(BA.toList(bytes), [76, 111, 110, 103]))
      isTrue(sg, "EIs Int: pool contains TRUE utf8", containsSeq(BA.toList(bytes), [84, 82, 85, 69]))
      isTrue(sg, "EIs Int: pool contains FALSE utf8", containsSeq(BA.toList(bytes), [70, 65, 76, 83, 69]))
    })

    group(s1, "EIs Float emits instanceof Double", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, EIs(ELit("float", "3.14"), ATPrim("Float")))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      isTrue(sg, "EIs Float: emits INSTANCEOF(193)", containsSeq(code, [193]))
      isTrue(sg, "EIs Float: emits IFEQ(153)", containsSeq(code, [153]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EIs Float: pool contains Double utf8", containsSeq(BA.toList(bytes), [68, 111, 117, 98, 108, 101]))
    })

    group(s1, "EIs Bool emits instanceof Boolean", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, EIs(ELit("true", "True"), ATPrim("Bool")))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      isTrue(sg, "EIs Bool: emits INSTANCEOF(193)", containsSeq(code, [193]))
      isTrue(sg, "EIs Bool: emits IFEQ(153)", containsSeq(code, [153]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EIs Bool: pool contains Boolean utf8", containsSeq(BA.toList(bytes), [66, 111, 111, 108, 101, 97, 110]))
    })

    group(s1, "EIs String emits instanceof String", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, EIs(ELit("string", "hello"), ATPrim("String")))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      isTrue(sg, "EIs String: emits INSTANCEOF(193)", containsSeq(code, [193]))
      isTrue(sg, "EIs String: emits IFEQ(153)", containsSeq(code, [153]))
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "EIs String: pool contains String utf8", containsSeq(BA.toList(bytes), [83, 116, 114, 105, 110, 103]))
    })

    group(s1, "ENever stays aconstNull placeholder", (sg: Suite) => {
      val t = baseContext()
      CG.emitExpr(t.ctx, ENever)
      eq(sg, "ENever: opcode[0] is aconstNull(1)", codeAt(t.mb, 0), 1)
      val bytes = finish(t.cf, t.mb)
      isTrue(sg, "ENever: class bytes produced", BA.length(bytes) > 0)
    })

    group(s1, "EAwait emits CHECKCAST and INVOKEVIRTUAL", (sg: Suite) => {
      // EAwait(ELit("int","1")) should emit: load expr result, CHECKCAST KTask (192), INVOKEVIRTUAL KTask.get (182).
      val t = baseContext()
      CG.emitExpr(t.ctx, EAwait(ELit("int", "1")))
      val code = Arr.toList(CF.mbGetCode(t.mb))
      isTrue(sg, "EAwait: emits CHECKCAST(192)", containsSeq(code, [192]));
      isTrue(sg, "EAwait: emits INVOKEVIRTUAL(182)", containsSeq(code, [182]))
    })
  })
