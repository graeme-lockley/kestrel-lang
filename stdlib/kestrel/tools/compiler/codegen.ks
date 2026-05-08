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
val KTASK = "kestrel/runtime/KTask"
export val KNONE = "kestrel/runtime/KNone"
export val KNIL = "kestrel/runtime/KNil"
val K_EXCEPTION = "kestrel/runtime/KException"
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

type LambdaInfo = {
  body: Ast.Expr,
  async_: Bool,
  params: List<Ast.Param>,
  freeVars: List<String>,
  capturing: Bool,
  localFunNames: Option<List<String>>,
  freeVarVars: Dict<String, Unit>
}

export type ModuleContext = {
  className: String,
  globalNames: Dict<String, Unit>,
  globalVarNames: Dict<String, Unit>,
  funArities: Dict<String, Int>,
  adtClassByConstructor: Dict<String, String>,
  adtConstructorArity: Dict<String, Int>,
  options: JvmCodegenOptions,
  lambdas: mut List<LambdaInfo>,
  lambdaIndex: mut Int,
  lambdaClasses: mut Dict<String, ByteArray>
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
  freeVarToIndex: mut Option<Dict<String, Int>>,
  localFunNamesInEnv: mut Option<Dict<String, Unit>>,
  freeVarVars: mut Dict<String, Unit>,
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
  options = emptyJvmCodegenOptions(),
  mut lambdas = [],
  mut lambdaIndex = 0,
  mut lambdaClasses = Dict.emptyStringDict()
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
  mut freeVarToIndex = None,
  mut localFunNamesInEnv = None,
  mut freeVarVars = Dict.emptyStringDict(),
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

// Returns a JVM method descriptor for a method that takes `arity` Object params and returns KTask.
fun taskMethodDesc(arity: Int): String =
  "(${objectArgs(arity)})Lkestrel/runtime/KTask;"

// Returns the JVM method name for the private async payload method.
fun asyncPayloadMethodName(name: String): String =
  Str.append(Str.append("$", "async"), Str.append("$", name))

// Recursively emits dup; ldc i; aload_i; aastore for each slot of the args array.
fun emitAsyncArgsLoop(mb: CF.MethodBuilder, cf: CF.ClassFileBuilder, i: Int, arity: Int): Unit =
  if (i >= arity) ()
  else {
    CF.mbEmit1(mb, Op.JvmOp.dup);
    val iIdx = CF.cfConstantInt(cf, i)
    CF.mbEmit1s(mb, Op.JvmOp.ldcW, iIdx);
    if (i == 0) CF.mbEmit1(mb, Op.JvmOp.aload0)
    else if (i == 1) CF.mbEmit1(mb, Op.JvmOp.aload1)
    else if (i == 2) CF.mbEmit1(mb, Op.JvmOp.aload2)
    else if (i == 3) CF.mbEmit1(mb, Op.JvmOp.aload3)
    else CF.mbEmit1b(mb, Op.JvmOp.aload, i);
    CF.mbEmit1(mb, Op.JvmOp.aastore);
    emitAsyncArgsLoop(mb, cf, i + 1, arity)
  }

// Emits ldc arity; anewarray Object; then populates each slot via emitAsyncArgsLoop.
fun emitAsyncArgsArray(cf: CF.ClassFileBuilder, mb: CF.MethodBuilder, arity: Int): Unit = {
  val nIdx = CF.cfConstantInt(cf, arity)
  CF.mbEmit1s(mb, Op.JvmOp.ldcW, nIdx);
  val objRef = CF.cfClassRef(cf, "java/lang/Object")
  CF.mbEmit1s(mb, Op.JvmOp.anewarray, objRef);
  emitAsyncArgsLoop(mb, cf, 0, arity)
}

fun emitApplyArgLoads(mb: CF.MethodBuilder, cf: CF.ClassFileBuilder, i: Int, arity: Int): Unit =
  if (i >= arity) ()
  else {
    CF.mbEmit1(mb, Op.JvmOp.aload1)
    CF.mbEmit1s(mb, Op.JvmOp.ldcW, CF.cfConstantInt(cf, i))
    CF.mbEmit1(mb, Op.JvmOp.aaload)
    emitApplyArgLoads(mb, cf, i + 1, arity)
  }

fun namesToDict(names: List<String>): Dict<String, Unit> =
  Lst.foldl(names, Dict.emptyStringDict(), (acc: Dict<String, Unit>, n: String) => Dict.insert(acc, n, ()))

fun keysetOf<K, V>(d: Dict<K, V>): Dict<K, Unit> =
  Lst.foldl(Dict.keys(d), Dict.empty(), (acc: Dict<K, Unit>, k: K) => Dict.insert(acc, k, ()))

fun bindParamNames(scope: Dict<String, Unit>, params: List<Ast.Param>): Dict<String, Unit> =
  match (params) {
    [] => scope
    p :: rest => bindParamNames(Dict.insert(scope, p.name, ()), rest)
  }

fun listAt<A>(xs: List<A>, idx: Int): Option<A> =
  if (idx < 0) None
  else
    match (xs) {
      [] => None
      h :: t => if (idx == 0) Some(h) else listAt(t, idx - 1)
    }

fun collectPatternVars(pat: Ast.Pattern): List<String> =
  match (pat) {
    PVar(name) => [name]
    PCons(h, t) => Lst.append(collectPatternVars(h), collectPatternVars(t))
    PList(parts, restOpt) => {
      val partVars = Lst.foldl(parts, [], (acc: List<String>, p: Ast.Pattern) => Lst.append(acc, collectPatternVars(p)))
      match (restOpt) {
        Some(rest) => Lst.append(partVars, [rest])
        None => partVars
      }
    }
    PCon(_name, fields) =>
      Lst.foldl(fields, [], (acc: List<String>, f: Ast.ConField) =>
        match (f.pattern) {
          Some(p) => Lst.append(acc, collectPatternVars(p))
          None => acc
        })
    PTuple(parts) =>
      Lst.foldl(parts, [], (acc: List<String>, p: Ast.Pattern) => Lst.append(acc, collectPatternVars(p)))
    _ => []
  }

fun unionManySets(sets: List<Dict<String, Unit>>): Dict<String, Unit> =
  match (sets) {
    [] => Dict.emptyStringDict()
    s :: rest => Dict.union(s, unionManySets(rest))
  }

fun getFreeVarsStmt(stmt: Ast.Stmt, bound: Dict<String, Unit>, scope: Dict<String, Unit>): Dict<String, Unit> =
  match (stmt) {
    SVal(_name, _ann, v) => getFreeVarsSet(v, bound, scope)
    SVar(_name, _ann, v) => getFreeVarsSet(v, bound, scope)
    SFun(_async, name, _tp, params, _rt, body) => {
      val b1 = Dict.insert(bound, name, ())
      val b2 = bindParamNames(b1, params)
      getFreeVarsSet(body, b2, scope)
    }
    SExpr(x) => getFreeVarsSet(x, bound, scope)
    SAssign(tgt, rhs) => Dict.union(getFreeVarsSet(tgt, bound, scope), getFreeVarsSet(rhs, bound, scope))
    _ => Dict.emptyStringDict()
  }

fun updateBoundFromStmt(stmt: Ast.Stmt, bound: Dict<String, Unit>): Dict<String, Unit> =
  match (stmt) {
    SVal(name, _ann, _v) => Dict.insert(bound, name, ())
    SVar(name, _ann, _v) => Dict.insert(bound, name, ())
    SFun(_async, name, _tp, _params, _rt, _body) => Dict.insert(bound, name, ())
    _ => bound
  }

fun getFreeVarsStmts(stmts: List<Ast.Stmt>, bound: Dict<String, Unit>, scope: Dict<String, Unit>): Dict<String, Unit> =
  match (stmts) {
    [] => Dict.emptyStringDict()
    s :: rest => {
      val sSet = getFreeVarsStmt(s, bound, scope)
      val b2 = updateBoundFromStmt(s, bound)
      Dict.union(sSet, getFreeVarsStmts(rest, b2, scope))
    }
  }

fun getFreeVarsSet(expr: Ast.Expr, bound: Dict<String, Unit>, scope: Dict<String, Unit>): Dict<String, Unit> =
  match (expr) {
    EIdent(name) =>
      if (Dict.member(scope, name) & !Dict.member(bound, name)) Dict.insert(Dict.emptyStringDict(), name, ())
      else Dict.emptyStringDict()
    ELambda(_async, _tp, _params, _body) => Dict.emptyStringDict()
    ECall(fn, args) => {
      val argSets = Lst.foldl(args, [], (acc: List<Dict<String, Unit>>, a: Ast.Expr) => Lst.append(acc, [getFreeVarsSet(a, bound, scope)]))
      Dict.union(getFreeVarsSet(fn, bound, scope), unionManySets(argSets))
    }
    EBinary(_op, l, r) => Dict.union(getFreeVarsSet(l, bound, scope), getFreeVarsSet(r, bound, scope))
    EUnary(_op, x) => getFreeVarsSet(x, bound, scope)
    EIf(c, t, eOpt) => {
      val base = Dict.union(getFreeVarsSet(c, bound, scope), getFreeVarsSet(t, bound, scope))
      match (eOpt) {
        Some(e2) => Dict.union(base, getFreeVarsSet(e2, bound, scope))
        None => base
      }
    }
    EIs(x, _t) => getFreeVarsSet(x, bound, scope)
    EWhile(c, b) => Dict.union(getFreeVarsSet(c, bound, scope), getFreeVarsSet(EBlock(b), bound, scope))
    EMatch(scrut, arms) => {
      val armSets = Lst.foldl(arms, [], (acc: List<Dict<String, Unit>>, arm: Ast.Case_) => {
        val patBound = Lst.foldl(collectPatternVars(arm.pattern), bound, (bb: Dict<String, Unit>, n: String) => Dict.insert(bb, n, ()))
        Lst.append(acc, [getFreeVarsSet(arm.body, patBound, scope)])
      })
      Dict.union(getFreeVarsSet(scrut, bound, scope), unionManySets(armSets))
    }
    EPipe(_op, l, r) => Dict.union(getFreeVarsSet(l, bound, scope), getFreeVarsSet(r, bound, scope))
    ECons(h, t) => Dict.union(getFreeVarsSet(h, bound, scope), getFreeVarsSet(t, bound, scope))
    EField(obj, _f) => getFreeVarsSet(obj, bound, scope)
    ETemplate(parts) =>
      Lst.foldl(parts, Dict.emptyStringDict(), (acc: Dict<String, Unit>, p: Ast.TmplPart) =>
        match (p) {
          TmplExpr(x) => Dict.union(acc, getFreeVarsSet(x, bound, scope))
          _ => acc
        })
    EList(xs) =>
      Lst.foldl(xs, Dict.emptyStringDict(), (acc: Dict<String, Unit>, x: Ast.ListElem) =>
        match (x) {
          LElem(v) => Dict.union(acc, getFreeVarsSet(v, bound, scope))
          LSpread(v) => Dict.union(acc, getFreeVarsSet(v, bound, scope))
        })
    EThrow(v) => getFreeVarsSet(v, bound, scope)
    EAwait(v) => getFreeVarsSet(v, bound, scope)
    ETry(block, _varOpt, arms) => {
      val armSets = Lst.foldl(arms, [], (acc: List<Dict<String, Unit>>, arm: Ast.Case_) => {
        val patBound = Lst.foldl(collectPatternVars(arm.pattern), bound, (bb: Dict<String, Unit>, n: String) => Dict.insert(bb, n, ()))
        Lst.append(acc, [getFreeVarsSet(arm.body, patBound, scope)])
      })
      Dict.union(getFreeVarsSet(EBlock(block), bound, scope), unionManySets(armSets))
    }
    ERecord(spreadOpt, fields) => {
      val spreadSet =
        match (spreadOpt) {
          Some(sp) => getFreeVarsSet(sp, bound, scope)
          None => Dict.emptyStringDict()
        }
      val fieldSet = Lst.foldl(fields, Dict.emptyStringDict(), (acc: Dict<String, Unit>, f: Ast.RecField) => Dict.union(acc, getFreeVarsSet(f.value, bound, scope)))
      Dict.union(spreadSet, fieldSet)
    }
    ETuple(parts) => Lst.foldl(parts, Dict.emptyStringDict(), (acc: Dict<String, Unit>, x: Ast.Expr) => Dict.union(acc, getFreeVarsSet(x, bound, scope)))
    EBlock(block) => {
      val stmtSet = getFreeVarsStmts(block.stmts, bound, scope)
      val b2 = Lst.foldl(block.stmts, bound, (b: Dict<String, Unit>, s: Ast.Stmt) => updateBoundFromStmt(s, b))
      Dict.union(stmtSet, getFreeVarsSet(block.result, b2, scope))
    }
    _ => Dict.emptyStringDict()
  }

fun getFreeVars(expr: Ast.Expr, paramNames: Dict<String, Unit>, scope: Dict<String, Unit>): List<String> =
  Dict.keys(getFreeVarsSet(expr, paramNames, scope))

fun collectLambdas(_prog: Ast.Program, _globalNames: Dict<String, Unit>, _funArities: Dict<String, Int>): List<LambdaInfo> = []

fun buildAsyncLambdaPayloadClass(outerClassName: String, lambdaId: Int, arity: Int, capturing: Bool): (String, ByteArray) = {
  val lambdaTag = Str.append("$", "Lambda")
  val payloadTag = Str.append("$", "Payload")
  val innerName = Str.append(Str.append(outerClassName, lambdaTag), Str.append(Str.fromInt(lambdaId), payloadTag))
  val cf = CF.newClassFile(innerName, "java/lang/Object", Op.Acc.public_ + Op.Acc.super_ + Op.Acc.final_)
  CF.cfAddInterface(cf, KFUNCTION)
  if (capturing) {
    CF.cfAddField(cf, "env", "[Ljava/lang/Object;", Op.Acc.private_ + Op.Acc.final_)
    val ctor = CF.cfAddMethod(cf, "<init>", "([Ljava/lang/Object;)V", Op.Acc.public_)
    CF.mbEmit1(ctor, Op.JvmOp.aload0)
    CF.mbEmit1s(ctor, Op.JvmOp.invokespecial, CF.cfMethodref(cf, "java/lang/Object", "<init>", "()V"))
    CF.mbEmit1(ctor, Op.JvmOp.aload0)
    CF.mbEmit1(ctor, Op.JvmOp.aload1)
    CF.mbEmit1s(ctor, Op.JvmOp.putfield, CF.cfFieldref(cf, innerName, "env", "[Ljava/lang/Object;"))
    CF.mbEmit1(ctor, Op.JvmOp.return_)
    CF.mbSetMaxs(ctor, 2, 2)
  } else emitDefaultCtor(cf);

  val applyMb = CF.cfAddMethod(cf, "apply", "([Ljava/lang/Object;)Ljava/lang/Object;", Op.Acc.public_)
  if (capturing) {
    CF.mbEmit1(applyMb, Op.JvmOp.aload0)
    CF.mbEmit1s(applyMb, Op.JvmOp.getfield, CF.cfFieldref(cf, innerName, "env", "[Ljava/lang/Object;"))
  } else ()
  emitApplyArgLoads(applyMb, cf, 0, arity)
  val payloadDesc =
    if (capturing) "([Ljava/lang/Object;${objectArgs(arity)})Ljava/lang/Object;"
    else objectMethodDesc(arity)
  val payloadMethod = asyncPayloadMethodName(Str.append("lambda", Str.fromInt(lambdaId)))
  CF.mbEmit1s(applyMb, Op.JvmOp.invokestatic, CF.cfMethodref(cf, outerClassName, payloadMethod, payloadDesc))
  CF.mbEmit1(applyMb, Op.JvmOp.areturn)
  CF.mbSetMaxs(applyMb, 16, 3)
  val out = (innerName, CF.cfToBytes(cf))
  out
}

fun buildLambdaClass(outerClassName: String, lambdaId: Int, arity: Int, capturing: Bool, async_: Bool): (String, ByteArray) = {
  val lambdaTag = Str.append("$", "Lambda")
  val payloadTag = Str.append("$", "Payload")
  val innerName = Str.append(Str.append(outerClassName, lambdaTag), Str.fromInt(lambdaId))
  val cf = CF.newClassFile(innerName, "java/lang/Object", Op.Acc.public_ + Op.Acc.super_ + Op.Acc.final_)
  CF.cfAddInterface(cf, KFUNCTION)

  if (capturing) {
    CF.cfAddField(cf, "env", "[Ljava/lang/Object;", Op.Acc.private_ + Op.Acc.final_)
    val ctor = CF.cfAddMethod(cf, "<init>", "([Ljava/lang/Object;)V", Op.Acc.public_)
    CF.mbEmit1(ctor, Op.JvmOp.aload0)
    CF.mbEmit1s(ctor, Op.JvmOp.invokespecial, CF.cfMethodref(cf, "java/lang/Object", "<init>", "()V"))
    CF.mbEmit1(ctor, Op.JvmOp.aload0)
    CF.mbEmit1(ctor, Op.JvmOp.aload1)
    CF.mbEmit1s(ctor, Op.JvmOp.putfield, CF.cfFieldref(cf, innerName, "env", "[Ljava/lang/Object;"))
    CF.mbEmit1(ctor, Op.JvmOp.return_)
    CF.mbSetMaxs(ctor, 2, 2)
  } else emitDefaultCtor(cf);

  val applyMb = CF.cfAddMethod(cf, "apply", "([Ljava/lang/Object;)Ljava/lang/Object;", Op.Acc.public_)
  if (async_) {
    if (capturing) {
      CF.mbEmit1s(applyMb, Op.JvmOp.new_, CF.cfClassRef(cf, Str.append(innerName, payloadTag)))
      CF.mbEmit1(applyMb, Op.JvmOp.dup)
      CF.mbEmit1(applyMb, Op.JvmOp.aload0)
      CF.mbEmit1s(applyMb, Op.JvmOp.getfield, CF.cfFieldref(cf, innerName, "env", "[Ljava/lang/Object;"))
      CF.mbEmit1s(applyMb, Op.JvmOp.invokespecial, CF.cfMethodref(cf, Str.append(innerName, payloadTag), "<init>", "([Ljava/lang/Object;)V"))
    } else {
      CF.mbEmit1s(applyMb, Op.JvmOp.new_, CF.cfClassRef(cf, Str.append(innerName, payloadTag)))
      CF.mbEmit1(applyMb, Op.JvmOp.dup)
      CF.mbEmit1s(applyMb, Op.JvmOp.invokespecial, CF.cfMethodref(cf, Str.append(innerName, payloadTag), "<init>", "()V"))
    }
    CF.mbEmit1(applyMb, Op.JvmOp.aload1)
    CF.mbEmit1s(applyMb, Op.JvmOp.invokestatic, CF.cfMethodref(cf, RUNTIME, "submitAsync", "(Lkestrel/runtime/KFunction;[Ljava/lang/Object;)Lkestrel/runtime/KTask;"))
  } else {
    if (capturing) {
      CF.mbEmit1(applyMb, Op.JvmOp.aload0)
      CF.mbEmit1s(applyMb, Op.JvmOp.getfield, CF.cfFieldref(cf, innerName, "env", "[Ljava/lang/Object;"))
    } else ()
    emitApplyArgLoads(applyMb, cf, 0, arity)
    val payloadDesc =
      if (capturing) "([Ljava/lang/Object;${objectArgs(arity)})Ljava/lang/Object;"
      else objectMethodDesc(arity)
    val lambdaMethod = jvmMangleName(Str.append(Str.append("$", "lambda"), Str.fromInt(lambdaId)))
    CF.mbEmit1s(applyMb, Op.JvmOp.invokestatic, CF.cfMethodref(cf, outerClassName, lambdaMethod, payloadDesc))
  }
  CF.mbEmit1(applyMb, Op.JvmOp.areturn)
  CF.mbSetMaxs(applyMb, 16, 3)
  val out = (innerName, CF.cfToBytes(cf))
  out
}

fun allocLambdaId(mctx: ModuleContext): Int = {
  val id = mctx.lambdaIndex
  mctx.lambdaIndex := id + 1
  id
}

fun putLambdaClass(mctx: ModuleContext, className: String, bytes: ByteArray): Unit = {
  mctx.lambdaClasses := Dict.insert(mctx.lambdaClasses, className, bytes)
}

fun freeVarIndexMap(names: List<String>): Dict<String, Int> = {
  fun loop(xs: List<String>, i: Int, acc: Dict<String, Int>): Dict<String, Int> =
    match (xs) {
      [] => acc
      n :: rest => loop(rest, i + 1, Dict.insert(acc, n, i))
    }
  loop(names, 0, Dict.emptyStringDict())
}

fun freeVarIndexMapFromOffset(names: List<String>, offset: Int): Dict<String, Int> = {
  fun loop(xs: List<String>, i: Int, acc: Dict<String, Int>): Dict<String, Int> =
    match (xs) {
      [] => acc
      n :: rest => loop(rest, i + 1, Dict.insert(acc, n, i))
    }
  loop(names, offset, Dict.emptyStringDict())
}

fun loadEnvArray(ctx: CodegenContext): Unit = {
  if (loadLocal(ctx, "__env")) ()
  else CF.mbEmit1(ctx.mb, Op.JvmOp.aload0)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, "[Ljava/lang/Object;"))
}

