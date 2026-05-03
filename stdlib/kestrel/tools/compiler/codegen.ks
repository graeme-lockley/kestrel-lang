//! JVM bytecode code generator for Kestrel AST.
//!
//! Emits classfiles, methods, and supporting metadata from parsed declarations.
//! This module is an internal compiler component used by
//! [`kestrel:tools/compiler/driver`](/docs/kestrel:tools/compiler/driver).

import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"
import * as Str from "kestrel:data/string"
import * as Ast from "kestrel:dev/parser/ast"
import {
  TDFun, TDExternFun, TDExternImport, TDExternType, TDType, TDException, TDExport, TDVal, TDVar, TDSVal, TDSVar,
  EIDecl, TBAdt,
  ELit, EIdent, ECall, EField, EAwait, EUnary, EBinary, ECons, EPipe,
  EIf, EWhile, EMatch, ELambda, ETemplate, EList, ERecord, ETuple,
  EThrow, ETry, EBlock, EIs, ENever,
  LElem, LSpread,
  SVal, SVar, SAssign, SExpr, SFun, SBreak, SContinue,
  TmplLit, TmplExpr,
  PWild, PVar, PLit, PCon, PList, PCons, PTuple,
  ATPrim, ATApp
} from "kestrel:dev/parser/ast"
import * as Arr from "kestrel:data/array"
import * as Ty from "kestrel:dev/typecheck/types"
import * as CF from "kestrel:tools/compiler/classfile"
import * as Op from "kestrel:tools/compiler/opcodes"

// Runtime class constants mirrored from bootstrap codegen.
export val RUNTIME = "kestrel/runtime/KRuntime"
export val KUNIT = "kestrel/runtime/KUnit"
export val KRECORD = "kestrel/runtime/KRecord"
export val KMATH = "kestrel/runtime/KMath"
export val LONG = "java/lang/Long"
export val DOUBLE = "java/lang/Double"
export val BOOLEAN = "java/lang/Boolean"
export val STRING_BUILDER = "java/lang/StringBuilder"
export val KFUNCTION = "kestrel/runtime/KFunction"
export val INTEGER = "java/lang/Integer"
export val KFUNCTION_REF = "kestrel/runtime/KFunctionRef"
export val KNONE = "kestrel/runtime/KNone"
export val KNIL = "kestrel/runtime/KNil"
val KSOME = "kestrel/runtime/KSome"
val KCONS = "kestrel/runtime/KCons"
val KLIST = "kestrel/runtime/KList"
val KERR = "kestrel/runtime/KErr"
val KOK = "kestrel/runtime/KOk"

export type JvmCodegenOptions = {
  importedValVarToClass: Dict<String, String>,
  importedVarNames: Dict<String, Unit>,
  importedFunArities: Dict<String, Int>,
  importedNameToClass: Dict<String, String>,
  importedNameToOriginal: Dict<String, String>,
  importedAdtClasses: Dict<String, (String, Int)>,
  namespaceClasses: Dict<String, String>,
  namespaceAdtConstructors: Dict<String, Dict<String, String>>
}

export type ModuleContext = {
  className: String,
  globalNames: Dict<String, Unit>,
  globalVarNames: Dict<String, Unit>,
  funArities: Dict<String, Int>,
  adtClassByConstructor: Dict<String, String>,
  adtConstructorArity: Dict<String, Int>,
  options: JvmCodegenOptions
}

type LoopBreakLayer = { breakJumps: Array<Int>, loopHead: Int }

export type CodegenContext = {
  cf: CF.ClassFileBuilder,
  mb: CF.MethodBuilder,
  mctx: ModuleContext,
  locals: mut Dict<String, Int>,
  nextLocal: mut Int,
  varLocals: mut Dict<String, Unit>,
  loopBreakStack: mut List<LoopBreakLayer>,
  getInferredType: (Ast.Expr) -> Option<Ty.InternalType>
}

export type JvmCodegenResult = {
  classes: Dict<String, ByteArray>
}

export fun emptyJvmCodegenOptions(): JvmCodegenOptions = {
  importedValVarToClass = Dict.emptyStringDict(),
  importedVarNames = Dict.emptyStringDict(),
  importedFunArities = Dict.emptyStringDict(),
  importedNameToClass = Dict.emptyStringDict(),
  importedNameToOriginal = Dict.emptyStringDict(),
  importedAdtClasses = Dict.emptyStringDict(),
  namespaceClasses = Dict.emptyStringDict(),
  namespaceAdtConstructors = Dict.emptyStringDict()
}

export fun emptyModuleContext(className: String): ModuleContext = {
  className = className,
  globalNames = Dict.emptyStringDict(),
  globalVarNames = Dict.emptyStringDict(),
  funArities = Dict.emptyStringDict(),
  adtClassByConstructor = Dict.emptyStringDict(),
  adtConstructorArity = Dict.emptyStringDict(),
  options = emptyJvmCodegenOptions()
}

export val noTypeInfo: (Ast.Expr) -> Option<Ty.InternalType> = (_: Ast.Expr) => None

export fun newCodegenContext(cf: CF.ClassFileBuilder, mb: CF.MethodBuilder, mctx: ModuleContext, getInferredType: (Ast.Expr) -> Option<Ty.InternalType>): CodegenContext = {
  cf = cf,
  mb = mb,
  mctx = mctx,
  mut locals = Dict.emptyStringDict(),
  mut nextLocal = 0,
  mut varLocals = Dict.emptyStringDict(),
  mut loopBreakStack = [],
  getInferredType = getInferredType
}

fun pushNull(ctx: CodegenContext): Unit = CF.mbEmit1(ctx.mb, Op.JvmOp.aconstNull)

// Decode the inner content of a char literal (quotes already stripped) to a Unicode code point.
// Handles: single char, \n, \r, \t, \\, \', \u{XXXX}.
fun charLiteralCodePoint(raw: String): Int =
  if (Str.length(raw) == 0) 0
  else if (Str.length(raw) == 1) Str.codePointAt(raw, 0)
  else {
    val second = Str.slice(raw, 1, 2)
    if (second == "n") 10
    else if (second == "r") 13
    else if (second == "t") 9
    else if (second == "\\") 92
    else if (second == "'") 39
    else if (second == "u") {
      val hex = Str.dropRight(Str.dropLeft(raw, 3), 1)
      match (Str.parseIntRadix(16, hex)) {
        Some(n) => n
        None => 0
      }
    } else 0
  }

fun pushBoolBoxed(ctx: CodegenContext, b: Bool): Unit = {
  val fld = if (b) "TRUE" else "FALSE"
  val desc = "Ljava/lang/Boolean;"
  val ref = CF.cfFieldref(ctx.cf, BOOLEAN, fld, desc)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, ref)
}

fun pushLongBoxed(ctx: CodegenContext, n: Int): Unit = {
  if (n == 0) CF.mbEmit1(ctx.mb, Op.JvmOp.lconst0)
  else if (n == 1) CF.mbEmit1(ctx.mb, Op.JvmOp.lconst1)
  else {
    CF.mbEmit1(ctx.mb, Op.JvmOp.lconst0)
  };
  val ref = CF.cfMethodref(ctx.cf, LONG, "valueOf", "(J)Ljava/lang/Long;")
  CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, ref)
}

fun emitFunctionRef(ctx: CodegenContext, ownerClass: String, methodName: String, arity: Int): Unit = {
  val classRef = CF.cfClassRef(ctx.cf, ownerClass)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, classRef);
  val strRef = CF.cfString(ctx.cf, methodName)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, strRef);
  val intRef = CF.cfConstantInt(ctx.cf, arity)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, intRef);
  val ofDesc = "(Ljava/lang/Class;Ljava/lang/String;I)L${KFUNCTION_REF};"
  val mref = CF.cfMethodref(ctx.cf, KFUNCTION_REF, "of", ofDesc)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, mref)
}

fun emitVarUnbox(ctx: CodegenContext): Unit = {
  val classRef = CF.cfClassRef(ctx.cf, KRECORD)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, classRef);
  val strRef = CF.cfString(ctx.cf, "0")
  CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, strRef);
  val mref = CF.cfMethodref(ctx.cf, KRECORD, "get", "(Ljava/lang/String;)Ljava/lang/Object;")
  CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, mref)
}

fun emitInitCall(ctx: CodegenContext, targetClass: String): Unit = {
  val initMethodName = Str.append("$", "init")
  val mref = CF.cfMethodref(ctx.cf, targetClass, initMethodName, "()V")
  CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, mref)
}

fun loadLocal(ctx: CodegenContext, name: String): Bool = {
  val idxOpt = Dict.get(ctx.locals, name)
  match (idxOpt) {
    Some(idx) => {
      if (idx <= 3) {
        if (idx == 0) CF.mbEmit1(ctx.mb, Op.JvmOp.aload0)
        else if (idx == 1) CF.mbEmit1(ctx.mb, Op.JvmOp.aload1)
        else if (idx == 2) CF.mbEmit1(ctx.mb, Op.JvmOp.aload2)
        else CF.mbEmit1(ctx.mb, Op.JvmOp.aload3)
      } else {
        CF.mbEmit1b(ctx.mb, Op.JvmOp.aload, idx)
      };
      True
    }
    None => False
  }
}

fun storeLocal(ctx: CodegenContext, idx: Int): Unit = {
  if (idx <= 3) {
    if (idx == 0) CF.mbEmit1(ctx.mb, Op.JvmOp.astore0)
    else if (idx == 1) CF.mbEmit1(ctx.mb, Op.JvmOp.astore1)
    else if (idx == 2) CF.mbEmit1(ctx.mb, Op.JvmOp.astore2)
    else CF.mbEmit1(ctx.mb, Op.JvmOp.astore3)
  } else {
    CF.mbEmit1b(ctx.mb, Op.JvmOp.astore, idx)
  }
}

