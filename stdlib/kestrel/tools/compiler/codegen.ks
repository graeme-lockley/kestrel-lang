import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"
import * as Str from "kestrel:data/string"
import * as Ast from "kestrel:dev/parser/ast"
import {
  TDFun, TDExternFun, TDType, TDException, TDExport, TDVal, TDVar, TDSVal, TDSVar,
  EIDecl, TBAdt,
  ELit, EIdent, ECall, EField, EAwait, EUnary, EBinary, ECons, EPipe,
  EIf, EWhile, EMatch, ELambda, ETemplate, EList, ERecord, ETuple,
  EThrow, ETry, EBlock, EIs, ENever,
  LElem, LSpread,
  SVal, SVar, SAssign, SExpr, SFun, SBreak, SContinue,
  TmplLit, TmplExpr,
  PWild, PVar, PLit, PCon, PList, PCons, PTuple
} from "kestrel:dev/parser/ast"
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

export type CodegenContext = {
  cf: CF.ClassFileBuilder,
  mb: CF.MethodBuilder,
  locals: mut Dict<String, Int>,
  nextLocal: mut Int
}

export type JvmCodegenResult = {
  classes: Dict<String, ByteArray>
}

export fun newCodegenContext(cf: CF.ClassFileBuilder, mb: CF.MethodBuilder): CodegenContext = {
  cf = cf,
  mb = mb,
  mut locals = Dict.emptyStringDict(),
  mut nextLocal = 0
}

fun pushNull(ctx: CodegenContext): Unit = CF.mbEmit1(ctx.mb, Op.JvmOp.aconstNull)

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

export fun emitFunDecl(cf: CF.ClassFileBuilder, decl: Ast.FunDecl): Unit = {
  val desc = objectMethodDesc(Lst.length(decl.params))
  val mb = CF.cfAddMethod(cf, decl.name, desc, Op.Acc.public_ + Op.Acc.static_)
  val ctx = newCodegenContext(cf, mb)
  bindParams(ctx, decl.params)
  emitTailLoopScaffold(mb)
  emitExpr(ctx, decl.body)
  CF.mbEmit1(mb, Op.JvmOp.areturn)
  CF.mbSetMaxs(mb, 16, 32)
}

export fun emitExternFun(cf: CF.ClassFileBuilder, decl: Ast.ExternFunDecl): Unit = {
  val desc = if (Str.length(decl.jvmDesc) > 0) decl.jvmDesc else objectMethodDesc(Lst.length(decl.params))
  val mb = CF.cfAddMethod(cf, decl.name, desc, Op.Acc.public_ + Op.Acc.static_)
  pushNull(newCodegenContext(cf, mb))
  CF.mbEmit1(mb, Op.JvmOp.areturn)
  CF.mbSetMaxs(mb, 1, 8)
}

export fun emitVal(cf: CF.ClassFileBuilder, name: String, expr: Ast.Expr): Unit = {
  CF.cfAddField(cf, name, "Ljava/lang/Object;", Op.Acc.public_ + Op.Acc.static_ + Op.Acc.final_)
  val mb = CF.cfAddMethod(cf, "init$${name}", "()Ljava/lang/Object;", Op.Acc.private_ + Op.Acc.static_)
  val ctx = newCodegenContext(cf, mb)
  emitExpr(ctx, expr)
  CF.mbEmit1(mb, Op.JvmOp.areturn)
  CF.mbSetMaxs(mb, 8, 8)
}

export fun emitVar(cf: CF.ClassFileBuilder, name: String, expr: Ast.Expr): Unit = {
  CF.cfAddField(cf, name, "Ljava/lang/Object;", Op.Acc.public_ + Op.Acc.static_)
  val mb = CF.cfAddMethod(cf, "init$${name}", "()Ljava/lang/Object;", Op.Acc.private_ + Op.Acc.static_)
  val ctx = newCodegenContext(cf, mb)
  emitExpr(ctx, expr)
  CF.mbEmit1(mb, Op.JvmOp.areturn)
  CF.mbSetMaxs(mb, 8, 8)
}

fun emitCtorClass(moduleName: String, ctor: Ast.CtorDef): (String, ByteArray) = {
  val className = "${moduleName}$${ctor.name}"
  val cf = CF.newClassFile(className, "java/lang/Object", Op.Acc.public_ + Op.Acc.super_)
  emitDefaultCtor(cf);
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

fun emitDecl(moduleName: String, cf: CF.ClassFileBuilder, decl: Ast.TopDecl, classes: Dict<String, ByteArray>): Dict<String, ByteArray> =
  match (decl) {
    TDFun(funDecl) => { emitFunDecl(cf, funDecl); classes }
    TDExternFun(externDecl) => { emitExternFun(cf, externDecl); classes }
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
        EIDecl(d) => emitDecl(moduleName, cf, d, classes)
        _ => classes
      }
    }
    TDVal(name, _ann, expr) => { emitVal(cf, name, expr); classes }
    TDVar(name, _ann, expr) => { emitVar(cf, name, expr); classes }
    TDSVal(name, expr) => { emitVal(cf, name, expr); classes }
    TDSVar(name, expr) => { emitVar(cf, name, expr); classes }
    _ => classes
  }