fun emitLoadFreeVarFromEnv(ctx: CodegenContext, idx: Int): Unit = {
  loadEnvArray(ctx)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfConstantInt(ctx.cf, idx))
  CF.mbEmit1(ctx.mb, Op.JvmOp.aaload)
}

fun emitLoadLocalFunFromEnv(ctx: CodegenContext, name: String): Unit = {
  emitLoadFreeVarFromEnv(ctx, 0)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KRECORD))
  CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfString(ctx.cf, name))
  CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, KRECORD, "get", "(Ljava/lang/String;)Ljava/lang/Object;"))
}

fun emitCaptureValueByName(ctx: CodegenContext, name: String): Unit = {
  if (loadLocal(ctx, name)) ()
  else {
    val localFunHit =
      match (ctx.localFunNamesInEnv) {
        Some(funSet) =>
          if (Dict.member(funSet, name)) {
            emitLoadLocalFunFromEnv(ctx, name)
            True
          } else False
        None => False
      }
    if (localFunHit) ()
    else {
      val freeHit =
        match (ctx.freeVarToIndex) {
          Some(fvMap) =>
            match (Dict.get(fvMap, name)) {
              Some(idx) => {
                emitLoadFreeVarFromEnv(ctx, idx)
                True
              }
              None => False
            }
          None => False
        }
      if (freeHit) ()
      else {
        val mctx = ctx.mctx
        if (Dict.member(mctx.globalNames, name)) {
          val fref = CF.cfFieldref(ctx.cf, mctx.className, name, "Ljava/lang/Object;")
          CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, fref)
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
              emitInitCall(ctx, valCls)
              val fref = CF.cfFieldref(ctx.cf, valCls, origName, "Ljava/lang/Object;")
              CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, fref)
            }
            None => {
              val importedFunClass = Dict.get(mctx.options.importedNameToClass, name)
              match (importedFunClass) {
                Some(funCls) => {
                  val importedFunArity = Dict.get(mctx.options.importedFunArities, name)
                  match (importedFunArity) {
                    Some(funArity) => {
                      val origName = Opt.getOrElse(Dict.get(mctx.options.importedNameToOriginal, name), name)
                      emitInitCall(ctx, funCls)
                      emitFunctionRef(ctx, funCls, origName, funArity)
                    }
                    None => emitIdentExpr(ctx, name)
                  }
                }
                None => emitIdentExpr(ctx, name)
              }
            }
          }
        }
      }
    }
  }
}