fun bindLocal(ctx: CodegenContext, name: String): Int = {
  val idx = ctx.nextLocal
  ctx.locals := Dict.insert(ctx.locals, name, idx)
  ctx.nextLocal := idx + 1
  idx
}

fun bindParams(ctx: CodegenContext, params: List<Ast.Param>): Unit =
  match (params) {
    [] => ()
    p :: rest => {
      bindLocal(ctx, p.name)
      bindParams(ctx, rest)
    }
  }

fun objectArgs(n: Int): String =
  if (n <= 0) "" else "Ljava/lang/Object;${objectArgs(n - 1)}"

fun objectMethodDesc(arity: Int): String =
  "(${objectArgs(arity)})Ljava/lang/Object;"

// ---------------------------------------------------------------------------
// Extern JVM dispatch helpers
// ---------------------------------------------------------------------------

fun firstIndexOf(needle: String, s: String): Int =
  match (Str.indexes(needle, s)) {
    [] => -1
    i :: _ => i
  }

// Map a Kestrel declared return type to a JVM return descriptor.
fun externReturnDesc(retType: Ast.AstType): String =
  match (retType) {
    ATPrim(name) =>
      if (name == "Int") "Ljava/lang/Long;"
      else if (name == "Bool") "Ljava/lang/Boolean;"
      else if (name == "String") "Ljava/lang/String;"
      else if (name == "Float") "Ljava/lang/Double;"
      else if (name == "Unit") "V"
      else if (name == "Char") "Ljava/lang/Integer;"
      else "Ljava/lang/Object;"
    ATApp(name, _) =>
      if (name == "Task") "Lkestrel/runtime/KTask;"
      else if (name == "List") "Lkestrel/runtime/KList;"
      else "Ljava/lang/Object;"
    _ => "Ljava/lang/Object;"
  }

// Parse "Owner.Class#method(ArgType,...)" -> owner in JVM internal form (dots -> slashes).
fun parseJvmOwner(raw: String): String = {
  val hashIdx = firstIndexOf("#", raw)
  Str.replace(".", "/", Str.left(raw, hashIdx))
}

// Parse "Owner.Class#method(ArgType,...)" -> method name.
fun parseJvmMethodName(raw: String): String = {
  val hashIdx = firstIndexOf("#", raw)
  val openIdx = firstIndexOf("(", raw)
  Str.sliceRel(hashIdx + 1, openIdx, raw)
}

// Parse "Owner.Class#method(ArgType,...)" -> number of declared arguments.
fun parseJvmArgCount(raw: String): Int = {
  val openIdx = firstIndexOf("(", raw)
  val closeIdx = firstIndexOf(")", raw)
  val argsRaw = Str.sliceRel(openIdx + 1, closeIdx, raw)
  val trimmed = Str.trimLeft(Str.trimRight(argsRaw))
  if (Str.length(trimmed) == 0) 0
  else Lst.length(Str.indexes(",", argsRaw)) + 1
}

// Emit ALOAD instructions for params from `start` (inclusive) to `end` (exclusive).
fun emitLoadArgs(mb: CF.MethodBuilder, start: Int, end: Int): Unit =
  if (start >= end) ()
  else {
    if (start == 0) CF.mbEmit1(mb, Op.JvmOp.aload0)
    else if (start == 1) CF.mbEmit1(mb, Op.JvmOp.aload1)
    else if (start == 2) CF.mbEmit1(mb, Op.JvmOp.aload2)
    else if (start == 3) CF.mbEmit1(mb, Op.JvmOp.aload3)
    else CF.mbEmit1b(mb, Op.JvmOp.aload, start);
    emitLoadArgs(mb, start + 1, end)
  }

// After the JVM call: if return was void (Unit), push KUnit; otherwise leave result on stack.
fun emitExternReturn(cf: CF.ClassFileBuilder, mb: CF.MethodBuilder, retDesc: String): Unit =
  if (retDesc == "V") {
    val kunitRef = CF.cfFieldref(cf, KUNIT, "INSTANCE", "Lkestrel/runtime/KUnit;")
    CF.mbEmit1s(mb, Op.JvmOp.getstatic, kunitRef)
  } else ()

fun emitDefaultCtor(cf: CF.ClassFileBuilder): Unit = {
  val mb = CF.cfAddMethod(cf, "<init>", "()V", Op.Acc.public_)
  CF.mbEmit1(mb, Op.JvmOp.aload0)
  val superInit = CF.cfMethodref(cf, "java/lang/Object", "<init>", "()V")
  CF.mbEmit1s(mb, Op.JvmOp.invokespecial, superInit)
  CF.mbEmit1(mb, Op.JvmOp.return_)
  CF.mbSetMaxs(mb, 1, 1)
}

fun emitTailLoopScaffold(mb: CF.MethodBuilder): Unit = {
  // Reserve a branch target so later stories can patch direct tail calls to this loop head.
  val loopHead = CF.mbLength(mb)
  CF.mbAddBranchTarget(mb, loopHead, None)
}

fun emitMainStub(cf: CF.ClassFileBuilder): Unit = {
  // Temporary shim so runInProcess can invoke compiled modules while full main emission lands.
  val mb = CF.cfAddMethod(cf, "main", "([Ljava/lang/String;)V", Op.Acc.public_ + Op.Acc.static_)
  CF.mbEmit1(mb, Op.JvmOp.return_)
  CF.mbSetMaxs(mb, 0, 1)
}

export fun emitFunDecl(cf: CF.ClassFileBuilder, decl: Ast.FunDecl, mctx: ModuleContext, getInferredType: (Ast.Expr) -> Option<Ty.InternalType>): Unit = {
  val desc = objectMethodDesc(Lst.length(decl.params))
  val mb = CF.cfAddMethod(cf, decl.name, desc, Op.Acc.public_ + Op.Acc.static_)
  val ctx = newCodegenContext(cf, mb, mctx, getInferredType)
  bindParams(ctx, decl.params)
  emitTailLoopScaffold(mb)
  emitExpr(ctx, decl.body)
  CF.mbEmit1(mb, Op.JvmOp.areturn)
  CF.mbSetMaxs(mb, 2, 32)
}

export fun emitExternFun(cf: CF.ClassFileBuilder, decl: Ast.ExternFunDecl): Unit = {
  val arity = Lst.length(decl.params)
  val desc = objectMethodDesc(arity)
  val mb = CF.cfAddMethod(cf, decl.name, desc, Op.Acc.public_ + Op.Acc.static_)
  if (Str.length(decl.jvmDesc) > 0) {
    val owner = parseJvmOwner(decl.jvmDesc)
    val methodName = parseJvmMethodName(decl.jvmDesc)
    val argCount = parseJvmArgCount(decl.jvmDesc)
    val retDesc = externReturnDesc(decl.retType)
    val callDesc = "(${objectArgs(argCount)})${retDesc}"
    if (arity == argCount) {
      emitLoadArgs(mb, 0, arity)
      val mref = CF.cfMethodref(cf, owner, methodName, callDesc)
      CF.mbEmit1s(mb, Op.JvmOp.invokestatic, mref)
    } else {
      CF.mbEmit1(mb, Op.JvmOp.aload0)
      val ownerRef = CF.cfClassRef(cf, owner)
      CF.mbEmit1s(mb, Op.JvmOp.checkcast, ownerRef)
      emitLoadArgs(mb, 1, arity)
      val mref = CF.cfMethodref(cf, owner, methodName, callDesc)
      CF.mbEmit1s(mb, Op.JvmOp.invokevirtual, mref)
    };
    emitExternReturn(cf, mb, retDesc)
  } else
    pushNull(newCodegenContext(cf, mb, emptyModuleContext(""), noTypeInfo));
  CF.mbEmit1(mb, Op.JvmOp.areturn)
  CF.mbSetMaxs(mb, 1, arity + 8)
}

fun emitExternOverride(cf: CF.ClassFileBuilder, ov: Ast.ExternOverride): Unit = {
  val desc = objectMethodDesc(Lst.length(ov.params))
  val mb = CF.cfAddMethod(cf, ov.name, desc, Op.Acc.public_ + Op.Acc.static_)
  pushNull(newCodegenContext(cf, mb, emptyModuleContext(""), noTypeInfo))
  CF.mbEmit1(mb, Op.JvmOp.areturn)
  CF.mbSetMaxs(mb, 1, 8)
}

fun emitExternImportOverrides(cf: CF.ClassFileBuilder, overrides: List<Ast.ExternOverride>): Unit =
  match (overrides) {
    [] => ()
    ov :: rest => { emitExternOverride(cf, ov); emitExternImportOverrides(cf, rest) }
  }

export fun emitVal(cf: CF.ClassFileBuilder, name: String, _expr: Ast.Expr): Unit = {
  CF.cfAddField(cf, name, "Ljava/lang/Object;", Op.Acc.public_ + Op.Acc.static_ + Op.Acc.final_)
  val mb = CF.cfAddMethod(cf, "init$${name}", "()Ljava/lang/Object;", Op.Acc.private_ + Op.Acc.static_)
  CF.mbEmit1(mb, Op.JvmOp.aconstNull)
  CF.mbEmit1(mb, Op.JvmOp.areturn)
  CF.mbSetMaxs(mb, 1, 0)
}