fun emitDecls(moduleName: String, cf: CF.ClassFileBuilder, decls: List<Ast.TopDecl>, classes: Dict<String, ByteArray>): Dict<String, ByteArray> =
  match (decls) {
    [] => classes
    d :: rest => emitDecls(moduleName, cf, rest, emitDecl(moduleName, cf, d, classes))
  }

export fun jvmCodegen(moduleName: String, prog: Ast.Program): JvmCodegenResult = {
  val cf = CF.newClassFile(moduleName, "java/lang/Object", Op.Acc.public_ + Op.Acc.super_)
  emitDefaultCtor(cf)
  val extraClasses = emitDecls(moduleName, cf, prog.body, Dict.emptyStringDict())
  val mainBytes = CF.cfToBytes(cf)
  {
    classes = Dict.insert(extraClasses, moduleName, mainBytes)
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

fun emitBlockStmt(ctx: CodegenContext, stmt: Ast.Stmt): Unit =
  match (stmt) {
    SVal(name, _ann, e) => {
      emitExpr(ctx, e)
      val idx = bindLocal(ctx, name)
      storeLocal(ctx, idx)
    }
    SVar(name, _ann, e) => {
      emitExpr(ctx, e)
      val idx = bindLocal(ctx, name)
      storeLocal(ctx, idx)
    }
    SAssign(_target, rhs) => {
      emitExpr(ctx, rhs)
      CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
    }
    SExpr(e) => {
      emitExpr(ctx, e)
      CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
    }
    SFun(_async, _name, _tp, _params, _rt, _body) => ()
    SBreak => ()
    SContinue => ()
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
      } else {
        pushNull(ctx)
      }
    }
    EIdent(name) => if (!loadLocal(ctx, name)) pushNull(ctx) else ()
    ECall(fn, args) => {
      emitExpr(ctx, fn)
      CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
      emitExprList(ctx, args)
      pushNull(ctx)
    }
    EField(obj, _field) => {
      emitExpr(ctx, obj)
      CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
      pushNull(ctx)
    }
    EAwait(e) => { emitExpr(ctx, e); CF.mbEmit1(ctx.mb, Op.JvmOp.pop); pushNull(ctx) }
    EUnary(_op, e) => { emitExpr(ctx, e); CF.mbEmit1(ctx.mb, Op.JvmOp.pop); pushNull(ctx) }
    EBinary(_op, l, r) => { emitExpr(ctx, l); CF.mbEmit1(ctx.mb, Op.JvmOp.pop); emitExpr(ctx, r); CF.mbEmit1(ctx.mb, Op.JvmOp.pop); pushNull(ctx) }
    ECons(h, t) => { emitExpr(ctx, h); CF.mbEmit1(ctx.mb, Op.JvmOp.pop); emitExpr(ctx, t); CF.mbEmit1(ctx.mb, Op.JvmOp.pop); pushNull(ctx) }
    EPipe(_op, l, r) => { emitExpr(ctx, l); CF.mbEmit1(ctx.mb, Op.JvmOp.pop); emitExpr(ctx, r); CF.mbEmit1(ctx.mb, Op.JvmOp.pop); pushNull(ctx) }
    EIf(c, t, eOpt) => {
      emitExpr(ctx, c)
      CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
      emitExpr(ctx, t)
      match (eOpt) {
        Some(e) => { CF.mbEmit1(ctx.mb, Op.JvmOp.pop); emitExpr(ctx, e) }
        None => ()
      }
    }
    EWhile(c, b) => {
      emitExpr(ctx, c)
      CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
      emitBlockStmts(ctx, b.stmts)
      emitExpr(ctx, b.result)
      CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
      pushNull(ctx)
    }
    EMatch(scrut, arms) => {
      emitExpr(ctx, scrut)
      CF.mbEmit1(ctx.mb, Op.JvmOp.pop)
      emitMatchArms(ctx, arms)
    }
    ELambda(_async, _tp, _params, _body) => pushNull(ctx)
    ETemplate(parts) => { emitTemplateParts(ctx, parts); pushNull(ctx) }
    EList(elems) => { emitListElems(ctx, elems); pushNull(ctx) }
    ERecord(spreadOpt, fields) => {
      match (spreadOpt) {
        Some(sp) => { emitExpr(ctx, sp); CF.mbEmit1(ctx.mb, Op.JvmOp.pop) }
        None => ()
      }
      val values = Lst.map(fields, (f: Ast.RecField) => f.value)
      emitExprList(ctx, values)
      pushNull(ctx)
    }
    ETuple(xs) => { emitExprList(ctx, xs); pushNull(ctx) }
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