fun emitCaptureArrayEntries(ctx: CodegenContext, freeVars: List<String>, i: Int): Unit =
  match (freeVars) {
    [] => ()
    name :: rest => {
      CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfConstantInt(ctx.cf, i))
      emitCaptureValueByName(ctx, name)
      CF.mbEmit1(ctx.mb, Op.JvmOp.aastore)
      emitCaptureArrayEntries(ctx, rest, i + 1)
    }
  }

fun lambdaScope(ctx: CodegenContext): Dict<String, Unit> = {
  val localScope = keysetOf(ctx.locals)
  val globalScope = Dict.union(ctx.mctx.globalNames, keysetOf(ctx.mctx.funArities))
  val importScope = Dict.union(keysetOf(ctx.mctx.options.importedValVarToClass), keysetOf(ctx.mctx.options.importedNameToClass))
  Dict.union(localScope, Dict.union(globalScope, importScope))
}

fun captureVarNames(ctx: CodegenContext, freeVars: List<String>): Dict<String, Unit> =
  Lst.foldl(freeVars, Dict.emptyStringDict(), (acc: Dict<String, Unit>, name: String) => {
    if (Dict.member(ctx.varLocals, name) | Dict.member(ctx.mctx.globalVarNames, name) | Dict.member(ctx.mctx.options.importedVarNames, name)) Dict.insert(acc, name, ())
    else acc
  })

fun emitLambdaBodyMethod(ctx: CodegenContext, lambdaId: Int, info: LambdaInfo): Unit = {
  val arity = Lst.length(info.params)
  val methodName =
    if (info.async_) asyncPayloadMethodName(Str.append("lambda", Str.fromInt(lambdaId)))
    else jvmMangleName(Str.append(Str.append("$", "lambda"), Str.fromInt(lambdaId)))
  val desc =
    if (info.capturing) "([Ljava/lang/Object;${objectArgs(arity)})Ljava/lang/Object;"
    else objectMethodDesc(arity)
  val flags = Op.Acc.private_ + Op.Acc.static_
  val mb = CF.cfAddMethod(ctx.cf, methodName, desc, flags)
  val bodyCtx = newCodegenContext(ctx.cf, mb, ctx.mctx, ctx.getInferredType)
  if (info.capturing) {
    bindLocal(bodyCtx, "__env")
    val freeVarOffset =
      match (info.localFunNames) {
        Some(_) => 1
        None => 0
      }
    bodyCtx.freeVarToIndex := Some(freeVarIndexMapFromOffset(info.freeVars, freeVarOffset))
    bodyCtx.freeVarVars := info.freeVarVars
    match (info.localFunNames) {
      Some(names) => { bodyCtx.localFunNamesInEnv := Some(namesToDict(names)); () }
      None => ()
    }
  } else ()
  bindParams(bodyCtx, info.params)
  emitExpr(bodyCtx, info.body)
  CF.mbEmit1(mb, Op.JvmOp.areturn)
  val maxLocals = if (bodyCtx.nextLocal + 8 > 24) bodyCtx.nextLocal + 8 else 24
  CF.mbSetMaxs(mb, 32, maxLocals)
}