export fun emitVar(cf: CF.ClassFileBuilder, name: String, _expr: Ast.Expr): Unit = {
  CF.cfAddField(cf, name, "Ljava/lang/Object;", Op.Acc.public_ + Op.Acc.static_)
  val mb = CF.cfAddMethod(cf, "init$${name}", "()Ljava/lang/Object;", Op.Acc.private_ + Op.Acc.static_)
  CF.mbEmit1(mb, Op.JvmOp.aconstNull)
  CF.mbEmit1(mb, Op.JvmOp.areturn)
  CF.mbSetMaxs(mb, 1, 0)
}

fun emitCtorClass(moduleName: String, ctor: Ast.CtorDef): (String, ByteArray) = {
  val className = "${moduleName}$${ctor.name}"
  val cf = CF.newClassFile(className, "java/lang/Object", Op.Acc.public_ + Op.Acc.super_)
  emitDefaultCtor(cf);
  if (Lst.isEmpty(ctor.params)) {
    val instanceDesc = "L${className};"
    CF.cfAddField(cf, "INSTANCE", instanceDesc, Op.Acc.public_ + Op.Acc.static_ + Op.Acc.final_);
    val clinit = CF.cfAddMethod(cf, "<clinit>", "()V", Op.Acc.static_)
    val classRef = CF.cfClassRef(cf, className)
    CF.mbEmit1s(clinit, Op.JvmOp.new_, classRef);
    CF.mbEmit1(clinit, Op.JvmOp.dup);
    val initRef = CF.cfMethodref(cf, className, "<init>", "()V")
    CF.mbEmit1s(clinit, Op.JvmOp.invokespecial, initRef);
    val instanceFieldRef = CF.cfFieldref(cf, className, "INSTANCE", instanceDesc)
    CF.mbEmit1s(clinit, Op.JvmOp.putstatic, instanceFieldRef);
    CF.mbEmit1(clinit, Op.JvmOp.return_);
    CF.mbSetMaxs(clinit, 2, 0)
  } else ();
  (className, CF.cfToBytes(cf))
}

fun emitExceptionClass(moduleName: String, exn: Ast.ExceptionDecl): (String, ByteArray) = {
  val className = "${moduleName}$${exn.name}"
  val cf = CF.newClassFile(className, "java/lang/RuntimeException", Op.Acc.public_ + Op.Acc.super_)
  emitDefaultCtor(cf);
  (className, CF.cfToBytes(cf))
}

export fun emitException(moduleName: String, exn: Ast.ExceptionDecl): (String, ByteArray) =
  emitExceptionClass(moduleName, exn)

fun emitTypeCtors(moduleName: String, ctors: List<Ast.CtorDef>, classes: Dict<String, ByteArray>): Dict<String, ByteArray> =
  match (ctors) {
    [] => classes
    c :: rest => {
      val pair = emitCtorClass(moduleName, c)
      emitTypeCtors(moduleName, rest, Dict.insert(classes, pair.0, pair.1))
    }
  }

fun emitDecl(moduleName: String, cf: CF.ClassFileBuilder, mctx: ModuleContext, decl: Ast.TopDecl, classes: Dict<String, ByteArray>, getInferredType: (Ast.Expr) -> Option<Ty.InternalType>): Dict<String, ByteArray> =
  match (decl) {
    TDFun(funDecl) => { emitFunDecl(cf, funDecl, mctx, getInferredType); classes }
    TDExternFun(externDecl) => { emitExternFun(cf, externDecl); classes }
    TDExternImport(eid) => { emitExternImportOverrides(cf, eid.overrides); classes }
    TDExternType(_) => classes
    TDType(typeDecl) => {
      match (typeDecl.body) {
        TBAdt(ctors) => emitTypeCtors(moduleName, ctors, classes)
        _ => classes
      }
    }
    TDException(exnDecl) => {
      val pair = emitException(moduleName, exnDecl)
      Dict.insert(classes, pair.0, pair.1)
    }
    TDExport(inner) => {
      match (inner) {
        EIDecl(d) => emitDecl(moduleName, cf, mctx, d, classes, getInferredType)
        _ => classes
      }
    }
    TDVal(name, _ann, expr) => { emitVal(cf, name, expr); classes }
    TDVar(name, _ann, expr) => { emitVar(cf, name, expr); classes }
    TDSVal(name, _ann, expr) => { emitVal(cf, name, expr); classes }
    TDSVar(name, _ann, expr) => { emitVar(cf, name, expr); classes }
    _ => classes
  }

fun emitDecls(moduleName: String, cf: CF.ClassFileBuilder, mctx: ModuleContext, decls: List<Ast.TopDecl>, classes: Dict<String, ByteArray>, getInferredType: (Ast.Expr) -> Option<Ty.InternalType>): Dict<String, ByteArray> =
  match (decls) {
    [] => classes
    d :: rest => emitDecls(moduleName, cf, mctx, rest, emitDecl(moduleName, cf, mctx, d, classes, getInferredType), getInferredType)
  }

export fun jvmCodegen(mctx: ModuleContext, prog: Ast.Program, getInferredType: (Ast.Expr) -> Option<Ty.InternalType>): JvmCodegenResult = {
  val moduleName = mctx.className
  val cf = CF.newClassFile(moduleName, "java/lang/Object", Op.Acc.public_ + Op.Acc.super_)
  emitDefaultCtor(cf)
  val extraClasses = emitDecls(moduleName, cf, mctx, prog.body, Dict.emptyStringDict(), getInferredType)
  emitMainStub(cf)
  val initMethodName = Str.append("$", "init")
  val initMb = CF.cfAddMethod(cf, initMethodName, "()V", Op.Acc.public_ + Op.Acc.static_)
  CF.mbEmit1(initMb, Op.JvmOp.return_)
  CF.mbSetMaxs(initMb, 0, 0)
  val mainBytes = CF.cfToBytes(cf)
  {
    classes = Dict.insert(extraClasses, moduleName, mainBytes)
  }
}

fun accumDeclForModuleCtx(className: String, mctx: ModuleContext, decl: Ast.TopDecl): ModuleContext =
  match (decl) {
    TDFun(fd) => {
      className = mctx.className,
      globalNames = mctx.globalNames,
      globalVarNames = mctx.globalVarNames,
      funArities = Dict.insert(mctx.funArities, fd.name, Lst.length(fd.params)),
      adtClassByConstructor = mctx.adtClassByConstructor,
      adtConstructorArity = mctx.adtConstructorArity,
      options = mctx.options
    }
    TDExternFun(fd) => {
      className = mctx.className,
      globalNames = mctx.globalNames,
      globalVarNames = mctx.globalVarNames,
      funArities = Dict.insert(mctx.funArities, fd.name, Lst.length(fd.params)),
      adtClassByConstructor = mctx.adtClassByConstructor,
      adtConstructorArity = mctx.adtConstructorArity,
      options = mctx.options
    }
    TDVal(name, _, _) => {
      className = mctx.className,
      globalNames = Dict.insert(mctx.globalNames, name, ()),
      globalVarNames = mctx.globalVarNames,
      funArities = mctx.funArities,
      adtClassByConstructor = mctx.adtClassByConstructor,
      adtConstructorArity = mctx.adtConstructorArity,
      options = mctx.options
    }
    TDVar(name, _, _) => {
      className = mctx.className,
      globalNames = Dict.insert(mctx.globalNames, name, ()),
      globalVarNames = Dict.insert(mctx.globalVarNames, name, ()),
      funArities = mctx.funArities,
      adtClassByConstructor = mctx.adtClassByConstructor,
      adtConstructorArity = mctx.adtConstructorArity,
      options = mctx.options
    }
    TDSVal(name, _, _) => {
      className = mctx.className,
      globalNames = Dict.insert(mctx.globalNames, name, ()),
      globalVarNames = mctx.globalVarNames,
      funArities = mctx.funArities,
      adtClassByConstructor = mctx.adtClassByConstructor,
      adtConstructorArity = mctx.adtConstructorArity,
      options = mctx.options
    }
    TDSVar(name, _, _) => {
      className = mctx.className,
      globalNames = Dict.insert(mctx.globalNames, name, ()),
      globalVarNames = Dict.insert(mctx.globalVarNames, name, ()),
      funArities = mctx.funArities,
      adtClassByConstructor = mctx.adtClassByConstructor,
      adtConstructorArity = mctx.adtConstructorArity,
      options = mctx.options
    }
    TDType(td) => {
      match (td.body) {
        TBAdt(ctors) => {
          val newAbc = Lst.foldl(ctors, mctx.adtClassByConstructor, (acc: Dict<String, String>, c: Ast.CtorDef) =>
            Dict.insert(acc, c.name, "${className}$${c.name}")
          )
          val newAca = Lst.foldl(ctors, mctx.adtConstructorArity, (acc: Dict<String, Int>, c: Ast.CtorDef) =>
            Dict.insert(acc, c.name, Lst.length(c.params))
          )
          {
            className = mctx.className,
            globalNames = mctx.globalNames,
            globalVarNames = mctx.globalVarNames,
            funArities = mctx.funArities,
            adtClassByConstructor = newAbc,
            adtConstructorArity = newAca,
            options = mctx.options
          }
        }
        _ => mctx
      }
    }
    TDException(exn) => {
      val exnClass = "${className}$${exn.name}"
      val exnArity = match (exn.fields) {
        Some(fs) => Lst.length(fs)
        None => 0
      }
      {
        className = mctx.className,
        globalNames = mctx.globalNames,
        globalVarNames = mctx.globalVarNames,
        funArities = mctx.funArities,
        adtClassByConstructor = Dict.insert(mctx.adtClassByConstructor, exn.name, exnClass),
        adtConstructorArity = Dict.insert(mctx.adtConstructorArity, exn.name, exnArity),
        options = mctx.options
      }
    }
    TDExport(inner) => {
      match (inner) {
        EIDecl(d) => accumDeclForModuleCtx(className, mctx, d)
        _ => mctx
      }
    }
    _ => mctx
  }