fun emitLambdaExpr(ctx: CodegenContext, async_: Bool, params: List<Ast.Param>, body: Ast.Expr): Unit = {
  val scope = lambdaScope(ctx)
  val paramScope = bindParamNames(Dict.emptyStringDict(), params)
  val freeVars = getFreeVars(body, paramScope, scope)
  val capturing = !Lst.isEmpty(freeVars)
  val info = {
    body = body,
    async_ = async_,
    params = params,
    freeVars = freeVars,
    capturing = capturing,
    localFunNames = None,
    freeVarVars = captureVarNames(ctx, freeVars)
  }
  val id = allocLambdaId(ctx.mctx)
  emitLambdaBodyMethod(ctx, id, info)
  val lambdaPair = buildLambdaClass(ctx.mctx.className, id, Lst.length(params), capturing, async_)
  putLambdaClass(ctx.mctx, lambdaPair.0, lambdaPair.1)
  if (async_) {
    val payloadPair = buildAsyncLambdaPayloadClass(ctx.mctx.className, id, Lst.length(params), capturing)
    putLambdaClass(ctx.mctx, payloadPair.0, payloadPair.1)
  } else ()
  if (capturing) {
    CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfConstantInt(ctx.cf, Lst.length(freeVars)))
    CF.mbEmit1s(ctx.mb, Op.JvmOp.anewarray, CF.cfClassRef(ctx.cf, "java/lang/Object"))
    emitCaptureArrayEntries(ctx, freeVars, 0)
    CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, lambdaPair.0))
    CF.mbEmit1(ctx.mb, Op.JvmOp.dupX1)
    CF.mbEmit1(ctx.mb, Op.JvmOp.swap)
    CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, CF.cfMethodref(ctx.cf, lambdaPair.0, "<init>", "([Ljava/lang/Object;)V"))
  } else {
    CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, lambdaPair.0))
    CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
    CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, CF.cfMethodref(ctx.cf, lambdaPair.0, "<init>", "()V"))
  }
}

export fun emitFunDecl(cf: CF.ClassFileBuilder, decl: Ast.FunDecl, mctx: ModuleContext, getInferredType: (Ast.Expr) -> Option<Ty.InternalType>): Unit = {
  val arity = Lst.length(decl.params)
  if (decl.async_) {
    // Payload method: private static, Object return, contains the actual body.
    val payloadName = asyncPayloadMethodName(decl.name)
    val payloadMb = CF.cfAddMethod(cf, payloadName, objectMethodDesc(arity), Op.Acc.private_ + Op.Acc.static_)
    val payloadCtx = newCodegenContext(cf, payloadMb, mctx, getInferredType)
    bindParams(payloadCtx, decl.params)
    emitTailLoopScaffold(payloadMb)
    emitExpr(payloadCtx, decl.body)
    CF.mbEmit1(payloadMb, Op.JvmOp.areturn)
    val payloadLocals = if (arity + 8 > 70) arity + 8 else 70
    CF.mbSetMaxs(payloadMb, 32, payloadLocals);
    // Outer wrapper method: public static, returns KTask; submits payload to async executor.
    val wrapperMb = CF.cfAddMethod(cf, decl.name, taskMethodDesc(arity), Op.Acc.public_ + Op.Acc.static_)
    val wrapperCtx = newCodegenContext(cf, wrapperMb, mctx, getInferredType)
    emitFunctionRef(wrapperCtx, mctx.className, payloadName, arity)
    emitAsyncArgsArray(cf, wrapperMb, arity);
    val submitRef = CF.cfMethodref(cf, RUNTIME, "submitAsync", "(Lkestrel/runtime/KFunction;[Ljava/lang/Object;)Lkestrel/runtime/KTask;")
    CF.mbEmit1s(wrapperMb, Op.JvmOp.invokestatic, submitRef)
    CF.mbEmit1(wrapperMb, Op.JvmOp.areturn)
    val wrapperLocals = if (arity + 4 > 8) arity + 4 else 8
    CF.mbSetMaxs(wrapperMb, 32, wrapperLocals)
  } else {
    val desc = objectMethodDesc(arity)
    val mb = CF.cfAddMethod(cf, decl.name, desc, Op.Acc.public_ + Op.Acc.static_)
    val ctx = newCodegenContext(cf, mb, mctx, getInferredType)
    bindParams(ctx, decl.params)
    emitTailLoopScaffold(mb)
    emitExpr(ctx, decl.body)
    CF.mbEmit1(mb, Op.JvmOp.areturn)
    CF.mbSetMaxs(mb, 2, 32)
  }
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
  val withLambdas = Dict.union(extraClasses, mctx.lambdaClasses)
  {
    classes = Dict.insert(withLambdas, moduleName, mainBytes)
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
      options = mctx.options,
      mut lambdas = mctx.lambdas,
      mut lambdaIndex = mctx.lambdaIndex,
      mut lambdaClasses = mctx.lambdaClasses
    }
    TDExternFun(fd) => {
      className = mctx.className,
      globalNames = mctx.globalNames,
      globalVarNames = mctx.globalVarNames,
      funArities = Dict.insert(mctx.funArities, fd.name, Lst.length(fd.params)),
      adtClassByConstructor = mctx.adtClassByConstructor,
      adtConstructorArity = mctx.adtConstructorArity,
      options = mctx.options,
      mut lambdas = mctx.lambdas,
      mut lambdaIndex = mctx.lambdaIndex,
      mut lambdaClasses = mctx.lambdaClasses
    }
    TDVal(name, _, _) => {
      className = mctx.className,
      globalNames = Dict.insert(mctx.globalNames, name, ()),
      globalVarNames = mctx.globalVarNames,
      funArities = mctx.funArities,
      adtClassByConstructor = mctx.adtClassByConstructor,
      adtConstructorArity = mctx.adtConstructorArity,
      options = mctx.options,
      mut lambdas = mctx.lambdas,
      mut lambdaIndex = mctx.lambdaIndex,
      mut lambdaClasses = mctx.lambdaClasses
    }
    TDVar(name, _, _) => {
      className = mctx.className,
      globalNames = Dict.insert(mctx.globalNames, name, ()),
      globalVarNames = Dict.insert(mctx.globalVarNames, name, ()),
      funArities = mctx.funArities,
      adtClassByConstructor = mctx.adtClassByConstructor,
      adtConstructorArity = mctx.adtConstructorArity,
      options = mctx.options,
      mut lambdas = mctx.lambdas,
      mut lambdaIndex = mctx.lambdaIndex,
      mut lambdaClasses = mctx.lambdaClasses
    }
    TDSVal(name, _, _) => {
      className = mctx.className,
      globalNames = Dict.insert(mctx.globalNames, name, ()),
      globalVarNames = mctx.globalVarNames,
      funArities = mctx.funArities,
      adtClassByConstructor = mctx.adtClassByConstructor,
      adtConstructorArity = mctx.adtConstructorArity,
      options = mctx.options,
      mut lambdas = mctx.lambdas,
      mut lambdaIndex = mctx.lambdaIndex,
      mut lambdaClasses = mctx.lambdaClasses
    }
    TDSVar(name, _, _) => {
      className = mctx.className,
      globalNames = Dict.insert(mctx.globalNames, name, ()),
      globalVarNames = Dict.insert(mctx.globalVarNames, name, ()),
      funArities = mctx.funArities,
      adtClassByConstructor = mctx.adtClassByConstructor,
      adtConstructorArity = mctx.adtConstructorArity,
      options = mctx.options,
      mut lambdas = mctx.lambdas,
      mut lambdaIndex = mctx.lambdaIndex,
      mut lambdaClasses = mctx.lambdaClasses
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
            options = mctx.options,
            mut lambdas = mctx.lambdas,
            mut lambdaIndex = mctx.lambdaIndex,
      mut lambdaClasses = mctx.lambdaClasses
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
        options = mctx.options,
        mut lambdas = mctx.lambdas,
        mut lambdaIndex = mctx.lambdaIndex,
      mut lambdaClasses = mctx.lambdaClasses
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
    options = options,
    mut lambdas = [],
    mut lambdaIndex = 0,
    mut lambdaClasses = Dict.emptyStringDict()
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
    options = afterDecls.options,
    mut lambdas = afterDecls.lambdas,
    mut lambdaIndex = afterDecls.lambdaIndex,
    mut lambdaClasses = afterDecls.lambdaClasses
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
    SFun(async_, name, _tp, params, _rt, body) => {
      val scope = lambdaScope(ctx)
      val paramScope = bindParamNames(Dict.emptyStringDict(), params)
      val freeVars = getFreeVars(body, paramScope, scope)
      val capturing = !Lst.isEmpty(freeVars)
      val info = {
        body = body,
        async_ = async_,
        params = params,
        freeVars = freeVars,
        capturing = capturing,
        localFunNames = None,
        freeVarVars = captureVarNames(ctx, freeVars)
      }
      val id = allocLambdaId(ctx.mctx)
      emitLambdaBodyMethod(ctx, id, info)
      val lambdaPair = buildLambdaClass(ctx.mctx.className, id, Lst.length(params), capturing, async_)
      putLambdaClass(ctx.mctx, lambdaPair.0, lambdaPair.1)
      if (async_) {
        val payloadPair = buildAsyncLambdaPayloadClass(ctx.mctx.className, id, Lst.length(params), capturing)
        putLambdaClass(ctx.mctx, payloadPair.0, payloadPair.1)
      } else ()
      if (capturing) {
        CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfConstantInt(ctx.cf, Lst.length(freeVars)))
        CF.mbEmit1s(ctx.mb, Op.JvmOp.anewarray, CF.cfClassRef(ctx.cf, "java/lang/Object"))
        emitCaptureArrayEntries(ctx, freeVars, 0)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, lambdaPair.0))
        CF.mbEmit1(ctx.mb, Op.JvmOp.dupX1)
        CF.mbEmit1(ctx.mb, Op.JvmOp.swap)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, CF.cfMethodref(ctx.cf, lambdaPair.0, "<init>", "([Ljava/lang/Object;)V"))
      } else {
        CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, lambdaPair.0))
        CF.mbEmit1(ctx.mb, Op.JvmOp.dup)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, CF.cfMethodref(ctx.cf, lambdaPair.0, "<init>", "()V"))
      }

      val idx = bindLocal(ctx, name)
      storeLocal(ctx, idx)
    }
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