fun mergeImportedAdtClasses(entries: List<(String, (String, Int))>, adtAcc: Dict<String, String>, arityAcc: Dict<String, Int>): (Dict<String, String>, Dict<String, Int>) =
  match (entries) {
    [] => (adtAcc, arityAcc)
    e :: rest => {
      val localName = e.0
      val classAndArity = e.1
      val adtCls = classAndArity.0
      val adtAr = classAndArity.1
      mergeImportedAdtClasses(rest, Dict.insert(adtAcc, localName, adtCls), Dict.insert(arityAcc, localName, adtAr))
    }
  }

export fun buildModuleContext(className: String, prog: Ast.Program, options: JvmCodegenOptions): ModuleContext = {
  val base = {
    className = className,
    globalNames = Dict.emptyStringDict(),
    globalVarNames = Dict.emptyStringDict(),
    funArities = Dict.emptyStringDict(),
    adtClassByConstructor = Dict.emptyStringDict(),
    adtConstructorArity = Dict.emptyStringDict(),
    options = options
  }
  val afterDecls = Lst.foldl(prog.body, base, (m: ModuleContext, d: Ast.TopDecl) =>
    accumDeclForModuleCtx(className, m, d)
  )
  val importedAdtEntries = Dict.toList(options.importedAdtClasses)
  val adtMerge = mergeImportedAdtClasses(importedAdtEntries, afterDecls.adtClassByConstructor, afterDecls.adtConstructorArity)
  {
    className = afterDecls.className,
    globalNames = afterDecls.globalNames,
    globalVarNames = afterDecls.globalVarNames,
    funArities = afterDecls.funArities,
    adtClassByConstructor = adtMerge.0,
    adtConstructorArity = adtMerge.1,
    options = afterDecls.options
  }
}

// ---------------------------------------------------------------------------
// estimateBodyLocals — conservative count of local slots declared in a loop body.
// Mirrors the TS `estimateBodyLocals` helper: counts Val/Var/Fun stmts and
// pattern-bound variables so the loop-head StackMapFrameState has a wide-enough
// numLocals to satisfy the JVM verifier on back-edge GOTOs.
// ---------------------------------------------------------------------------

fun countPatternVars(p: Ast.Pattern): Int =
  match (p) {
    PWild => 0
    PVar(_) => 1
    PLit(_, _) => 0
    PCon(_, fields) =>
      Lst.foldl(fields, 0, (acc: Int, f: Ast.ConField) =>
        match (f.pattern) {
          Some(pat) => acc + countPatternVars(pat)
          None => acc
        })
    PList(parts, _rest) =>
      Lst.foldl(parts, 0, (acc: Int, pat: Ast.Pattern) => acc + countPatternVars(pat))
    PCons(h, t) => countPatternVars(h) + countPatternVars(t)
    PTuple(parts) =>
      Lst.foldl(parts, 0, (acc: Int, pat: Ast.Pattern) => acc + countPatternVars(pat))
  }

fun countStmtLocals(stmts: List<Ast.Stmt>): Int =
  match (stmts) {
    [] => 0
    s :: rest => {
      val here =
        match (s) {
          SVal(_, _, _) => 1
          SVar(_, _, _) => 1
          SFun(_, _, _, _, _, _) => 1
          SExpr(e) => estimateBodyLocals(e)
          SAssign(tgt, rhs) => estimateBodyLocals(tgt) + estimateBodyLocals(rhs)
          SBreak => 0
          SContinue => 0
        }
      here + countStmtLocals(rest)
    }
  }

fun estimateBodyLocals(expr: Ast.Expr): Int =
  match (expr) {
    EBlock(b) => countStmtLocals(b.stmts) + estimateBodyLocals(b.result)
    EIf(_, t, eOpt) => {
      val elseCount =
        match (eOpt) {
          Some(e) => estimateBodyLocals(e)
          None => 0
        }
      estimateBodyLocals(t) + elseCount
    }
    EWhile(_, b) => estimateBodyLocals(EBlock(b))
    EMatch(_, arms) =>
      Lst.foldl(arms, 0, (acc: Int, arm: Ast.Case_) =>
        acc + countPatternVars(arm.pattern) + estimateBodyLocals(arm.body))
    ETry(b, _, arms) => {
      val bodyCount = estimateBodyLocals(EBlock(b))
      val armCount = Lst.foldl(arms, 0, (acc: Int, arm: Ast.Case_) =>
        acc + countPatternVars(arm.pattern) + estimateBodyLocals(arm.body))
      bodyCount + armCount
    }
    _ => 0
  }

fun backpatchBreakJumps(code: Array<Int>, jumps: List<Int>, exitPos: Int): Unit =
  match (jumps) {
    [] => ()
    j :: rest => { patchShort(code, j + 1, exitPos - j); backpatchBreakJumps(code, rest, exitPos) }
  }

fun patchShort(code: Array<Int>, pos: Int, offset: Int): Unit = {
  val u = if (offset >= 0) offset else offset + 65536
  Arr.set(code, pos, u / 256);
  Arr.set(code, pos + 1, u % 256)
}

fun jvmMangleName(op: String): String = {
  val d = "$"
  if (op == "<") "${d}less"
  else if (op == ">") "${d}greater"
  else if (op == "<=") "${d}less${d}eq"
  else if (op == ">=") "${d}greater${d}eq"
  else op
}

fun primNameFromType(t: Option<Ty.InternalType>): String =
  match (t) {
    Some(typ) =>
      match (Ty.primName(typ)) {
        Some(name) =>
          if (name == "Int") "Int"
          else if (name == "Float") "Float"
          else if (name == "Char" | name == "Rune") "Char"
          else "Other"
        None => "Other"
      }
    None => "Other"
  }

fun emitShortCircuitAnd(ctx: CodegenContext, left: Ast.Expr, right: Ast.Expr): Unit = {
  emitExpr(ctx, left)
  val boolClassRef = CF.cfClassRef(ctx.cf, BOOLEAN)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, boolClassRef)
  val bvMref = CF.cfMethodref(ctx.cf, BOOLEAN, "booleanValue", "()Z")
  CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, bvMref)
  val code = CF.mbGetCode(ctx.mb)
  val ifeqStart = CF.mbLength(ctx.mb)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
  CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), None)
  emitExpr(ctx, right)
  val gotoEnd = CF.mbLength(ctx.mb)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.goto_, 0)
  val pushFalse = CF.mbLength(ctx.mb)
  CF.mbAddBranchTarget(ctx.mb, pushFalse, None)
  pushBoolBoxed(ctx, False)
  val afterAnd = CF.mbLength(ctx.mb)
  CF.mbAddBranchTarget(ctx.mb, afterAnd, None)
  patchShort(code, ifeqStart + 1, pushFalse - ifeqStart)
  patchShort(code, gotoEnd + 1, afterAnd - gotoEnd)
}

fun emitShortCircuitOr(ctx: CodegenContext, left: Ast.Expr, right: Ast.Expr): Unit = {
  emitExpr(ctx, left)
  val boolClassRef = CF.cfClassRef(ctx.cf, BOOLEAN)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, boolClassRef)
  val bvMref = CF.cfMethodref(ctx.cf, BOOLEAN, "booleanValue", "()Z")
  CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, bvMref)
  val code = CF.mbGetCode(ctx.mb)
  val ifeqStart = CF.mbLength(ctx.mb)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
  CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), None)
  pushBoolBoxed(ctx, True)
  val gotoSkip = CF.mbLength(ctx.mb)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.goto_, 0)
  val rightStart = CF.mbLength(ctx.mb)
  CF.mbAddBranchTarget(ctx.mb, rightStart, None)
  emitExpr(ctx, right)
  val afterOr = CF.mbLength(ctx.mb)
  CF.mbAddBranchTarget(ctx.mb, afterOr, None)
  patchShort(code, ifeqStart + 1, rightStart - ifeqStart)
  patchShort(code, gotoSkip + 1, afterOr - gotoSkip)
}

fun emitEqExpr(ctx: CodegenContext, left: Ast.Expr, right: Ast.Expr): Unit = {
  emitExpr(ctx, left)
  emitExpr(ctx, right)
  val mref = CF.cfMethodref(ctx.cf, RUNTIME, "equals", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;")
  CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, mref)
}

fun emitNeExpr(ctx: CodegenContext, left: Ast.Expr, right: Ast.Expr): Unit = {
  emitEqExpr(ctx, left, right)
  val boolClassRef = CF.cfClassRef(ctx.cf, BOOLEAN)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, boolClassRef)
  val bvMref = CF.cfMethodref(ctx.cf, BOOLEAN, "booleanValue", "()Z")
  CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, bvMref)
  val code = CF.mbGetCode(ctx.mb)
  val ifneStart = CF.mbLength(ctx.mb)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.ifne, 0)
  CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), None)
  pushBoolBoxed(ctx, True)
  val gotoEnd = CF.mbLength(ctx.mb)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.goto_, 0)
  val pushFalse = CF.mbLength(ctx.mb)
  CF.mbAddBranchTarget(ctx.mb, pushFalse, None)
  pushBoolBoxed(ctx, False)
  val afterNe = CF.mbLength(ctx.mb)
  CF.mbAddBranchTarget(ctx.mb, afterNe, None)
  patchShort(code, ifneStart + 1, pushFalse - ifneStart)
  patchShort(code, gotoEnd + 1, afterNe - gotoEnd)
}