// Emit pattern — replaced by per-arm inline logic in emitExpr; kept as no-op for compatibility.
export fun emitPattern(_ctx: CodegenContext, _pattern: Ast.Pattern): Unit = ()

// ---------------------------------------------------------------------------
// Sub-pattern binding helpers (for nested PCon patterns)
// ---------------------------------------------------------------------------

// Emit bindings for a nested PCon pattern where `valueSlot` already holds the value.
// Returns a list of IFEQ positions (all needing backpatch to the arm miss target).
fun emitSubPatternBindings(ctx: CodegenContext, valueSlot: Int, pat: Ast.Pattern): List<Int> =
  match (pat) {
    PVar(name) => { ctx.locals := Dict.insert(ctx.locals, name, valueSlot); [] }
    PCon(ctorName, fields) =>
      match (Dict.get(ctx.mctx.adtClassByConstructor, ctorName)) {
        Some(adtClass) => {
          loadLocalSlot(ctx, valueSlot)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.instanceof_, CF.cfClassRef(ctx.cf, adtClass))
          val ifeq = CF.mbLength(ctx.mb)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
          val fieldIfeqs = emitSubPatConFields(ctx, valueSlot, adtClass, fields)
          ifeq :: fieldIfeqs
        }
        None => []
      }
    _ => []
  }

// Emit GETFIELD bindings for each field of a nested PCon constructor pattern.
fun emitSubPatConFields(ctx: CodegenContext, scrutSlot: Int, adtClass: String, fields: List<Ast.ConField>): List<Int> =
  match (fields) {
    [] => []
    f :: rest => {
      loadLocalSlot(ctx, scrutSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, adtClass))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.getfield, CF.cfFieldref(ctx.cf, adtClass, f.name, "Ljava/lang/Object;"))
      val thisIfeqs =
        match (f.pattern) {
          Some(PVar(bindName)) => {
            val slot = ctx.nextLocal
            ctx.nextLocal := slot + 1
            storeLocal(ctx, slot)
            ctx.locals := Dict.insert(ctx.locals, bindName, slot)
            []
          }
          Some(PWild) => { CF.mbEmit1(ctx.mb, Op.JvmOp.pop); [] }
          Some(nestedPat) => {
            val subSlot = ctx.nextLocal
            ctx.nextLocal := subSlot + 1
            storeLocal(ctx, subSlot)
            emitSubPatternBindings(ctx, subSlot, nestedPat)
          }
          None => { CF.mbEmit1(ctx.mb, Op.JvmOp.pop); [] }
        }
      Lst.append(thisIfeqs, emitSubPatConFields(ctx, scrutSlot, adtClass, rest))
    }
  }

// Backpatch all IFEQ positions in `ifeqs` to jump to `target`.
fun backpatchIfeqList(code: Array<Int>, ifeqs: List<Int>, target: Int): Unit =
  match (ifeqs) {
    [] => ()
    iq :: rest => { patchShort(code, iq + 1, target - iq); backpatchIfeqList(code, rest, target) }
  }

// ---------------------------------------------------------------------------
// PCons spine walk
// ---------------------------------------------------------------------------

// Walk a PCons spine emitting INSTANCEOF KCons checks and variable bindings at each level.
// Returns all IFEQ positions (to backpatch to the arm miss target).
// firstLevel: whether this is the outermost cons cell (controls arm-entry branch target).
fun emitConsSpine(ctx: CodegenContext, currentScrutSlot: Int, pat: Ast.Pattern, matchBaseState: CF.StackMapFrameState, firstLevel: Bool, accIfeqs: List<Int>): List<Int> =
  match (pat) {
    PCons(headPat, tailPat) => {
      loadLocalSlot(ctx, currentScrutSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.instanceof_, CF.cfClassRef(ctx.cf, KCONS))
      val levelIfeq = CF.mbLength(ctx.mb)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
      if (firstLevel) CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), Some(matchBaseState)) else ()
      emitConsHeadAndTail(ctx, currentScrutSlot, headPat, tailPat, matchBaseState, levelIfeq :: accIfeqs)
    }
    _ => accIfeqs
  }

fun emitConsHeadAndTail(ctx: CodegenContext, currentScrutSlot: Int, headPat: Ast.Pattern, tailPat: Ast.Pattern, matchBaseState: CF.StackMapFrameState, accIfeqs: List<Int>): List<Int> = {
  val headIfeqs =
    match (headPat) {
      PVar(name) => {
        loadLocalSlot(ctx, currentScrutSlot)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KCONS))
        CF.mbEmit1s(ctx.mb, Op.JvmOp.getfield, CF.cfFieldref(ctx.cf, KCONS, "head", "Ljava/lang/Object;"))
        val slot = ctx.nextLocal
        ctx.nextLocal := slot + 1
        ctx.locals := Dict.insert(ctx.locals, name, slot)
        storeLocal(ctx, slot)
        []
      }
      PCon(ctorName, fields) =>
        match (Dict.get(ctx.mctx.adtClassByConstructor, ctorName)) {
          Some(adtClass) => {
            loadLocalSlot(ctx, currentScrutSlot)
            CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KCONS))
            CF.mbEmit1s(ctx.mb, Op.JvmOp.getfield, CF.cfFieldref(ctx.cf, KCONS, "head", "Ljava/lang/Object;"))
            CF.mbEmit1s(ctx.mb, Op.JvmOp.instanceof_, CF.cfClassRef(ctx.cf, adtClass))
            val ifeqHead = CF.mbLength(ctx.mb)
            CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
            CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), Some(matchBaseState))
            val fieldIfeqs = emitConsHeadAdtFields(ctx, currentScrutSlot, adtClass, fields)
            ifeqHead :: fieldIfeqs
          }
          None => []
        }
      _ => []
    }
  emitConsTailBinding(ctx, currentScrutSlot, tailPat, matchBaseState, Lst.append(accIfeqs, headIfeqs))
}

fun emitConsHeadAdtFields(ctx: CodegenContext, currentScrutSlot: Int, adtClass: String, fields: List<Ast.ConField>): List<Int> =
  match (fields) {
    [] => []
    f :: rest =>
      match (f.pattern) {
        Some(PVar(bindName)) => {
          loadLocalSlot(ctx, currentScrutSlot)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KCONS))
          CF.mbEmit1s(ctx.mb, Op.JvmOp.getfield, CF.cfFieldref(ctx.cf, KCONS, "head", "Ljava/lang/Object;"))
          CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, adtClass))
          CF.mbEmit1s(ctx.mb, Op.JvmOp.getfield, CF.cfFieldref(ctx.cf, adtClass, f.name, "Ljava/lang/Object;"))
          val slot = ctx.nextLocal
          ctx.nextLocal := slot + 1
          ctx.locals := Dict.insert(ctx.locals, bindName, slot)
          storeLocal(ctx, slot)
          emitConsHeadAdtFields(ctx, currentScrutSlot, adtClass, rest)
        }
        _ => emitConsHeadAdtFields(ctx, currentScrutSlot, adtClass, rest)
      }
  }

fun emitConsTailBinding(ctx: CodegenContext, currentScrutSlot: Int, tailPat: Ast.Pattern, matchBaseState: CF.StackMapFrameState, accIfeqs: List<Int>): List<Int> =
  match (tailPat) {
    PCons(_, _) => {
      loadLocalSlot(ctx, currentScrutSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KCONS))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.getfield, CF.cfFieldref(ctx.cf, KCONS, "tail", "Lkestrel/runtime/KList;"))
      val tailSlot = ctx.nextLocal
      ctx.nextLocal := tailSlot + 1
      storeLocal(ctx, tailSlot)
      emitConsSpine(ctx, tailSlot, tailPat, matchBaseState, False, accIfeqs)
    }
    PVar(name) => {
      loadLocalSlot(ctx, currentScrutSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KCONS))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.getfield, CF.cfFieldref(ctx.cf, KCONS, "tail", "Lkestrel/runtime/KList;"))
      val slot = ctx.nextLocal
      ctx.nextLocal := slot + 1
      ctx.locals := Dict.insert(ctx.locals, name, slot)
      storeLocal(ctx, slot)
      accIfeqs
    }
    PList([], _) => {
      // h :: [] — check tail is KNil.
      loadLocalSlot(ctx, currentScrutSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KCONS))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.getfield, CF.cfFieldref(ctx.cf, KCONS, "tail", "Lkestrel/runtime/KList;"))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.instanceof_, CF.cfClassRef(ctx.cf, KNIL))
      val ifeqTailNil = CF.mbLength(ctx.mb)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
      ifeqTailNil :: accIfeqs
    }
    _ => accIfeqs
  }

// ---------------------------------------------------------------------------
// PList element pattern helper
// ---------------------------------------------------------------------------