fun emitUnaryExpr(ctx: CodegenContext, op: String, e: Ast.Expr): Unit =
  if (op == "!") {
    emitExpr(ctx, e)
    val boolFieldref = CF.cfFieldref(ctx.cf, BOOLEAN, "TRUE", "Ljava/lang/Boolean;")
    CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, boolFieldref)
    val code = CF.mbGetCode(ctx.mb)
    val ifAcmpeqStart = CF.mbLength(ctx.mb)
    CF.mbEmit1s(ctx.mb, Op.JvmOp.ifAcmpeq, 0)
    CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), None)
    pushBoolBoxed(ctx, True)
    val gotoEnd = CF.mbLength(ctx.mb)
    CF.mbEmit1s(ctx.mb, Op.JvmOp.goto_, 0)
    val falseLabel = CF.mbLength(ctx.mb)
    CF.mbAddBranchTarget(ctx.mb, falseLabel, None)
    pushBoolBoxed(ctx, False)
    val afterNot = CF.mbLength(ctx.mb)
    CF.mbAddBranchTarget(ctx.mb, afterNot, None)
    patchShort(code, ifAcmpeqStart + 1, falseLabel - ifAcmpeqStart)
    patchShort(code, gotoEnd + 1, afterNot - gotoEnd)
  } else if (op == "-") {
    val prim = primNameFromType(ctx.getInferredType(e))
    if (prim == "Float") {
      val zeroIdx = CF.cfConstantDouble(ctx.cf, 0.0)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.ldc2W, zeroIdx)
      val dblRef = CF.cfMethodref(ctx.cf, DOUBLE, "valueOf", "(D)Ljava/lang/Double;")
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, dblRef)
      emitExpr(ctx, e)
      val doubleClassRef = CF.cfClassRef(ctx.cf, DOUBLE)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, doubleClassRef)
      val mref = CF.cfMethodref(ctx.cf, KMATH, "subFloat", "(Ljava/lang/Double;Ljava/lang/Double;)Ljava/lang/Double;")
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, mref)
    } else {
      pushLongBoxed(ctx, 0)
      emitExpr(ctx, e)
      val longClassRef = CF.cfClassRef(ctx.cf, LONG)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, longClassRef)
      val mref = CF.cfMethodref(ctx.cf, KMATH, "sub", "(Ljava/lang/Long;Ljava/lang/Long;)Ljava/lang/Long;")
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, mref)
    }
  } else
    emitExpr(ctx, e)

fun emitBinaryExpr(ctx: CodegenContext, op: String, left: Ast.Expr, right: Ast.Expr): Unit =
  if (op == "&") emitShortCircuitAnd(ctx, left, right)
  else if (op == "|") emitShortCircuitOr(ctx, left, right)
  else if (op == "==") emitEqExpr(ctx, left, right)
  else if (op == "!=") emitNeExpr(ctx, left, right)
  else if (op == "++") {
    emitExpr(ctx, left)
    emitExpr(ctx, right)
    val mref = CF.cfMethodref(ctx.cf, RUNTIME, "concat", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/String;")
    CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, mref)
  } else {
    val leftPrim = primNameFromType(ctx.getInferredType(left))
    val rightPrim = primNameFromType(ctx.getInferredType(right))
    val isInt = leftPrim == "Int" & rightPrim == "Int"
    val isFloat = (leftPrim == "Float") | (rightPrim == "Float")
    emitExpr(ctx, left)
    if (isInt) {
      val longRef = CF.cfClassRef(ctx.cf, LONG)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, longRef)
    } else if (isFloat) {
      val dblRef = CF.cfClassRef(ctx.cf, DOUBLE)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, dblRef)
    } else ()
    emitExpr(ctx, right)
    if (isInt) {
      val longRef = CF.cfClassRef(ctx.cf, LONG)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, longRef)
    } else if (isFloat) {
      val dblRef = CF.cfClassRef(ctx.cf, DOUBLE)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, dblRef)
    } else ()
    if (op == "<" | op == ">" | op == "<=" | op == ">=") {
      if (isInt) {
        val mangledOp = jvmMangleName(op)
        val mref = CF.cfMethodref(ctx.cf, KMATH, mangledOp, "(Ljava/lang/Long;Ljava/lang/Long;)Ljava/lang/Boolean;")
        CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, mref)
      } else if (isFloat) {
        val mangledOp = "${jvmMangleName(op)}Float"
        val mref = CF.cfMethodref(ctx.cf, KMATH, mangledOp, "(Ljava/lang/Double;Ljava/lang/Double;)Ljava/lang/Boolean;")
        CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, mref)
      } else {
        CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
        CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
        pushBoolBoxed(ctx, False)
      }
    } else {
      if (isInt) {
        val kop =
          if (op == "+") "add"
          else if (op == "-") "sub"
          else if (op == "*") "mul"
          else if (op == "/") "div"
          else if (op == "%") "mod"
          else "pow"
        val mref = CF.cfMethodref(ctx.cf, KMATH, kop, "(Ljava/lang/Long;Ljava/lang/Long;)Ljava/lang/Long;")
        CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, mref)
      } else if (isFloat) {
        val kop =
          if (op == "+") "addFloat"
          else if (op == "-") "subFloat"
          else if (op == "*") "mulFloat"
          else if (op == "/") "divFloat"
          else "powFloat"
        val mref = CF.cfMethodref(ctx.cf, KMATH, kop, "(Ljava/lang/Double;Ljava/lang/Double;)Ljava/lang/Double;")
        CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, mref)
      } else {
        CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
        CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
        pushNull(ctx)
      }
    }
  }

// Load a local variable by slot index (mirrors storeLocal).
fun loadLocalSlot(ctx: CodegenContext, idx: Int): Unit =
  if (idx == 0) CF.mbEmit1(ctx.mb, Op.JvmOp.aload0)
  else if (idx == 1) CF.mbEmit1(ctx.mb, Op.JvmOp.aload1)
  else if (idx == 2) CF.mbEmit1(ctx.mb, Op.JvmOp.aload2)
  else if (idx == 3) CF.mbEmit1(ctx.mb, Op.JvmOp.aload3)
  else CF.mbEmit1b(ctx.mb, Op.JvmOp.aload, idx)

// Emit call arguments leaving every value on the stack (unlike emitExprList which discards intermediates).
fun emitCallArgs(ctx: CodegenContext, xs: List<Ast.Expr>): Unit =
  match (xs) {
    [] => ()
    x :: rest => { emitExpr(ctx, x); emitCallArgs(ctx, rest) }
  }

// Store n stack values (top = arg_{n-1}) right-to-left so slot (base+i) = arg_i.
fun storeArgsRtoL(ctx: CodegenContext, base: Int, i: Int): Unit =
  if (i < 0) ()
  else { storeLocal(ctx, base + i); storeArgsRtoL(ctx, base, i - 1) }

// Fill Object[] at top of stack: array[i] = ALOAD slot(base+i), for i in [0, n).
fun fillArgsToArray(ctx: CodegenContext, base: Int, i: Int, n: Int): Unit =
  if (i >= n) ()
  else {
    CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
    val iIdx = CF.cfConstantInt(ctx.cf, i)
    CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, iIdx)
    loadLocalSlot(ctx, base + i)
    CF.mbEmit1(ctx.mb, Op.JvmOp.aastore)
    fillArgsToArray(ctx, base, i + 1, n)
  }

// Indirect call fallback: emit callee, build Object[], INVOKEINTERFACE KFunction.apply.
fun emitCallIndirect(ctx: CodegenContext, callee: Ast.Expr, args: List<Ast.Expr>): Unit = {
  val n = Lst.length(args)
  val calleeSlot = ctx.nextLocal
  val argBase = calleeSlot + 1
  ctx.nextLocal := argBase + n
  emitExpr(ctx, callee)
  storeLocal(ctx, calleeSlot)
  emitCallArgs(ctx, args)
  storeArgsRtoL(ctx, argBase, n - 1)
  val nIdx = CF.cfConstantInt(ctx.cf, n)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, nIdx)
  val objRef = CF.cfClassRef(ctx.cf, "java/lang/Object")
  CF.mbEmit1s(ctx.mb, Op.JvmOp.anewarray, objRef)
  fillArgsToArray(ctx, argBase, 0, n)
  loadLocalSlot(ctx, calleeSlot)
  val kfRef = CF.cfClassRef(ctx.cf, KFUNCTION)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, kfRef)
  CF.mbEmit1(ctx.mb, Op.JvmOp.swap)
  val applyIdx = CF.cfIfaceMethodref(ctx.cf, KFUNCTION, "apply", "([Ljava/lang/Object;)Ljava/lang/Object;")
  CF.mbEmit1(ctx.mb, Op.JvmOp.invokeinterface)
  CF.mbPushShort(ctx.mb, applyIdx)
  CF.mbPushByte(ctx.mb, 2)
  CF.mbPushByte(ctx.mb, 0)
}

fun emitRecordFields(ctx: CodegenContext, fields: List<Ast.RecField>): Unit =
  match (fields) {
    [] => ()
    f :: rest => {
      CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfString(ctx.cf, f.name))
      emitExpr(ctx, f.value)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, KRECORD, "set", "(Ljava/lang/String;Ljava/lang/Object;)V"))
      emitRecordFields(ctx, rest)
    }
  }