// Emit INSTANCEOF KCons checks and head bindings for a [p1, p2, ...rest] list pattern.
// Returns all IFEQ positions (accumulated in reverse; to backpatch to arm miss target).
fun emitListPatternElems(ctx: CodegenContext, scrutSlot: Int, pats: List<Ast.Pattern>, restOpt: Option<String>, matchBaseState: CF.StackMapFrameState, accIfeqs: List<Int>): List<Int> =
  match (pats) {
    [] =>
      match (restOpt) {
        None => {
          loadLocalSlot(ctx, scrutSlot)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.instanceof_, CF.cfClassRef(ctx.cf, KNIL))
          val ifeq = CF.mbLength(ctx.mb)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
          ifeq :: accIfeqs
        }
        Some(restName) => {
          ctx.locals := Dict.insert(ctx.locals, restName, scrutSlot)
          accIfeqs
        }
      }
    p :: restPats => {
      loadLocalSlot(ctx, scrutSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.instanceof_, CF.cfClassRef(ctx.cf, KCONS))
      val ifeq = CF.mbLength(ctx.mb)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
      CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), Some(matchBaseState))
      match (p) {
        PVar(name) => {
          loadLocalSlot(ctx, scrutSlot)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KCONS))
          CF.mbEmit1s(ctx.mb, Op.JvmOp.getfield, CF.cfFieldref(ctx.cf, KCONS, "head", "Ljava/lang/Object;"))
          val slot = ctx.nextLocal
          ctx.nextLocal := slot + 1
          ctx.locals := Dict.insert(ctx.locals, name, slot)
          storeLocal(ctx, slot)
        }
        _ => ()
      }
      loadLocalSlot(ctx, scrutSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KCONS))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.getfield, CF.cfFieldref(ctx.cf, KCONS, "tail", "Lkestrel/runtime/KList;"))
      val tailSlot = ctx.nextLocal
      ctx.nextLocal := tailSlot + 1
      storeLocal(ctx, tailSlot)
      emitListPatternElems(ctx, tailSlot, restPats, restOpt, matchBaseState, ifeq :: accIfeqs)
    }
  }

// ---------------------------------------------------------------------------
// PTuple element pattern helper
// ---------------------------------------------------------------------------

// Emit KRecord.get() extractions for a tuple pattern (a, b, ...).
// Returns accumulated IFEQ positions (for literal sub-patterns) to backpatch.
fun emitTuplePatternElems(ctx: CodegenContext, scrutSlot: Int, pats: List<Ast.Pattern>, idx: Int, missIfeqs: List<Int>): List<Int> =
  match (pats) {
    [] => missIfeqs
    p :: rest => {
      val thisMiss =
        match (p) {
          PVar(name) => {
            loadLocalSlot(ctx, scrutSlot)
            CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KRECORD))
            CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfString(ctx.cf, "${idx}"))
            CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, KRECORD, "get", "(Ljava/lang/String;)Ljava/lang/Object;"))
            val slot = ctx.nextLocal
            ctx.nextLocal := slot + 1
            ctx.locals := Dict.insert(ctx.locals, name, slot)
            storeLocal(ctx, slot)
            []
          }
          PWild => {
            val toss = ctx.nextLocal
            ctx.nextLocal := toss + 1
            loadLocalSlot(ctx, scrutSlot)
            CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KRECORD))
            CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfString(ctx.cf, "${idx}"))
            CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, KRECORD, "get", "(Ljava/lang/String;)Ljava/lang/Object;"))
            storeLocal(ctx, toss)
            []
          }
          PLit(litKind, litRaw) => {
            val tmp = ctx.nextLocal
            ctx.nextLocal := tmp + 1
            loadLocalSlot(ctx, scrutSlot)
            CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KRECORD))
            CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfString(ctx.cf, "${idx}"))
            CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, KRECORD, "get", "(Ljava/lang/String;)Ljava/lang/Object;"))
            storeLocal(ctx, tmp)
            val ifeq =
              if (litKind == "float" & litRaw == "NaN") {
                loadLocalSlot(ctx, tmp)
                CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, CF.cfMethodref(ctx.cf, RUNTIME, "floatIsNan", "(Ljava/lang/Object;)Ljava/lang/Boolean;"))
                CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, BOOLEAN, "booleanValue", "()Z"))
                val iq = CF.mbLength(ctx.mb)
                CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
                iq
              } else {
                loadLocalSlot(ctx, tmp)
                emitExpr(ctx, ELit(litKind, litRaw))
                CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, CF.cfMethodref(ctx.cf, RUNTIME, "equals", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;"))
                CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, BOOLEAN, "booleanValue", "()Z"))
                val iq = CF.mbLength(ctx.mb)
                CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
                iq
              }
            [ifeq]
          }
          _ => []
        }
      emitTuplePatternElems(ctx, scrutSlot, rest, idx + 1, Lst.append(missIfeqs, thisMiss))
    }
  }

// ---------------------------------------------------------------------------
// Arm body helpers
// ---------------------------------------------------------------------------

// Emit the body of a conditional arm (one with IFEQ guards).
// Backpatches all `ifeqs` to the miss target (position after the GOTO).
// Returns a list of GOTO-to-matchEnd positions to backpatch later.
fun emitArmBodyConditional(ctx: CodegenContext, body: Ast.Expr, ifeqs: List<Int>, matchResultSlot: Int, matchBaseState: CF.StackMapFrameState, code: Array<Int>): List<Int> = {
  val pushes = thenArmPushesValue(body)
  emitExpr(ctx, body)
  val gotoOpt =
    if (pushes) {
      storeLocal(ctx, matchResultSlot)
      val gotoPos = CF.mbLength(ctx.mb)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.goto_, 0)
      Some(gotoPos)
    } else
      None
  val afterGoto = CF.mbLength(ctx.mb)
  backpatchIfeqList(code, ifeqs, afterGoto)
  CF.mbAddBranchTarget(ctx.mb, afterGoto, Some(matchBaseState))
  match (gotoOpt) {
    Some(gotoPos) => [gotoPos]
    None => []
  }
}

// Emit the body of an unconditional arm (PWild, PVar — no IFEQ guard).
// Returns a list of GOTO-to-matchEnd positions.
fun emitArmBodyUnconditional(ctx: CodegenContext, body: Ast.Expr, matchResultSlot: Int): List<Int> = {
  val pushes = thenArmPushesValue(body)
  emitExpr(ctx, body)
  if (pushes) {
    storeLocal(ctx, matchResultSlot)
    val gotoPos = CF.mbLength(ctx.mb)
    CF.mbEmit1s(ctx.mb, Op.JvmOp.goto_, 0)
    [gotoPos]
  } else
    []
}

// Emit a single-field binding for a constructor with one payload field (e.g. Some, Ok, Err).
// fieldDesc: JVM field descriptor string (e.g. "Ljava/lang/Object;").
fun emitSingleFieldBinding(ctx: CodegenContext, scrutSlot: Int, ctorClass: String, fieldName: String, fieldDesc: String, fieldPat: Option<Ast.Pattern>): List<Int> =
  match (fieldPat) {
    Some(PVar(name)) => {
      loadLocalSlot(ctx, scrutSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, ctorClass))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.getfield, CF.cfFieldref(ctx.cf, ctorClass, fieldName, fieldDesc))
      val slot = ctx.nextLocal
      ctx.nextLocal := slot + 1
      ctx.locals := Dict.insert(ctx.locals, name, slot)
      storeLocal(ctx, slot)
      []
    }
    Some(PWild) => {
      loadLocalSlot(ctx, scrutSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, ctorClass))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.getfield, CF.cfFieldref(ctx.cf, ctorClass, fieldName, fieldDesc))
      CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
      []
    }
    Some(nestedPat) => {
      loadLocalSlot(ctx, scrutSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, ctorClass))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.getfield, CF.cfFieldref(ctx.cf, ctorClass, fieldName, fieldDesc))
      val innerSlot = ctx.nextLocal
      ctx.nextLocal := innerSlot + 1
      storeLocal(ctx, innerSlot)
      emitSubPatternBindings(ctx, innerSlot, nestedPat)
    }
    None => {
      loadLocalSlot(ctx, scrutSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, ctorClass))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.getfield, CF.cfFieldref(ctx.cf, ctorClass, fieldName, fieldDesc))
      CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
      []
    }
  }

// Helper: extract the pattern of the first ConField (or None if empty).
fun firstFieldPat(fields: List<Ast.ConField>): Option<Ast.Pattern> =
  match (fields) {
    [] => None
    f :: _ => f.pattern
  }

// Helper: extract the pattern of the second ConField (or None if fewer than 2 fields).
fun secondFieldPat(fields: List<Ast.ConField>): Option<Ast.Pattern> =
  match (fields) {
    [] => None
    _ :: rest =>
      match (rest) {
        [] => None
        f :: _ => f.pattern
      }
  }

// ---------------------------------------------------------------------------
// Main arm dispatcher
// ---------------------------------------------------------------------------