fun emitExprList(ctx: CodegenContext, xs: List<Ast.Expr>): Unit =
  match (xs) {
    [] => ()
    x :: rest => {
      emitExpr(ctx, x)
      if (!Lst.isEmpty(rest)) CF.mbEmit1(ctx.mb, Op.JvmOp.pop) else ()
      emitExprList(ctx, rest)
    }
  }

fun emitListElems(ctx: CodegenContext, xs: List<Ast.ListElem>): Unit =
  match (xs) {
    [] => ()
    x :: rest => {
      match (x) {
        LElem(e) => { emitExpr(ctx, e); CF.mbEmit1(ctx.mb, Op.JvmOp.pop) }
        LSpread(e) => { emitExpr(ctx, e); CF.mbEmit1(ctx.mb, Op.JvmOp.pop) }
      }
      emitListElems(ctx, rest)
    }
  }

fun emitTemplateParts(ctx: CodegenContext, parts: List<Ast.TmplPart>): Unit =
  match (parts) {
    [] => ()
    p :: rest => {
      match (p) {
        TmplLit(_) => ()
        TmplExpr(e) => { emitExpr(ctx, e); CF.mbEmit1(ctx.mb, Op.JvmOp.pop) }
      }
      emitTemplateParts(ctx, rest)
    }
  }

// Build a KList from a reversed list of elements (right-to-left fold).
// listTemp holds the accumulated list; elemTemp is a scratch slot.
fun emitListBuild(ctx: CodegenContext, elems: List<Ast.ListElem>, listTemp: Int, elemTemp: Int): Unit =
  match (elems) {
    [] => ()
    LElem(e) :: rest => {
      emitExpr(ctx, e)
      storeLocal(ctx, elemTemp)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, KCONS))
      CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
      loadLocalSlot(ctx, elemTemp)
      loadLocalSlot(ctx, listTemp)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KLIST))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, CF.cfMethodref(ctx.cf, KCONS, "<init>", "(Ljava/lang/Object;Lkestrel/runtime/KList;)V"))
      storeLocal(ctx, listTemp)
      emitListBuild(ctx, rest, listTemp, elemTemp)
    }
    LSpread(e) :: rest => {
      emitExpr(ctx, e)
      storeLocal(ctx, elemTemp)
      loadLocalSlot(ctx, elemTemp)
      loadLocalSlot(ctx, listTemp)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, CF.cfMethodref(ctx.cf, RUNTIME, "listPrependAll", "(Ljava/lang/Object;Ljava/lang/Object;)Lkestrel/runtime/KList;"))
      storeLocal(ctx, listTemp)
      emitListBuild(ctx, rest, listTemp, elemTemp)
    }
  }

// Emit KRecord field-set instructions for tuple elements, starting at index i.
fun emitTupleElems(ctx: CodegenContext, xs: List<Ast.Expr>, i: Int): Unit =
  match (xs) {
    [] => ()
    x :: rest => {
      CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfString(ctx.cf, Str.fromInt(i)))
      emitExpr(ctx, x)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, KRECORD, "set", "(Ljava/lang/String;Ljava/lang/Object;)V"))
      emitTupleElems(ctx, rest, i + 1)
    }
  }

// Emit StringBuilder append calls for each template part.
fun emitTemplateBuild(ctx: CodegenContext, parts: List<Ast.TmplPart>): Unit =
  match (parts) {
    [] => ()
    TmplLit(s) :: rest => {
      CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfString(ctx.cf, s))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, STRING_BUILDER, "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;"))
      emitTemplateBuild(ctx, rest)
    }
    TmplExpr(e) :: rest => {
      emitExpr(ctx, e)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, CF.cfMethodref(ctx.cf, RUNTIME, "formatOne", "(Ljava/lang/Object;)Ljava/lang/String;"))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, STRING_BUILDER, "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;"))
      emitTemplateBuild(ctx, rest)
    }
  }

export fun emitBlockStmt(ctx: CodegenContext, stmt: Ast.Stmt): Unit =
  match (stmt) {
    SVal(name, _ann, e) => {
      emitExpr(ctx, e)
      val idx = bindLocal(ctx, name)
      storeLocal(ctx, idx)
    }
    SVar(name, _ann, e) => {
      val tempSlot = ctx.nextLocal
      ctx.nextLocal := tempSlot + 1
      emitExpr(ctx, e)
      storeLocal(ctx, tempSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, KRECORD))
      CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, CF.cfMethodref(ctx.cf, KRECORD, "<init>", "()V"))
      CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfString(ctx.cf, "0"))
      loadLocalSlot(ctx, tempSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, KRECORD, "set", "(Ljava/lang/String;Ljava/lang/Object;)V"))
      val idx = bindLocal(ctx, name)
      storeLocal(ctx, idx)
      ctx.varLocals := Dict.insert(ctx.varLocals, name, ())
    }
    SAssign(target, rhs) => {
      match (target) {
        EIdent(name) => {
          val slotOpt = Dict.get(ctx.locals, name)
          match (slotOpt) {
            Some(slot) => {
              if (Dict.member(ctx.varLocals, name)) {
                val tempSlot = ctx.nextLocal
                ctx.nextLocal := tempSlot + 1
                emitExpr(ctx, rhs)
                storeLocal(ctx, tempSlot)
                loadLocalSlot(ctx, slot)
                CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KRECORD))
                CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfString(ctx.cf, "0"))
                loadLocalSlot(ctx, tempSlot)
                CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, KRECORD, "set", "(Ljava/lang/String;Ljava/lang/Object;)V"))
              } else {
                emitExpr(ctx, rhs)
                storeLocal(ctx, slot)
              }
            }
            None => {
              emitExpr(ctx, rhs)
              CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
            }
          }
        }
        EField(obj, field) => {
          val tempSlot = ctx.nextLocal
          ctx.nextLocal := tempSlot + 1
          emitExpr(ctx, rhs)
          storeLocal(ctx, tempSlot)
          emitExpr(ctx, obj)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KRECORD))
          CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfString(ctx.cf, field))
          loadLocalSlot(ctx, tempSlot)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, KRECORD, "set", "(Ljava/lang/String;Ljava/lang/Object;)V"))
        }
        _ => {
          emitExpr(ctx, rhs)
          CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
        }
      }
    }
    SExpr(e) => {
      emitExpr(ctx, e)
      CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
    }
    SFun(_async, _name, _tp, _params, _rt, _body) => ()
    SBreak => {
      match (ctx.loopBreakStack) {
        layer :: _ => {
          val gotoPos = CF.mbLength(ctx.mb)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.goto_, 0)                        // placeholder; backpatched at loop exit
          Arr.push(layer.breakJumps, gotoPos)
        }
        [] => ()  // typechecker ensures break is always inside a loop
      }
    }
    SContinue => {
      match (ctx.loopBreakStack) {
        layer :: _ => {
          val code = CF.mbGetCode(ctx.mb)
          val gotoPos = CF.mbLength(ctx.mb)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.goto_, 0)                        // placeholder; patched immediately
          patchShort(code, gotoPos + 1, layer.loopHead - gotoPos)
        }
        [] => ()  // typechecker ensures continue is always inside a loop
      }
    }
  }

fun emitBlockStmts(ctx: CodegenContext, stmts: List<Ast.Stmt>): Unit =
  match (stmts) {
    [] => ()
    s :: rest => { emitBlockStmt(ctx, s); emitBlockStmts(ctx, rest) }
  }

export fun emitPattern(ctx: CodegenContext, pattern: Ast.Pattern): Unit =
  match (pattern) {
    PWild => ()
    PVar(_) => ()
    PLit(_, _) => ()
    PCon(_, fields) => {
      val pats = Lst.filterMap(fields, (f: Ast.ConField) => f.pattern)
      emitPatternList(ctx, pats)
    }
    PList(parts, _rest) => emitPatternList(ctx, parts)
    PCons(h, t) => { emitPattern(ctx, h); emitPattern(ctx, t) }
    PTuple(parts) => emitPatternList(ctx, parts)
  }

fun emitPatternList(ctx: CodegenContext, ps: List<Ast.Pattern>): Unit =
  match (ps) {
    [] => ()
    p :: rest => { emitPattern(ctx, p); emitPatternList(ctx, rest) }
  }

export fun emitMatchArm(ctx: CodegenContext, arm: Ast.Case_): Unit = {
  emitPattern(ctx, arm.pattern)
  emitExpr(ctx, arm.body)
}

fun emitMatchArms(ctx: CodegenContext, arms: List<Ast.Case_>): Unit =
  match (arms) {
    [] => pushNull(ctx)
    a :: [] => emitMatchArm(ctx, a)
    a :: rest => {
      emitMatchArm(ctx, a)
      CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
      emitMatchArms(ctx, rest)
    }
  }

// True if the then-arm of an if expression falls through with a value on the JVM stack.
// False when the arm transfers control unconditionally (ENever, or block ending with break/continue),
// which means emitting ASTORE/GOTO after it would produce unreachable bytecode the verifier rejects.
fun thenArmPushesValue(expr: Ast.Expr): Bool =
  match (expr) {
    ENever => False
    EBlock(block) =>
      match (Lst.last(block.stmts)) {
        Some(SBreak) => False
        Some(SContinue) => False
        None => thenArmPushesValue(block.result)
        _ => True
      }
    _ => True
  }