// Emit one match arm (test + bindings + body + GOTO). Returns GOTO-to-matchEnd positions.
fun emitOneArm(ctx: CodegenContext, arm: Ast.Case_, scrutSlot: Int, matchResultSlot: Int, matchBaseState: CF.StackMapFrameState, code: Array<Int>): List<Int> =
  match (arm.pattern) {
    PWild =>
      emitArmBodyUnconditional(ctx, arm.body, matchResultSlot)

    PVar(name) => {
      val slot = ctx.nextLocal
      ctx.nextLocal := slot + 1
      ctx.locals := Dict.insert(ctx.locals, name, slot)
      loadLocalSlot(ctx, scrutSlot)
      storeLocal(ctx, slot)
      emitArmBodyUnconditional(ctx, arm.body, matchResultSlot)
    }

    PLit(kind, raw) => {
      val ifeq =
        if (kind == "float" & raw == "NaN") {
          loadLocalSlot(ctx, scrutSlot)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, CF.cfMethodref(ctx.cf, RUNTIME, "floatIsNan", "(Ljava/lang/Object;)Ljava/lang/Boolean;"))
          CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, BOOLEAN, "booleanValue", "()Z"))
          val iq = CF.mbLength(ctx.mb)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
          iq
        } else {
          loadLocalSlot(ctx, scrutSlot)
          emitExpr(ctx, ELit(kind, raw))
          CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, CF.cfMethodref(ctx.cf, RUNTIME, "equals", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;"))
          CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, BOOLEAN, "booleanValue", "()Z"))
          val iq = CF.mbLength(ctx.mb)
          CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
          iq
        }
      CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), Some(matchBaseState))
      emitArmBodyConditional(ctx, arm.body, [ifeq], matchResultSlot, matchBaseState, code)
    }

    PCon(ctorName, fields) => {
      if (ctorName == "None") {
        loadLocalSlot(ctx, scrutSlot)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.instanceof_, CF.cfClassRef(ctx.cf, KNONE))
        val ifeq = CF.mbLength(ctx.mb)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
        CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), Some(matchBaseState))
        emitArmBodyConditional(ctx, arm.body, [ifeq], matchResultSlot, matchBaseState, code)
      } else if (ctorName == "Some") {
        loadLocalSlot(ctx, scrutSlot)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.instanceof_, CF.cfClassRef(ctx.cf, KSOME))
        val ifeq = CF.mbLength(ctx.mb)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
        CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), Some(matchBaseState))
        val fieldPat = firstFieldPat(fields)
        val subIfeqs = emitSingleFieldBinding(ctx, scrutSlot, KSOME, "value", "Ljava/lang/Object;", fieldPat)
        emitArmBodyConditional(ctx, arm.body, ifeq :: subIfeqs, matchResultSlot, matchBaseState, code)
      } else if (ctorName == "Nil") {
        loadLocalSlot(ctx, scrutSlot)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.instanceof_, CF.cfClassRef(ctx.cf, KNIL))
        val ifeq = CF.mbLength(ctx.mb)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
        CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), Some(matchBaseState))
        emitArmBodyConditional(ctx, arm.body, [ifeq], matchResultSlot, matchBaseState, code)
      } else if (ctorName == "Cons") {
        loadLocalSlot(ctx, scrutSlot)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.instanceof_, CF.cfClassRef(ctx.cf, KCONS))
        val ifeq = CF.mbLength(ctx.mb)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
        CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), Some(matchBaseState))
        val headPat = firstFieldPat(fields)
        val tailPat = secondFieldPat(fields)
        val headIfeqs = emitSingleFieldBinding(ctx, scrutSlot, KCONS, "head", "Ljava/lang/Object;", headPat)
        val tailIfeqs = emitSingleFieldBinding(ctx, scrutSlot, KCONS, "tail", "Lkestrel/runtime/KList;", tailPat)
        emitArmBodyConditional(ctx, arm.body, Lst.append(ifeq :: headIfeqs, tailIfeqs), matchResultSlot, matchBaseState, code)
      } else if (ctorName == "Ok" | ctorName == "Err") {
        val ctorClass = if (ctorName == "Ok") KOK else KERR
        loadLocalSlot(ctx, scrutSlot)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.instanceof_, CF.cfClassRef(ctx.cf, ctorClass))
        val ifeq = CF.mbLength(ctx.mb)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
        CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), Some(matchBaseState))
        val fieldPat = firstFieldPat(fields)
        val subIfeqs = emitSingleFieldBinding(ctx, scrutSlot, ctorClass, "value", "Ljava/lang/Object;", fieldPat)
        emitArmBodyConditional(ctx, arm.body, ifeq :: subIfeqs, matchResultSlot, matchBaseState, code)
      } else if (ctorName == "True" | ctorName == "False") {
        val boolField = if (ctorName == "True") "TRUE" else "FALSE"
        loadLocalSlot(ctx, scrutSlot)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.getstatic, CF.cfFieldref(ctx.cf, BOOLEAN, boolField, "Ljava/lang/Boolean;"))
        CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic, CF.cfMethodref(ctx.cf, RUNTIME, "equals", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;"))
        CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, BOOLEAN, "booleanValue", "()Z"))
        val ifeq = CF.mbLength(ctx.mb)
        CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
        CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), Some(matchBaseState))
        emitArmBodyConditional(ctx, arm.body, [ifeq], matchResultSlot, matchBaseState, code)
      } else {
        // User-defined ADT constructor
        match (Dict.get(ctx.mctx.adtClassByConstructor, ctorName)) {
          Some(adtClass) => {
            loadLocalSlot(ctx, scrutSlot)
            CF.mbEmit1s(ctx.mb, Op.JvmOp.instanceof_, CF.cfClassRef(ctx.cf, adtClass))
            val ifeq = CF.mbLength(ctx.mb)
            CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
            CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), Some(matchBaseState))
            val fieldIfeqs = emitSubPatConFields(ctx, scrutSlot, adtClass, fields)
            emitArmBodyConditional(ctx, arm.body, ifeq :: fieldIfeqs, matchResultSlot, matchBaseState, code)
          }
          None =>
            // Unknown constructor — fall through unconditionally
            emitArmBodyUnconditional(ctx, arm.body, matchResultSlot)
        }
      }
    }

    PList(elems, restOpt) =>
      match (elems) {
        [] =>
          match (restOpt) {
            None => {
              // [] — empty list pattern
              loadLocalSlot(ctx, scrutSlot)
              CF.mbEmit1s(ctx.mb, Op.JvmOp.instanceof_, CF.cfClassRef(ctx.cf, KNIL))
              val ifeq = CF.mbLength(ctx.mb)
              CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
              CF.mbAddBranchTarget(ctx.mb, CF.mbLength(ctx.mb), Some(matchBaseState))
              emitArmBodyConditional(ctx, arm.body, [ifeq], matchResultSlot, matchBaseState, code)
            }
            Some(restName) => {
              // [...rest] — matches any list, bind it unconditionally
              ctx.locals := Dict.insert(ctx.locals, restName, scrutSlot)
              emitArmBodyUnconditional(ctx, arm.body, matchResultSlot)
            }
          }
        _ => {
          // [p1, p2, ...] non-empty element list
          val ifeqs = emitListPatternElems(ctx, scrutSlot, elems, restOpt, matchBaseState, [])
          emitArmBodyConditional(ctx, arm.body, ifeqs, matchResultSlot, matchBaseState, code)
        }
      }

    PCons(headPat, tailPat) => {
      val ifeqs = emitConsSpine(ctx, scrutSlot, PCons(headPat, tailPat), matchBaseState, True, [])
      emitArmBodyConditional(ctx, arm.body, ifeqs, matchResultSlot, matchBaseState, code)
    }

    PTuple(pats) => {
      // INSTANCEOF KRecord test (no arm-entry frame — PTuple doesn't add one per TS reference).
      loadLocalSlot(ctx, scrutSlot)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.instanceof_, CF.cfClassRef(ctx.cf, KRECORD))
      val ifNotTuple = CF.mbLength(ctx.mb)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.ifeq, 0)
      val elemMissIfeqs = emitTuplePatternElems(ctx, scrutSlot, pats, 0, [])
      emitArmBodyConditional(ctx, arm.body, ifNotTuple :: elemMissIfeqs, matchResultSlot, matchBaseState, code)
    }
  }

// ---------------------------------------------------------------------------
// Full match arm emitter
// ---------------------------------------------------------------------------

// Emit all match arms with real JVM branching.
// Returns the list of GOTO positions that need to be backpatched to matchEnd.
fun emitMatchArmsFull(ctx: CodegenContext, arms: List<Ast.Case_>, scrutSlot: Int, matchResultSlot: Int, savedNextLocal: Int, matchBaseState: CF.StackMapFrameState, code: Array<Int>): List<Int> =
  match (arms) {
    [] => []
    arm :: rest => {
      ctx.nextLocal := savedNextLocal
      val savedLocals = ctx.locals
      val armEndLabels = emitOneArm(ctx, arm, scrutSlot, matchResultSlot, matchBaseState, code)
      ctx.locals := savedLocals
      Lst.append(armEndLabels, emitMatchArmsFull(ctx, rest, scrutSlot, matchResultSlot, savedNextLocal, matchBaseState, code))
    }
  }

// emitMatchArmsStub was removed in S17-33 when ETry gained real JVM exception dispatch.

// Helper extracted from emitExpr to avoid typechecker OOM on large match bodies.
fun emitEThrow(ctx: CodegenContext, e: Ast.Expr): Unit = {
  emitExpr(ctx, e)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.new_, CF.cfClassRef(ctx.cf, K_EXCEPTION))
  CF.mbEmit1(ctx.mb, Op.JvmOp.dupX1)
  CF.mbEmit1(ctx.mb, Op.JvmOp.swap)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.invokespecial, CF.cfMethodref(ctx.cf, K_EXCEPTION, "<init>", "(Ljava/lang/Object;)V"))
  CF.mbEmit1(ctx.mb, Op.JvmOp.athrow)
}