export fun emitExpr(ctx: CodegenContext, expr: Ast.Expr): Unit =
  match (expr) {
    ELit(kind, raw) => {
      if (kind == "int") {
        match (Str.toInt(raw)) {
          Some(n) => pushLongBoxed(ctx, n)
          None => pushLongBoxed(ctx, 0)
        }
      } else if (kind == "bool" | kind == "true") {
        pushBoolBoxed(ctx, True)
      } else if (kind == "false") {
        pushBoolBoxed(ctx, False)
      } else if (kind == "float") {
        val d = Str.toFloat(raw)
        val idx = CF.cfConstantDouble(ctx.cf, d)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.ldc2W, idx)
        val ref = CF.cfMethodref(ctx.cf, DOUBLE, "valueOf", "(D)Ljava/lang/Double;")
        CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, ref)
      } else if (kind == "string") {
        val idx = CF.cfString(ctx.cf, raw)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, idx)
      } else if (kind == "char") {
        val cp = charLiteralCodePoint(raw)
        val idx = CF.cfConstantInt(ctx.cf, cp)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, idx)
        val ref = CF.cfMethodref(ctx.cf, INTEGER, "valueOf", "(I)Ljava/lang/Integer;")
        CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, ref)
      } else if (kind == "unit") {
        val kunitRef = CF.cfFieldref(ctx.cf, KUNIT, "INSTANCE", "Lkestrel/runtime/KUnit;")
        CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, kunitRef)
      } else {
        pushNull(ctx)
      }
    }
    EIdent(name) => {
      if (loadLocal(ctx, name)) {
        if (Dict.member(ctx.varLocals, name)) emitVarUnbox(ctx) else ()
      }
      else {
        val mctx = ctx.mctx
        if (Dict.member(mctx.globalNames, name)) {
          val fref = CF.cfFieldref(ctx.cf, mctx.className, name, "Ljava/lang/Object;")
          CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, fref);
          if (Dict.member(mctx.globalVarNames, name)) emitVarUnbox(ctx) else ()
        }
        else if (Dict.member(mctx.funArities, name)) {
          val arity = Opt.getOrElse(Dict.get(mctx.funArities, name), 0)
          emitFunctionRef(ctx, mctx.className, name, arity)
        }
        else {
          val importedValClass = Dict.get(mctx.options.importedValVarToClass, name)
          match (importedValClass) {
            Some(valCls) => {
              val origName = Opt.getOrElse(Dict.get(mctx.options.importedNameToOriginal, name), name)
              emitInitCall(ctx, valCls);
              val fref = CF.cfFieldref(ctx.cf, valCls, origName, "Ljava/lang/Object;")
              CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, fref);
              if (Dict.member(mctx.options.importedVarNames, name)) emitVarUnbox(ctx) else ()
            }
            None => {
              val importedFunClass = Dict.get(mctx.options.importedNameToClass, name)
              match (importedFunClass) {
                Some(funCls) => {
                  val importedFunArity = Dict.get(mctx.options.importedFunArities, name)
                  match (importedFunArity) {
                    Some(funArity) => {
                      val origName = Opt.getOrElse(Dict.get(mctx.options.importedNameToOriginal, name), name)
                      emitInitCall(ctx, funCls);
                      emitFunctionRef(ctx, funCls, origName, funArity)
                    }
                    None => pushNull(ctx)
                  }
                }
                None => {
                  if (name == "None") {
                    val fref = CF.cfFieldref(ctx.cf, KNONE, "INSTANCE", "Lkestrel/runtime/KNone;")
                    CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, fref)
                  }
                  else if (name == "Nil" | name == "[]") {
                    val fref = CF.cfFieldref(ctx.cf, KNIL, "INSTANCE", "Lkestrel/runtime/KNil;")
                    CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, fref)
                  }
                  else {
                    val adtClassOpt = Dict.get(mctx.adtClassByConstructor, name)
                    match (adtClassOpt) {
                      Some(adtCls) => {
                        val adtArity = Opt.getOrElse(Dict.get(mctx.adtConstructorArity, name), 1)
                        if (adtArity == 0) {
                          val fref = CF.cfFieldref(ctx.cf, adtCls, "INSTANCE", "L${adtCls};")
                          CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, fref)
                        } else pushNull(ctx)
                      }
                      None => pushNull(ctx)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    ECall(fn, args) => {
      val mctx = ctx.mctx
      match (fn) {
        EIdent(name) => {
          if (name == "Some") {
            match (args) {
              a :: [] => {
                CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, KSOME))
                CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
                emitExpr(ctx, a)
                val mref = CF.cfMethodref(ctx.cf, KSOME, "<init>", "(Ljava/lang/Object;)V")
                CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, mref)
              }
              _ => emitCallIndirect(ctx, fn, args)
            }
          } else if (name == "Cons") {
            match (args) {
              h :: t :: [] => {
                val headSlot = ctx.nextLocal
                val tailSlot = headSlot + 1
                ctx.nextLocal := tailSlot + 1
                emitExpr(ctx, h)
                storeLocal(ctx, headSlot)
                emitExpr(ctx, t)
                storeLocal(ctx, tailSlot)
                CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, KCONS))
                CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
                loadLocalSlot(ctx, headSlot)
                loadLocalSlot(ctx, tailSlot)
                val mref = CF.cfMethodref(ctx.cf, KCONS, "<init>", "(Ljava/lang/Object;L${KLIST};)V")
                CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, mref)
              }
              _ => emitCallIndirect(ctx, fn, args)
            }
          } else if (name == "Err") {
            match (args) {
              a :: [] => {
                CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, KERR))
                CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
                emitExpr(ctx, a)
                val mref = CF.cfMethodref(ctx.cf, KERR, "<init>", "(Ljava/lang/Object;)V")
                CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, mref)
              }
              _ => emitCallIndirect(ctx, fn, args)
            }
          } else if (name == "Ok") {
            match (args) {
              a :: [] => {
                CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, KOK))
                CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
                emitExpr(ctx, a)
                val mref = CF.cfMethodref(ctx.cf, KOK, "<init>", "(Ljava/lang/Object;)V")
                CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, mref)
              }
              _ => emitCallIndirect(ctx, fn, args)
            }
          } else {
            val adtCtorClassOpt = Dict.get(mctx.adtClassByConstructor, name)
            match (adtCtorClassOpt) {
              Some(adtCls) => {
                val arity = Lst.length(args)
                val expectedArity = Opt.getOrElse(Dict.get(mctx.adtConstructorArity, name), arity)
                if (arity == expectedArity) {
                  CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, adtCls))
                  CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
                  emitCallArgs(ctx, args)
                  val ctorDesc = "(${objectArgs(arity)})V"
                  val mref = CF.cfMethodref(ctx.cf, adtCls, "<init>", ctorDesc)
                  CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, mref)
                } else emitCallIndirect(ctx, fn, args)
              }
              None => {
                if (name == "println" | name == "print") {
                  val runtimeMethod = if (name == "println") "println" else "print"
                  val n = Lst.length(args)
                  val argBase = ctx.nextLocal
                  ctx.nextLocal := argBase + n
                  emitCallArgs(ctx, args)
                  storeArgsRtoL(ctx, argBase, n - 1)
                  val nIdx = CF.cfConstantInt(ctx.cf, n)
                  CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, nIdx)
                  val objRef = CF.cfClassRef(ctx.cf, "java/lang/Object")
                  CF.mbEmit1s(ctx.mb, Op.JvmOp.anewarray, objRef)
                  fillArgsToArray(ctx, argBase, 0, n)
                  val printRef = CF.cfMethodref(ctx.cf, RUNTIME, runtimeMethod, "([Ljava/lang/Object;)V")
                  CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, printRef)
                  val kunitRef = CF.cfFieldref(ctx.cf, KUNIT, "INSTANCE", "Lkestrel/runtime/KUnit;")
                  CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, kunitRef)
                } else if (name == "exit") {
                  match (args) {
                    a :: [] => {
                      emitExpr(ctx, a)
                      val mref = CF.cfMethodref(ctx.cf, RUNTIME, "exit", "(Ljava/lang/Object;)V")
                      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, mref)
                      val kunitRef = CF.cfFieldref(ctx.cf, KUNIT, "INSTANCE", "Lkestrel/runtime/KUnit;")
                      CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, kunitRef)
                    }
                    _ => emitCallIndirect(ctx, fn, args)
                  }
                } else if (name == "concat") {
                  match (args) {
                    a :: b :: [] => {
                      emitExpr(ctx, a)
                      emitExpr(ctx, b)
                      val mref = CF.cfMethodref(ctx.cf, RUNTIME, "concat", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/String;")
                      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, mref)
                    }
                    _ => emitCallIndirect(ctx, fn, args)
                  }
                } else if (Dict.member(mctx.funArities, name)) {
                  val arity = Opt.getOrElse(Dict.get(mctx.funArities, name), 0)
                  emitCallArgs(ctx, args)
                  val desc = objectMethodDesc(arity)
                  val mref = CF.cfMethodref(ctx.cf, mctx.className, jvmMangleName(name), desc)
                  CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, mref)
                } else {
                  val importedClassOpt = Dict.get(mctx.options.importedNameToClass, name)
                  match (importedClassOpt) {
                    Some(cls) => {
                      val origName = Opt.getOrElse(Dict.get(mctx.options.importedNameToOriginal, name), name)
                      val arity = Lst.length(args)
                      emitInitCall(ctx, cls)
                      emitCallArgs(ctx, args)
                      val desc = objectMethodDesc(arity)
                      val mref = CF.cfMethodref(ctx.cf, cls, jvmMangleName(origName), desc)
                      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, mref)
                    }
                    None => emitCallIndirect(ctx, fn, args)
                  }
                }
              }
            }
          }
        }
        EField(obj, method) => {
          match (obj) {
            EIdent(ns) => {
              val nsClassOpt = Dict.get(mctx.options.namespaceClasses, ns)
              match (nsClassOpt) {
                Some(nsClass) => {
                  val nsAdtCtorsOpt = Dict.get(mctx.options.namespaceAdtConstructors, ns)
                  val ctorClassOpt = match (nsAdtCtorsOpt) {
                    Some(ctorMap) => Dict.get(ctorMap, method)
                    None => None
                  }
                  match (ctorClassOpt) {
                    Some(ctorClass) => {
                      if (nsClass != mctx.className) emitInitCall(ctx, nsClass) else ()
                      val arity = Lst.length(args)
                      CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, ctorClass))
                      CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
                      emitCallArgs(ctx, args)
                      val ctorDesc = "(${objectArgs(arity)})V"
                      val mref = CF.cfMethodref(ctx.cf, ctorClass, "<init>", ctorDesc)
                      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, mref)
                    }
                    None => {
                      if (nsClass != mctx.className) emitInitCall(ctx, nsClass) else ()
                      val arity = Lst.length(args)
                      emitCallArgs(ctx, args)
                      val desc = objectMethodDesc(arity)
                      val mref = CF.cfMethodref(ctx.cf, nsClass, jvmMangleName(method), desc)
                      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, mref)
                    }
                  }
                }
                None => emitCallIndirect(ctx, fn, args)
              }
            }
            _ => emitCallIndirect(ctx, fn, args)
          }
        }
        _ => emitCallIndirect(ctx, fn, args)
      }
    }
    EField(obj, field) => {
      emitExpr(ctx, obj)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KRECORD))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfString(ctx.cf, field))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, KRECORD, "get", "(Ljava/lang/String;)Ljava/lang/Object;"))
    }
    EAwait(e) => { emitExpr(ctx, e); CF.mbEmit1(ctx.mb, Op.JvmOp.pop); pushNull(ctx) }
    EUnary(op, e) => emitUnaryExpr(ctx, op, e)
    EBinary(op, l, r) => emitBinaryExpr(ctx, op, l, r)
    ECons(h, t) => {
      val headSlot = ctx.nextLocal
      val tailSlot = ctx.nextLocal + 1
      ctx.nextLocal := ctx.nextLocal + 2
      emitExpr(ctx, h)
      storeLocal(ctx, headSlot)
      emitExpr(ctx, t)
      storeLocal(ctx, tailSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, KCONS))
      CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
      loadLocalSlot(ctx, headSlot)
      loadLocalSlot(ctx, tailSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KLIST))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, CF.cfMethodref(ctx.cf, KCONS, "<init>", "(Ljava/lang/Object;Lkestrel/runtime/KList;)V"))
    }
    EPipe(op, left, right) =>
      if (op == "|>") {
        match (right) {
          ECall(fn, args) => emitExpr(ctx, ECall(fn, left :: args))
          _ => emitExpr(ctx, ECall(right, [left]))
        }
      } else {
        match (left) {
          ECall(fn, args) => emitExpr(ctx, ECall(fn, Lst.append(args, [right])))
          _ => emitExpr(ctx, ECall(left, [right]))
        }
      }
    EIf(c, t, eOpt) => {
      val ifResultSlot = 53
      // Evaluate condition and unbox to JVM int.
      emitExpr(ctx, c)
      val boolClassRef = CF.cfClassRef(ctx.cf, BOOLEAN)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, boolClassRef)
      val bvMref = CF.cfMethodref(ctx.cf, BOOLEAN, "booleanValue", "()Z")
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, bvMref)
      val code = CF.mbGetCode(ctx.mb)
      val ifeqPos = CF.mbLength(ctx.mb)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)                              // placeholder
      CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), None)            // stackmap: then-arm entry
      // Emit then-arm.
      emitExpr(ctx, t)
      val thenPushes = thenArmPushesValue(t)
      val gotoPos =
        if (thenPushes) {
          storeLocal(ctx, ifResultSlot)
          val gp = CF.mbLength(ctx.mb)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.goto_, 0)                         // placeholder
          gp
        } else
          -1
      // Else-arm entry: backpatch IFEQ.
      val elseStart = CF.mbLength(ctx.mb)
      CF.mbAddBranchTarget(ctx.mb, elseStart, None)                      // stackmap: else-arm entry
      patchShort(code, ifeqPos + 1, elseStart - ifeqPos)
      // Emit else-arm (or KUnit if no else clause).
      match (eOpt) {
        Some(e) => emitExpr(ctx, e)
        None => {
          val kunitRef = CF.cfFieldref(ctx.cf, KUNIT, "INSTANCE", "Lkestrel/runtime/KUnit;")
          CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, kunitRef)
        }
      }
      storeLocal(ctx, ifResultSlot)
      // Join point: backpatch GOTO.
      val ifEndPos = CF.mbLength(ctx.mb)
      CF.mbAddBranchTarget(ctx.mb, ifEndPos, None)                       // stackmap: join point
      if (thenPushes) patchShort(code, gotoPos + 1, ifEndPos - gotoPos) else ()
      loadLocalSlot(ctx, ifResultSlot)
    }
    EWhile(c, b) => {
      val code = CF.mbGetCode(ctx.mb)
      val loopBodyExtra = estimateBodyLocals(EBlock(b))
      val numLocals = if (ctx.nextLocal + loopBodyExtra > 70) ctx.nextLocal + loopBodyExtra else 70
      val loopState = CF.paramOnlyFrame(numLocals)
      val loopHead = CF.mbLength(ctx.mb)
      CF.mbAddBranchTarget(ctx.mb, loopHead, Some(loopState))
      // Evaluate condition and branch to exit if false.
      emitExpr(ctx, c)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, BOOLEAN))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, BOOLEAN, "booleanValue", "()Z"))
      val ifeqPos = CF.mbLength(ctx.mb)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)                             // placeholder
      // Body entry stackmap.
      CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), Some(loopState))
      // Push break layer so SBreak/SContinue can find the loop head and break list.
      val layer = { breakJumps = Arr.new(), loopHead = loopHead }
      ctx.loopBreakStack := layer :: ctx.loopBreakStack
      // Emit body; discard its value.
      emitExpr(ctx, EBlock(b))
      CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
      // Pop break layer.
      ctx.loopBreakStack := Lst.tail(ctx.loopBreakStack)
      // Back-edge GOTO to loop head.
      val gotoPos = CF.mbLength(ctx.mb)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.goto_, 0)                            // placeholder
      patchShort(code, gotoPos + 1, loopHead - gotoPos)
      // Exit position: backpatch IFEQ and all break jumps.
      val exitPos = CF.mbLength(ctx.mb)
      CF.mbAddBranchTarget(ctx.mb, exitPos, Some(loopState))
      patchShort(code, ifeqPos + 1, exitPos - ifeqPos)
      backpatchBreakJumps(code, Arr.toList(layer.breakJumps), exitPos)
      // Push KUnit as the while expression result.
      val kunitRef = CF.cfFieldref(ctx.cf, KUNIT, "INSTANCE", "Lkestrel/runtime/KUnit;")
      CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, kunitRef)
    }
    EMatch(scrut, arms) => {
      emitExpr(ctx, scrut)
      CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
      emitMatchArms(ctx, arms)
    }
    ELambda(_async, _tp, _params, _body) => pushNull(ctx)
    ETemplate(parts) => {
      CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, STRING_BUILDER))
      CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, CF.cfMethodref(ctx.cf, STRING_BUILDER, "<init>", "()V"))
      emitTemplateBuild(ctx, parts)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, STRING_BUILDER, "toString", "()Ljava/lang/String;"))
    }
    EList(elems) =>
      if (Lst.isEmpty(elems)) {
        val nilRef = CF.cfFieldref(ctx.cf, KNIL, "INSTANCE", "Lkestrel/runtime/KNil;")
        CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, nilRef)
      } else {
        val listTemp = ctx.nextLocal
        val elemTemp = ctx.nextLocal + 1
        ctx.nextLocal := ctx.nextLocal + 2
        val nilRef = CF.cfFieldref(ctx.cf, KNIL, "INSTANCE", "Lkestrel/runtime/KNil;")
        CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, nilRef)
        storeLocal(ctx, listTemp)
        emitListBuild(ctx, Lst.reverse(elems), listTemp, elemTemp)
        loadLocalSlot(ctx, listTemp)
      }
    ERecord(spreadOpt, fields) => {
      match (spreadOpt) {
        Some(sp) => {
          emitExpr(ctx, sp)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KRECORD))
          CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, KRECORD, "copy", "()Lkestrel/runtime/KRecord;"))
        }
        None => {
          CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, KRECORD))
          CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, CF.cfMethodref(ctx.cf, KRECORD, "<init>", "()V"))
        }
      }
      emitRecordFields(ctx, fields)
    }
    ETuple(xs) => {
      CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, KRECORD))
      CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, CF.cfMethodref(ctx.cf, KRECORD, "<init>", "()V"))
      emitTupleElems(ctx, xs, 0)
    }
    EThrow(e) => { emitExpr(ctx, e); CF.mbEmit1(ctx.mb, Op.JvmOp.pop); pushNull(ctx) }
    ETry(block, _varOpt, cases) => {
      emitBlockStmts(ctx, block.stmts)
      emitExpr(ctx, block.result)
      CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
      emitMatchArms(ctx, cases)
    }
    EBlock(block) => {
      emitBlockStmts(ctx, block.stmts)
      emitExpr(ctx, block.result)
    }
    EIs(e, _t) => { emitExpr(ctx, e); CF.mbEmit1(ctx.mb, Op.JvmOp.pop); pushBoolBoxed(ctx, True) }
    ENever => pushNull(ctx)
  }