// Helper extracted from emitExpr to avoid typechecker OOM on large match bodies.
fun emitETry(ctx: CodegenContext, block: Ast.Block_, varOpt: Option<String>, cases: List<Ast.Case_>): Unit = {
  // Allocate the try-result slot.
  val tryResultSlot = ctx.nextLocal
  ctx.nextLocal := ctx.nextLocal + 1
  // --- Try body ---
  val tryStart = CF.mbLength(ctx.mb)
  CF.mbAddBranchTarget(ctx.mb, tryStart, Some(CF.paramOnlyFrame(ctx.nextLocal)))
  emitBlockStmts(ctx, block.stmts)
  emitExpr(ctx, block.result)
  storeLocal(ctx, tryResultSlot)
  val gotoAfterTry = CF.mbLength(ctx.mb)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.goto_, 0)   // placeholder — backpatched to afterCatch
  // --- Handler setup ---
  val handlerStart = CF.mbLength(ctx.mb)
  val tryBodyExtra = estimateBodyLocals(EBlock(block))
  val handlerNumLocals = if (ctx.nextLocal + tryBodyExtra > 70) ctx.nextLocal + tryBodyExtra else 70
  val throwableClassIdx = CF.cfClassRef(ctx.cf, "java/lang/Throwable")
  CF.mbAddBranchTarget(ctx.mb, handlerStart, Some(CF.exceptionHandlerFrame(handlerNumLocals, throwableClassIdx)))
  CF.mbAddException(ctx.mb, tryStart, handlerStart, handlerStart, throwableClassIdx)
  // --- normalizeCaught dispatch ---
  val EXN_SLOT = 57
  val PAYLOAD_SLOT = 56
  storeLocal(ctx, EXN_SLOT)
  loadLocalSlot(ctx, EXN_SLOT)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, throwableClassIdx)
  // Push ArithmeticOverflow class string (or null).
  match (Dict.get(ctx.mctx.adtClassByConstructor, "ArithmeticOverflow")) {
    Some(c) => CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfString(ctx.cf, c))
    None => CF.mbEmit1(ctx.mb, Op.JvmOp.aconstNull)
  }
  // Push DivideByZero class string (or null).
  match (Dict.get(ctx.mctx.adtClassByConstructor, "DivideByZero")) {
    Some(c) => CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfString(ctx.cf, c))
    None => CF.mbEmit1(ctx.mb, Op.JvmOp.aconstNull)
  }
  // Push Cancelled class string (or null).
  match (Dict.get(ctx.mctx.adtClassByConstructor, "Cancelled")) {
    Some(c) => CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfString(ctx.cf, c))
    None => CF.mbEmit1(ctx.mb, Op.JvmOp.aconstNull)
  }
  CF.mbEmit1s(ctx.mb, Op.JvmOp.invokestatic,
    CF.cfMethodref(ctx.cf, RUNTIME, "normalizeCaught",
      "(Ljava/lang/Throwable;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/Object;"))
  storeLocal(ctx, PAYLOAD_SLOT)
  // Bind varOpt name to PAYLOAD_SLOT if present.
  val prevVarOpt = match (varOpt) {
    Some(name) => {
      val prev = Dict.get(ctx.locals, name)
      ctx.locals := Dict.insert(ctx.locals, name, PAYLOAD_SLOT)
      prev
    }
    None => None
  }
  // --- Catch arm dispatch ---
  val catchBaseState = CF.paramOnlyFrame(if (ctx.nextLocal > 58) ctx.nextLocal else 58)
  val savedNextLocal = ctx.nextLocal
  val code = CF.mbGetCode(ctx.mb)
  val catchEndLabels = emitMatchArmsFull(ctx, cases, PAYLOAD_SLOT, tryResultSlot, savedNextLocal, catchBaseState, code)
  // --- Rethrow if no arm matched ---
  val rethrowPos = CF.mbLength(ctx.mb)
  CF.mbAddBranchTarget(ctx.mb, rethrowPos, Some(catchBaseState))
  loadLocalSlot(ctx, EXN_SLOT)
  CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, throwableClassIdx)
  CF.mbEmit1(ctx.mb, Op.JvmOp.athrow)
  // --- Backpatch and result ---
  val afterCatch = CF.mbLength(ctx.mb)
  CF.mbAddBranchTarget(ctx.mb, afterCatch, Some(CF.paramOnlyFrame(ctx.nextLocal)))
  patchShort(code, gotoAfterTry + 1, afterCatch - gotoAfterTry)
  backpatchBreakJumps(code, catchEndLabels, afterCatch)
  // Restore varOpt binding.
  match (varOpt) {
    Some(name) => match (prevVarOpt) {
      Some(prev) => { ctx.locals := Dict.insert(ctx.locals, name, prev) }
      None => { ctx.locals := Dict.remove(ctx.locals, name) }
    }
    None => ()
  }
  loadLocalSlot(ctx, tryResultSlot)
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

// Helper extracted from emitExpr to reduce match body type complexity.
fun emitLitExpr(ctx: CodegenContext, kind: String, raw: String): Unit = {
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

// Helper extracted from emitExpr to reduce match body type complexity.
fun emitIdentExpr(ctx: CodegenContext, name: String): Unit = {
  val freeHit =
    match (ctx.freeVarToIndex) {
      Some(fvMap) => {
        match (Dict.get(fvMap, name)) {
          Some(idx) => {
            emitLoadFreeVarFromEnv(ctx, idx)
            if (Dict.member(ctx.freeVarVars, name)) emitVarUnbox(ctx) else ()
            True
          }
          None => False
        }
      }
      None => False
    }
  if (freeHit) ()
  else {
    val localFunHit =
      match (ctx.localFunNamesInEnv) {
        Some(funSet) =>
          if (Dict.member(funSet, name)) {
            emitLoadLocalFunFromEnv(ctx, name)
            True
          } else False
        None => False
      }
    if (localFunHit) ()
    else if (loadLocal(ctx, name)) {
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
}

// Helper extracted from emitExpr to reduce match body type complexity.
fun emitCallExpr(ctx: CodegenContext, fn: Ast.Expr, args: List<Ast.Expr>): Unit = {
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

// Helper extracted from emitExpr to reduce match body type complexity.
fun emitIfExpr(ctx: CodegenContext, c: Ast.Expr, t: Ast.Expr, eOpt: Option<Ast.Expr>): Unit = {
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

// Helper extracted from emitExpr to reduce match body type complexity.
fun emitWhileExpr(ctx: CodegenContext, c: Ast.Expr, b: Ast.Block_): Unit = {
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

// Helper extracted from emitExpr to reduce match body type complexity.
fun emitMatchExpr(ctx: CodegenContext, scrut: Ast.Expr, arms: List<Ast.Case_>): Unit = {
  emitExpr(ctx, scrut)
  val scrutSlot = 55
  val matchResultSlot = 54
  storeLocal(ctx, scrutSlot)
  pushNull(ctx)
  storeLocal(ctx, matchResultSlot)
  val numLocals = if (ctx.nextLocal > 56) ctx.nextLocal else 56
  val matchBaseState = CF.paramOnlyFrame(numLocals)
  val savedNextLocal = ctx.nextLocal
  val code = CF.mbGetCode(ctx.mb)
  val endLabels = emitMatchArmsFull(ctx, arms, scrutSlot, matchResultSlot, savedNextLocal, matchBaseState, code)
  val endPos = CF.mbLength(ctx.mb)
  CF.mbAddBranchTarget(ctx.mb, endPos, Some(matchBaseState))
  backpatchBreakJumps(code, endLabels, endPos)
  loadLocalSlot(ctx, matchResultSlot)
}

export fun emitExpr(ctx: CodegenContext, expr: Ast.Expr): Unit =
  match (expr) {
    ELit(kind, raw) => emitLitExpr(ctx, kind, raw)
    EIdent(name) => emitIdentExpr(ctx, name)
    ECall(fn, args) => emitCallExpr(ctx, fn, args)
    EField(obj, field) => {
      emitExpr(ctx, obj)
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KRECORD))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.ldcW, CF.cfString(ctx.cf, field))
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, KRECORD, "get", "(Ljava/lang/String;)Ljava/lang/Object;"))
    }
    EAwait(e) => {
      emitExpr(ctx, e);
      CF.mbEmit1s(ctx.mb, Op.JvmOp.checkcast, CF.cfClassRef(ctx.cf, KTASK));
      CF.mbEmit1s(ctx.mb, Op.JvmOp.invokevirtual, CF.cfMethodref(ctx.cf, KTASK, "get", "()Ljava/lang/Object;"))
    }
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
    EIf(c, t, eOpt) => emitIfExpr(ctx, c, t, eOpt)
    EWhile(c, b) => emitWhileExpr(ctx, c, b)
    EMatch(scrut, arms) => emitMatchExpr(ctx, scrut, arms)
    ELambda(async_, _tp, params, body) => emitLambdaExpr(ctx, async_, params, body)
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
    EThrow(e) => emitEThrow(ctx, e)
    ETry(block, varOpt, cases) => emitETry(ctx, block, varOpt, cases)
    EBlock(block) => {
      emitBlockStmts(ctx, block.stmts)
      emitExpr(ctx, block.result)
    }
    EIs(e, _t) => { emitExpr(ctx, e); CF.mbEmit1(ctx.mb, Op.JvmOp.pop); pushBoolBoxed(ctx, True) }
    ENever => pushNull(ctx)
  }
