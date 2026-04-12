//! Hindley-Milner type checker for parsed Kestrel programs.
//!
//! This module is the canonical self-hosted checker entry point used by
//! compiler and tooling code. It performs declaration prebinding, expression
//! inference, unification/subtyping checks, export-environment construction,
//! and diagnostic emission.
//!
//! The checker records inferred expression types per invocation and exposes
//! lookup through `TypecheckResult.getInferredType` so downstream consumers
//! (for example codegen and documentation extraction) can query inferred
//! information without relying on module-global mutable state.
import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"
import * as Str from "kestrel:data/string"
import * as Ast from "kestrel:dev/parser/ast"
import {
  ELit, EIdent, ECall, EField, EAwait, EUnary, EBinary, ECons, EPipe,
  EIf, EWhile, ELambda, ETemplate, EList, ERecord, ETuple,
  EMatch, EBlock, EThrow, ETry, EIs, ENever,
  SVal, SVar, SAssign, SExpr, SFun, SBreak, SContinue,
  PWild, PVar, PLit, PCon, PList, PCons, PTuple,
  LElem, LSpread,
  TDFun, TDType, TDVal, TDVar, TDSVal, TDSVar, TDSExpr,
  TBAdt, TBAlias,
  TmplLit, TmplExpr
} from "kestrel:dev/parser/ast"
import * as Diag from "kestrel:dev/typecheck/diagnostics"
import * as FA from "kestrel:dev/typecheck/from-ast"
import * as Rep from "kestrel:dev/typecheck/reporter"
import * as Ty from "kestrel:dev/typecheck/types"
import { TArrow, TApp, TRecord, TTuple, TNamespace } from "kestrel:dev/typecheck/types"

/// Map of in-scope value bindings to internal types.
export type TypeEnv = { items: Dict<String, Ty.InternalType> }

/// Snapshot of externally provided dependency exports used during checking.
///
/// This mirrors the shape produced by multi-module compilation pipelines:
///
/// - `exports`: value bindings exported by the dependency
/// - `exportedTypeAliases`: alias definitions exported by the dependency
/// - `exportedConstructors`: ADT constructors exported by the dependency
/// - `exportedTypeVisibility`: visibility map for exported type declarations
export type DependencyExportSnapshot = {
  exports: TypeEnv,
  exportedTypeAliases: Dict<String, Ty.InternalType>,
  exportedConstructors: Dict<String, Ty.InternalType>,
  exportedTypeVisibility: Dict<String, String>
}

/// Inputs that configure a single typecheck run.
///
/// `importBindings` and `typeAliasBindings` allow callers to inject resolved
/// bindings for cross-module checking. `sourceFile` is used in diagnostics.
export type TypecheckOptions = {
  importBindings: Option<TypeEnv>,
  typeAliasBindings: Option<Dict<String, Ty.InternalType>>,
  importOpaqueTypes: Option<List<String>>,
  sourceFile: String
}

/// Output of a full typecheck run.
///
/// - `ok`: true when no error-severity diagnostics were emitted
/// - `exports`: inferred/exported value environment for the module
/// - `exportedTypeAliases`: exported type alias map
/// - `exportedConstructors`: exported ADT constructor map
/// - `exportedTypeVisibility`: type-name -> visibility map
/// - `diagnostics`: collected diagnostics for this run
/// - `getInferredType`: per-run expression lookup (no shared global state)
export type TypecheckResult = {
  ok: Bool,
  exports: TypeEnv,
  exportedTypeAliases: Dict<String, Ty.InternalType>,
  exportedConstructors: Dict<String, Ty.InternalType>,
  exportedTypeVisibility: Dict<String, String>,
  diagnostics: List<Diag.Diagnostic>,
  getInferredType: (Ast.Expr) -> Option<Ty.InternalType>
}

type TcState = {
  reporter: Rep.Reporter,
  subst: mut Dict<Int, Ty.InternalType>,
  adtConstructors: Dict<String, List<String>>,
  ctorOwners: Dict<String, String>,
  sourceFile: String,
  inferredItems: mut List<InferredEntry>
}

type InferredEntry = { node: Ast.Expr, type_: Ty.InternalType }

type TypeRegistry = {
  typeAliases: Dict<String, Ty.InternalType>,
  ctorEnv: Dict<String, Ty.InternalType>,
  adtConstructors: Dict<String, List<String>>,
  ctorOwners: Dict<String, String>,
  exportedConstructors: Dict<String, Ty.InternalType>,
  exportedTypeVisibility: Dict<String, String>
}

/// Default options for standalone callers.
///
/// Most compiler code paths override imports and aliases explicitly.
export val defaultTypecheckOptions: TypecheckOptions = {
  importBindings = None,
  typeAliasBindings = None,
  importOpaqueTypes = None,
  sourceFile = ""
}

fun emptyTypeEnv(): TypeEnv = { items = Dict.emptyStringDict() }

fun envGet(env: TypeEnv, name: String): Option<Ty.InternalType> = Dict.get(env.items, name)

fun envInsert(env: TypeEnv, name: String, t: Ty.InternalType): TypeEnv =
  { items = Dict.insert(env.items, name, t) }

fun envUnion(left: TypeEnv, right: TypeEnv): TypeEnv =
  { items = Dict.union(left.items, right.items) }

fun rawToEnv(items: Dict<String, Ty.InternalType>): TypeEnv = { items = items }

fun mergeTypeMaps(left: Dict<String, Ty.InternalType>, right: Dict<String, Ty.InternalType>): Dict<String, Ty.InternalType> =
  Dict.union(left, right)

fun addDiag(state: TcState, code: String, message: String): Unit =
  Rep.report(state.reporter, {
    severity = Diag.Error,
    code = code,
    message = message,
    location = Diag.locationFileOnly(state.sourceFile),
    sourceLine = None,
    related = [],
    suggestion = None,
    hint = None
  })

fun apply(state: TcState, t: Ty.InternalType): Ty.InternalType = Ty.applySubstFull(state.subst, t)

fun setInferredLoop(entries: List<InferredEntry>, node: Ast.Expr, t: Ty.InternalType): List<InferredEntry> =
  { node = node, type_ = t } :: entries

fun putInferredType(state: TcState, node: Ast.Expr, t: Ty.InternalType): Unit = {
  state.inferredItems := setInferredLoop(state.inferredItems, node, t);
  ()
}

fun getInferredLoop(entries: List<InferredEntry>, node: Ast.Expr): Option<Ty.InternalType> =
  match (entries) {
    [] => None
    h :: rest => if (h.node == node) Some(h.type_) else getInferredLoop(rest, node)
  }

fun setInferredType(state: TcState, node: Ast.Expr, t: Ty.InternalType): Unit =
  putInferredType(state, node, t)

fun unifyEq(state: TcState, left: Ty.InternalType, right: Ty.InternalType): Bool =
  match (Ty.unify(state.subst, left, right)) {
    Ok(s2) => {
      state.subst := s2;
      True
    }
    Err(err) => {
      addDiag(state, Diag.CODES.type_.unify, "Cannot unify ${Ty.typeToString(err.0)} with ${Ty.typeToString(err.1)}");
      False
    }
  }

fun inferLiteral(kind: String): Ty.InternalType =
  if (kind == "int") Ty.tInt
  else if (kind == "float") Ty.tFloat
  else if (kind == "bool" | kind == "true" | kind == "false") Ty.tBool
  else if (kind == "string") Ty.tString
  else if (kind == "char") Ty.tChar
  else if (kind == "rune") Ty.tRune
  else Ty.tUnit

fun buildTypeParamScope(base: Dict<String, Ty.InternalType>, names: List<String>): Dict<String, Ty.InternalType> =
  match (names) {
    [] => base
    n :: rest => buildTypeParamScope(Dict.insert(base, n, Ty.freshVar()), rest)
  }

fun ctorReturnType(typeName: String, scope: Dict<String, Ty.InternalType>, typeParams: List<String>): Ty.InternalType = {
  val args = Lst.map(typeParams, (n: String) => Opt.getOrElse(Dict.get(scope, n), Ty.freshVar()))
  Ty.TApp(typeName, args)
}

fun convertTypes(types: List<Ast.AstType>, scope: Dict<String, Ty.InternalType>): List<Ty.InternalType> =
  Lst.map(types, (t: Ast.AstType) => FA.astTypeToInternalWithScope(t, scope, []))

fun registerCtorLoop(
  ctors: List<Ast.CtorDef>,
  scope: Dict<String, Ty.InternalType>,
  typeName: String,
  typeParams: List<String>,
  ctorEnv: Dict<String, Ty.InternalType>,
  ctorOwners: Dict<String, String>,
  ctorNames: List<String>
): (Dict<String, Ty.InternalType>, Dict<String, String>, List<String>) =
  match (ctors) {
    [] => (ctorEnv, ctorOwners, Lst.reverse(ctorNames))
    c :: rest => {
      val ret = ctorReturnType(typeName, scope, typeParams)
      val params = convertTypes(c.params, scope)
      val ctorType =
        if (Lst.isEmpty(params))
          Ty.generalize(Dict.emptyStringDict(), ret)
        else
          Ty.generalize(Dict.emptyStringDict(), Ty.TArrow(params, ret))
      registerCtorLoop(
        rest,
        scope,
        typeName,
        typeParams,
        Dict.insert(ctorEnv, c.name, ctorType),
        Dict.insert(ctorOwners, c.name, typeName),
        c.name :: ctorNames
      )
    }
  }

fun registerTypeDecl(reg: TypeRegistry, td: Ast.TypeDecl): TypeRegistry = {
  val scope = buildTypeParamScope(reg.typeAliases, td.typeParams)
  val named = ctorReturnType(td.name, scope, td.typeParams)
  val vis = Dict.insert(reg.exportedTypeVisibility, td.name, td.visibility)
  match (td.body) {
    TBAlias(bodyType) => {
      val aliasType = FA.astTypeToInternalWithScope(bodyType, scope, [])
      {
        typeAliases = Dict.insert(reg.typeAliases, td.name, aliasType),
        ctorEnv = reg.ctorEnv,
        adtConstructors = reg.adtConstructors,
        ctorOwners = reg.ctorOwners,
        exportedConstructors = reg.exportedConstructors,
        exportedTypeVisibility = vis
      }
    }
    TBAdt(ctors) => {
      val out = registerCtorLoop(ctors, scope, td.name, td.typeParams, reg.ctorEnv, reg.ctorOwners, [])
      val exportedCtors =
        if (td.visibility == "export")
          Lst.foldl(out.2, reg.exportedConstructors, (acc: Dict<String, Ty.InternalType>, name: String) =>
            Dict.insert(acc, name, Opt.getOrElse(Dict.get(out.0, name), named)))
        else
          reg.exportedConstructors
      {
        typeAliases = Dict.insert(reg.typeAliases, td.name, named),
        ctorEnv = out.0,
        adtConstructors = Dict.insert(reg.adtConstructors, td.name, out.2),
        ctorOwners = out.1,
        exportedConstructors = exportedCtors,
        exportedTypeVisibility = vis
      }
    }
  }
}

fun paramTypes(params: List<Ast.Param>, scope: Dict<String, Ty.InternalType>): List<Ty.InternalType> =
  match (params) {
    [] => []
    p :: rest => {
      val pt = match (p.type_) {
        Some(t) => FA.astTypeToInternalWithScope(t, scope, [])
        None => Ty.freshVar()
      }
      pt :: paramTypes(rest, scope)
    }
  }

fun namesFromParams(params: List<Ast.Param>): List<String> =
  match (params) {
    [] => []
    p :: rest => p.name :: namesFromParams(rest)
  }

fun bindParams(env: TypeEnv, names: List<String>, types: List<Ty.InternalType>): TypeEnv =
  match (names) {
    [] => env
    n :: rest =>
      match (types) {
        [] => env
        t :: tail => bindParams(envInsert(env, n, t), rest, tail)
      }
  }

fun registerFunSig(reg: Dict<String, Ty.InternalType>, typeAliases: Dict<String, Ty.InternalType>, fd: Ast.FunDecl): Dict<String, Ty.InternalType> = {
  val scope = buildTypeParamScope(typeAliases, fd.typeParams)
  val ps = paramTypes(fd.params, scope)
  val ret = FA.astTypeToInternalWithScope(fd.retType, scope, [])
  Dict.insert(reg, fd.name, Ty.generalize(Dict.emptyStringDict(), Ty.TArrow(ps, ret)))
}

fun inferExprs(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, exprs: List<Ast.Expr>): List<Ty.InternalType> =
  match (exprs) {
    [] => []
    e :: rest => inferExpr(state, env, typeAliases, e) :: inferExprs(state, env, typeAliases, rest)
  }

fun inferListElems(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, elems: List<Ast.ListElem>, elemType: Ty.InternalType): Unit =
  match (elems) {
    [] => ()
    h :: rest => {
      match (h) {
        LElem(e) => { val et = inferExpr(state, env, typeAliases, e); unifyEq(state, et, elemType); () }
        LSpread(e) => { val et = inferExpr(state, env, typeAliases, e); unifyEq(state, et, Ty.TApp("List", [elemType])); () }
      };
      inferListElems(state, env, typeAliases, rest, elemType)
    }
  }

fun inferStmtList(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, stmts: List<Ast.Stmt>): TypeEnv =
  match (stmts) {
    [] => env
    h :: rest => {
      val env2 =
        match (h) {
          SVal(name, ann, expr) => {
            val t = inferExpr(state, env, typeAliases, expr)
            match (ann) {
              Some(astType) => { unifyEq(state, t, FA.astTypeToInternalWithScope(astType, typeAliases, [])); () }
              None => ()
            };
            envInsert(env, name, Ty.generalize(env.items, apply(state, t)))
          }
          SVar(name, ann, expr) => {
            val t = inferExpr(state, env, typeAliases, expr)
            match (ann) {
              Some(astType) => { unifyEq(state, t, FA.astTypeToInternalWithScope(astType, typeAliases, [])); () }
              None => ()
            };
            envInsert(env, name, apply(state, t))
          }
          SExpr(expr) => { inferExpr(state, env, typeAliases, expr); env }
          SFun(async_, name, typeParams, params, retType, body) => {
            val scope = buildTypeParamScope(typeAliases, typeParams)
            val ps = paramTypes(params, scope)
            val ret = FA.astTypeToInternalWithScope(retType, scope, [])
            val fnRet = if (async_) Ty.TApp("Task", [ret]) else ret
            val fnType = Ty.TArrow(ps, fnRet)
            val env2a = envInsert(env, name, Ty.generalize(Dict.emptyStringDict(), fnType))
            val local = bindParams(env2a, namesFromParams(params), ps)
            val bodyT = inferExpr(state, local, mergeTypeMaps(typeAliases, scope), body)
            unifyEq(state, bodyT, ret)
            env2a
          }
          SBreak => { addDiag(state, Diag.CODES.type_.breakOutsideLoop, "break used outside loop"); env }
          SContinue => { addDiag(state, Diag.CODES.type_.continueOutsideLoop, "continue used outside loop"); env }
          SAssign(target, rhs) => {
            val targetT = inferExpr(state, env, typeAliases, target)
            val rhsT = inferExpr(state, env, typeAliases, rhs)
            unifyEq(state, rhsT, targetT);
            env
          }
          _ => env
        }
      inferStmtList(state, env2, typeAliases, rest)
    }
  }

fun bindPatternList(state: TcState, env: TypeEnv, patterns: List<Ast.Pattern>, types: List<Ty.InternalType>): TypeEnv =
  match (patterns) {
    [] => env
    p :: rest =>
      match (types) {
        [] => env
        t :: tail => bindPatternList(state, bindPattern(state, env, p, t), rest, tail)
      }
  }

fun bindCtorArgs(state: TcState, env: TypeEnv, fields: List<Ast.ConField>, params: List<Ty.InternalType>): TypeEnv =
  match (fields) {
    [] => env
    f :: rest =>
      match (params) {
        [] => env
        t :: tail => {
          val env2 =
            match (f.pattern) {
              Some(p) => bindPattern(state, env, p, t)
              None => env
            }
          bindCtorArgs(state, env2, rest, tail)
        }
      }
  }

fun bindPattern(state: TcState, env: TypeEnv, pat: Ast.Pattern, expected: Ty.InternalType): TypeEnv =
  match (pat) {
    PWild => env
    PVar(name) => envInsert(env, name, expected)
    PLit(kind, _) => { unifyEq(state, expected, inferLiteral(kind)); env }
    PTuple(parts) => {
      val ts = Lst.map(parts, (_p: Ast.Pattern) => Ty.freshVar())
      unifyEq(state, expected, Ty.TTuple(ts));
      bindPatternList(state, env, parts, ts)
    }
    PList(parts, _rest) => {
      val elem = Ty.freshVar()
      unifyEq(state, expected, Ty.TApp("List", [elem]));
      bindPatternList(state, env, parts, Lst.map(parts, (_p: Ast.Pattern) => elem))
    }
    PCons(head, tail) => {
      val elem = Ty.freshVar()
      unifyEq(state, expected, Ty.TApp("List", [elem]));
      val env2 = bindPattern(state, env, head, elem)
      bindPattern(state, env2, tail, Ty.TApp("List", [elem]))
    }
    PCon(name, fields) => {
      val found = envGet(env, name)
      if (found == None) {
        addDiag(state, Diag.CODES.type_.unknownVariable, "Unknown constructor: ${name}");
        env
      } else {
        val ctorT = Ty.instantiate(Opt.getOrElse(found, Ty.freshVar()))
        match (ctorT) {
          TArrow(params, ret) => {
            unifyEq(state, expected, ret);
            bindCtorArgs(state, env, fields, params)
          }
          _ => {
            unifyEq(state, expected, ctorT);
            env
          }
        }
      }
    }
  }

fun patternIsCatchAll(p: Ast.Pattern): Bool =
  match (p) {
    PWild => True
    PVar(_) => True
    _ => False
  }

fun caseCtorNames(cases: List<Ast.Case_>): List<String> =
  match (cases) {
    [] => []
    c :: rest =>
      match (c.pattern) {
        PCon(name, _) => name :: caseCtorNames(rest)
        _ => caseCtorNames(rest)
      }
  }

fun allCovered(expected: List<String>, seen: List<String>): Bool =
  match (expected) {
    [] => True
    h :: rest => Lst.any(seen, (s: String) => s == h) & allCovered(rest, seen)
  }

fun checkExhaustive(state: TcState, scrutType: Ty.InternalType, cases: List<Ast.Case_>): Unit = {
  if (Lst.any(cases, (c: Ast.Case_) => patternIsCatchAll(c.pattern))) ()
  else
    match (apply(state, scrutType)) {
      TApp(name, _) => {
        val ctors = Dict.get(state.adtConstructors, name)
        match (ctors) {
          Some(expected) =>
            if (!allCovered(expected, caseCtorNames(cases)))
              addDiag(state, Diag.CODES.type_.nonExhaustiveMatch, "Non-exhaustive match for ${name}")
            else ()
          None => ()
        }
      }
      _ => ()
    }
}

fun inferMatchCases(
  state: TcState,
  env: TypeEnv,
  typeAliases: Dict<String, Ty.InternalType>,
  scrutType: Ty.InternalType,
  cases: List<Ast.Case_>,
  resultType: Ty.InternalType
): Unit =
  match (cases) {
    [] => ()
    c :: rest => {
      val env2 = bindPattern(state, env, c.pattern, scrutType)
      val bodyT = inferExpr(state, env2, typeAliases, c.body)
      unifyEq(state, bodyT, resultType);
      inferMatchCases(state, env, typeAliases, scrutType, rest, resultType)
    }
  }

fun inferBlock(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, block: Ast.Block): Ty.InternalType = {
  val env2 = inferStmtList(state, env, typeAliases, block.stmts)
  inferExpr(state, env2, typeAliases, block.result)
}

fun findRecordField(fields: List<Ty.TypeField>, name: String): Option<Ty.InternalType> =
  match (fields) {
    [] => None
    f :: rest => if (f.name == name) Some(f.type_) else findRecordField(rest, name)
  }

fun listNth<T>(lst: List<T>, i: Int): Option<T> =
  match (lst) {
    [] => None
    h :: rest => if (i == 0) Some(h) else listNth(rest, i - 1)
  }

fun inferUnary(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, op: String, operand: Ast.Expr): Ty.InternalType = {
  val t = inferExpr(state, env, typeAliases, operand)
  if (op == "-" | op == "+") {
    unifyEq(state, t, Ty.tInt);
    Ty.tInt
  } else if (op == "!") {
    unifyEq(state, t, Ty.tBool);
    Ty.tBool
  } else Ty.freshVar()
}

fun inferRecordFields(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, fields: List<Ast.RecField>): List<Ty.TypeField> =
  match (fields) {
    [] => []
    f :: rest => {
      val t = inferExpr(state, env, typeAliases, f.value)
      { name = f.name, mut_ = f.mut_, type_ = apply(state, t) } :: inferRecordFields(state, env, typeAliases, rest)
    }
  }

fun inferRecord(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, spreadOpt: Option<Ast.Expr>, fields: List<Ast.RecField>): Ty.InternalType = {
  val newFields = inferRecordFields(state, env, typeAliases, fields)
  match (spreadOpt) {
    None => Ty.TRecord(newFields, None)
    Some(spreadExpr) => {
      val spreadT = apply(state, inferExpr(state, env, typeAliases, spreadExpr))
      match (spreadT) {
        TRecord(spreadFields, rowOpt) => {
          val newNames = Lst.map(newFields, (f: Ty.TypeField) => f.name)
          val inherited = Lst.filter(spreadFields, (f: Ty.TypeField) => !Lst.any(newNames, (n: String) => n == f.name))
          Ty.TRecord(Lst.append(inherited, newFields), rowOpt)
        }
        _ => Ty.TRecord(newFields, Some(Ty.freshVar()))
      }
    }
  }
}

fun inferFieldNamespace(state: TcState, bindings: Dict<String, Ty.InternalType>, fieldName: String): Ty.InternalType = {
  val found = Dict.get(bindings, fieldName)
  match (found) {
    Some(t) => Ty.instantiate(t)
    None => {
      addDiag(state, Diag.CODES.type_.unknownVariable, "Namespace does not export '${fieldName}'");
      Ty.freshVar()
    }
  }
}

fun inferFieldTuple(state: TcState, elems: List<Ty.InternalType>, fieldName: String): Ty.InternalType =
  match (Str.toInt(fieldName)) {
    Some(i) =>
      match (listNth(elems, i)) {
        Some(t) => t
        None => {
          addDiag(state, Diag.CODES.type_.check, "Tuple index out of range: ${fieldName}");
          Ty.freshVar()
        }
      }
    None => {
      addDiag(state, Diag.CODES.type_.check, "Not a valid tuple index: ${fieldName}");
      Ty.freshVar()
    }
  }

fun inferFieldRecord(state: TcState, recFields: List<Ty.TypeField>, fieldName: String): Ty.InternalType =
  match (findRecordField(recFields, fieldName)) {
    Some(t) => t
    None => {
      addDiag(state, Diag.CODES.type_.unknownVariable, "Unknown field: ${fieldName}");
      Ty.freshVar()
    }
  }

fun inferField(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, obj: Ast.Expr, fieldName: String): Ty.InternalType =
  match (apply(state, inferExpr(state, env, typeAliases, obj))) {
    TNamespace(bindings) => inferFieldNamespace(state, bindings, fieldName)
    TTuple(elems) => inferFieldTuple(state, elems, fieldName)
    TRecord(recFields, _) => inferFieldRecord(state, recFields, fieldName)
    _ => {
      addDiag(state, Diag.CODES.type_.check, "Cannot access field '${fieldName}' on non-record type");
      Ty.freshVar()
    }
  }

fun inferAwait(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, e: Ast.Expr): Ty.InternalType = {
  val t = apply(state, inferExpr(state, env, typeAliases, e))
  match (t) {
    TApp("Task", args) =>
      match (args) {
        h :: _ => h
        [] => Ty.freshVar()
      }
    _ => {
      addDiag(state, Diag.CODES.type_.check, "await expects Task<T>");
      Ty.freshVar()
    }
  }
}

fun inferCons(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, head: Ast.Expr, tail: Ast.Expr): Ty.InternalType = {
  val headT = inferExpr(state, env, typeAliases, head)
  val tailT = inferExpr(state, env, typeAliases, tail)
  val elem = Ty.freshVar()
  unifyEq(state, tailT, Ty.TApp("List", [elem]));
  unifyEq(state, headT, elem);
  apply(state, Ty.TApp("List", [elem]))
}

fun inferTemplateParts(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, parts: List<Ast.TmplPart>): Unit =
  match (parts) {
    [] => ()
    p :: rest => {
      match (p) {
        TmplLit(_) => ()
        TmplExpr(e) => { inferExpr(state, env, typeAliases, e); () }
      };
      inferTemplateParts(state, env, typeAliases, rest)
    }
  }

fun inferTryCases(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, cases: List<Ast.Case_>, expected: Ty.InternalType): Unit =
  match (cases) {
    [] => ()
    c :: rest => {
      val env2 = bindPattern(state, env, c.pattern, Ty.freshVar())
      val bodyT = inferExpr(state, env2, typeAliases, c.body)
      unifyEq(state, bodyT, expected);
      inferTryCases(state, env, typeAliases, rest, expected)
    }
  }

fun inferTry(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, block: Ast.Block, varOpt: Option<String>, cases: List<Ast.Case_>): Ty.InternalType = {
  val bodyT = inferBlock(state, env, typeAliases, block)
  match (varOpt) {
    Some(varName) => inferTryCases(state, envInsert(env, varName, Ty.freshVar()), typeAliases, cases, bodyT)
    None => inferTryCases(state, env, typeAliases, cases, bodyT)
  };
  apply(state, bodyT)
}

fun inferPipeLR(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, left: Ast.Expr, right: Ast.Expr): Ty.InternalType =
  match (right) {
    ECall(fn, args) => inferExpr(state, env, typeAliases, ECall(fn, left :: args))
    _ => {
      val leftT = apply(state, inferExpr(state, env, typeAliases, left))
      val rightT = apply(state, inferExpr(state, env, typeAliases, right))
      val ret = Ty.freshVar()
      unifyEq(state, rightT, Ty.TArrow([leftT], ret));
      apply(state, ret)
    }
  }

fun inferPipeRL(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, left: Ast.Expr, right: Ast.Expr): Ty.InternalType =
  match (left) {
    ECall(fn, args) => inferExpr(state, env, typeAliases, ECall(fn, Lst.append(args, [right])))
    _ => {
      val leftT = apply(state, inferExpr(state, env, typeAliases, left))
      val rightT = apply(state, inferExpr(state, env, typeAliases, right))
      val ret = Ty.freshVar()
      unifyEq(state, leftT, Ty.TArrow([rightT], ret));
      apply(state, ret)
    }
  }

fun inferPipe(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, op: String, left: Ast.Expr, right: Ast.Expr): Ty.InternalType =
  if (op == "|>") inferPipeLR(state, env, typeAliases, left, right)
  else inferPipeRL(state, env, typeAliases, left, right)

fun inferExpr(state: TcState, env: TypeEnv, typeAliases: Dict<String, Ty.InternalType>, expr: Ast.Expr): Ty.InternalType = {
  val out =
    match (expr) {
      ELit(kind, _) => inferLiteral(kind)
      EIdent(name) => {
        val found = envGet(env, name)
        if (found == None) {
          addDiag(state, Diag.CODES.type_.unknownVariable, "Unknown variable: ${name}");
          Ty.freshVar()
        } else
          Ty.instantiate(Opt.getOrElse(found, Ty.freshVar()))
      }
      ECall(fn, args) => {
        val fnT = inferExpr(state, env, typeAliases, fn)
        val argTs = inferExprs(state, env, typeAliases, args)
        val ret = Ty.freshVar()
        unifyEq(state, fnT, Ty.TArrow(argTs, ret));
        apply(state, ret)
      }
      EBinary(op, left, right) => {
        val l = inferExpr(state, env, typeAliases, left)
        val r = inferExpr(state, env, typeAliases, right)
        if (op == "+" | op == "-" | op == "*" | op == "/" | op == "%" | op == "**") {
          if (unifyEq(state, l, Ty.tInt) & unifyEq(state, r, Ty.tInt)) Ty.tInt
          else if (unifyEq(state, l, Ty.tFloat) & unifyEq(state, r, Ty.tFloat)) Ty.tFloat
          else {
            addDiag(state, Diag.CODES.type_.check, "Arithmetic operator ${op} requires matching numeric operands");
            Ty.tInt
          }
        } else if (op == "&" | op == "|") {
          unifyEq(state, l, Ty.tBool);
          unifyEq(state, r, Ty.tBool);
          Ty.tBool
        } else {
          unifyEq(state, l, r);
          Ty.tBool
        }
      }
      EIf(cond, thenExpr, elseOpt) => {
        val condT = inferExpr(state, env, typeAliases, cond)
        unifyEq(state, condT, Ty.tBool);
        val thenT = inferExpr(state, env, typeAliases, thenExpr)
        match (elseOpt) {
          Some(elseExpr) => {
            val elseT = inferExpr(state, env, typeAliases, elseExpr)
            unifyEq(state, thenT, elseT);
            apply(state, thenT)
          }
          None => Ty.tUnit
        }
      }
      EWhile(cond, block) => {
        val condT = inferExpr(state, env, typeAliases, cond)
        unifyEq(state, condT, Ty.tBool);
        inferExpr(state, env, typeAliases, EBlock(block));
        Ty.tUnit
      }
      ELambda(async_, typeParams, params, body) => {
        val scope = buildTypeParamScope(typeAliases, typeParams)
        val ps = paramTypes(params, scope)
        val env2 = bindParams(env, namesFromParams(params), ps)
        val bodyT = inferExpr(state, env2, mergeTypeMaps(typeAliases, scope), body)
        if (async_) Ty.TArrow(ps, Ty.TApp("Task", [bodyT])) else Ty.TArrow(ps, bodyT)
      }
      EList(elems) => {
        val elem = Ty.freshVar()
        inferListElems(state, env, typeAliases, elems, elem);
        Ty.TApp("List", [apply(state, elem)])
      }
      ETuple(items) => Ty.TTuple(inferExprs(state, env, typeAliases, items))
      EMatch(scrut, cases) => {
        val scrutT = inferExpr(state, env, typeAliases, scrut)
        val result = Ty.freshVar()
        inferMatchCases(state, env, typeAliases, scrutT, cases, result);
        checkExhaustive(state, scrutT, cases);
        apply(state, result)
      }
      EBlock(block) => inferBlock(state, env, typeAliases, block)
      EUnary(op, x) => inferUnary(state, env, typeAliases, op, x)
      ERecord(spr, fields) => inferRecord(state, env, typeAliases, spr, fields)
      EField(obj, fn) => inferField(state, env, typeAliases, obj, fn)
      EAwait(e) => inferAwait(state, env, typeAliases, e)
      EThrow(e) => { inferExpr(state, env, typeAliases, e); Ty.freshVar() }
      ETry(block, varOpt, cases) => inferTry(state, env, typeAliases, block, varOpt, cases)
      ECons(head, tail) => inferCons(state, env, typeAliases, head, tail)
      EPipe(op, left, right) => inferPipe(state, env, typeAliases, op, left, right)
      ETemplate(parts) => { inferTemplateParts(state, env, typeAliases, parts); Ty.tString }
      EIs(e, _) => { inferExpr(state, env, typeAliases, e); Ty.tBool }
      ENever => Ty.freshVar()
      _ => {
        addDiag(state, Diag.CODES.type_.check, "Unsupported expression form in self-hosted checker MVP");
        Ty.freshVar()
      }
    }
  setInferredType(state, expr, out);
  apply(state, out)
}

fun prebindTypeDecls(reg: TypeRegistry, decls: List<Ast.TopDecl>): TypeRegistry =
  match (decls) {
    [] => reg
    h :: rest => {
      val reg2 =
        match (h) {
          TDType(td) => registerTypeDecl(reg, td)
          _ => reg
        }
      prebindTypeDecls(reg2, rest)
    }
  }

fun prebindFunDecls(env: Dict<String, Ty.InternalType>, typeAliases: Dict<String, Ty.InternalType>, decls: List<Ast.TopDecl>): Dict<String, Ty.InternalType> =
  match (decls) {
    [] => env
    h :: rest => {
      val env2 =
        match (h) {
          TDFun(fd) => registerFunSig(env, typeAliases, fd)
          _ => env
        }
      prebindFunDecls(env2, typeAliases, rest)
    }
  }

fun taskReturnType(async_: Bool, ret: Ty.InternalType): Ty.InternalType =
  if (async_) Ty.TApp("Task", [ret]) else ret

fun maybeExportBinding(exported: Bool, exports: TypeEnv, name: String, t: Ty.InternalType): TypeEnv =
  if (exported) envInsert(exports, name, t) else exports

fun checkFunDecl(
  state: TcState,
  env: TypeEnv,
  typeAliases: Dict<String, Ty.InternalType>,
  exports: TypeEnv,
  exportedTypeAliases: Dict<String, Ty.InternalType>,
  fd: Ast.FunDecl
): (TypeEnv, TypeEnv, Dict<String, Ty.InternalType>) = {
  val scope = buildTypeParamScope(typeAliases, fd.typeParams)
  val ps = paramTypes(fd.params, scope)
  val ret = FA.astTypeToInternalWithScope(fd.retType, mergeTypeMaps(typeAliases, scope), [])
  val local = bindParams(env, namesFromParams(fd.params), ps)
  val bodyT = inferExpr(state, local, mergeTypeMaps(typeAliases, scope), fd.body)
  val resultT = taskReturnType(fd.async_, ret)
  unifyEq(state, bodyT, ret);
  val finalType = Ty.generalize(Dict.emptyStringDict(), Ty.TArrow(ps, resultT));
  val env2 = envInsert(env, fd.name, finalType);
  val exports2 = maybeExportBinding(fd.exported, exports, fd.name, finalType);
  (env2, exports2, exportedTypeAliases)
}

fun checkExportValDecl(
  state: TcState,
  env: TypeEnv,
  typeAliases: Dict<String, Ty.InternalType>,
  exports: TypeEnv,
  exportedTypeAliases: Dict<String, Ty.InternalType>,
  name: String,
  ann: Option<Ast.AstType>,
  expr: Ast.Expr
): (TypeEnv, TypeEnv, Dict<String, Ty.InternalType>) = {
  val t = inferExpr(state, env, typeAliases, expr)
  match (ann) {
    Some(astType) => { unifyEq(state, t, FA.astTypeToInternalWithScope(astType, typeAliases, [])); () }
    None => ()
  };
  val gt = Ty.generalize(env.items, apply(state, t));
  val env2 = envInsert(env, name, gt);
  (env2, envInsert(exports, name, gt), exportedTypeAliases)
}

fun checkExportVarDecl(
  state: TcState,
  env: TypeEnv,
  typeAliases: Dict<String, Ty.InternalType>,
  exports: TypeEnv,
  exportedTypeAliases: Dict<String, Ty.InternalType>,
  name: String,
  ann: Option<Ast.AstType>,
  expr: Ast.Expr
): (TypeEnv, TypeEnv, Dict<String, Ty.InternalType>) = {
  val t = inferExpr(state, env, typeAliases, expr)
  match (ann) {
    Some(astType) => { unifyEq(state, t, FA.astTypeToInternalWithScope(astType, typeAliases, [])); () }
    None => ()
  };
  val mt = apply(state, t);
  val env2 = envInsert(env, name, mt);
  (env2, envInsert(exports, name, mt), exportedTypeAliases)
}

fun checkScriptValDecl(
  state: TcState,
  env: TypeEnv,
  typeAliases: Dict<String, Ty.InternalType>,
  exports: TypeEnv,
  exportedTypeAliases: Dict<String, Ty.InternalType>,
  name: String,
  expr: Ast.Expr
): (TypeEnv, TypeEnv, Dict<String, Ty.InternalType>) = {
  val t = inferExpr(state, env, typeAliases, expr);
  (envInsert(env, name, Ty.generalize(env.items, apply(state, t))), exports, exportedTypeAliases)
}

fun checkScriptVarDecl(
  state: TcState,
  env: TypeEnv,
  typeAliases: Dict<String, Ty.InternalType>,
  exports: TypeEnv,
  exportedTypeAliases: Dict<String, Ty.InternalType>,
  name: String,
  expr: Ast.Expr
): (TypeEnv, TypeEnv, Dict<String, Ty.InternalType>) = {
  val t = inferExpr(state, env, typeAliases, expr);
  (envInsert(env, name, apply(state, t)), exports, exportedTypeAliases)
}

fun checkTypeDeclExports(
  typeAliases: Dict<String, Ty.InternalType>,
  env: TypeEnv,
  exports: TypeEnv,
  exportedTypeAliases: Dict<String, Ty.InternalType>,
  td: Ast.TypeDecl
): (TypeEnv, TypeEnv, Dict<String, Ty.InternalType>) = {
  val aliasOut =
    match (td.body) {
      TBAlias(bodyType) => Dict.insert(exportedTypeAliases, td.name, FA.astTypeToInternalWithScope(bodyType, typeAliases, []))
      _ => exportedTypeAliases
    };
  (env, exports, aliasOut)
}

fun checkDecls(
  state: TcState,
  env: TypeEnv,
  typeAliases: Dict<String, Ty.InternalType>,
  exports: TypeEnv,
  exportedTypeAliases: Dict<String, Ty.InternalType>,
  decls: List<Ast.TopDecl>
): (TypeEnv, TypeEnv, Dict<String, Ty.InternalType>) =
  match (decls) {
    [] => (env, exports, exportedTypeAliases)
    h :: rest => {
      val out =
        match (h) {
          TDFun(fd) => checkFunDecl(state, env, typeAliases, exports, exportedTypeAliases, fd)
          TDVal(name, ann, expr) => checkExportValDecl(state, env, typeAliases, exports, exportedTypeAliases, name, ann, expr)
          TDVar(name, ann, expr) => checkExportVarDecl(state, env, typeAliases, exports, exportedTypeAliases, name, ann, expr)
          TDSVal(name, expr) => checkScriptValDecl(state, env, typeAliases, exports, exportedTypeAliases, name, expr)
          TDSVar(name, expr) => checkScriptVarDecl(state, env, typeAliases, exports, exportedTypeAliases, name, expr)
          TDSExpr(expr) => { inferExpr(state, env, typeAliases, expr); (env, exports, exportedTypeAliases) }
          TDType(td) => checkTypeDeclExports(typeAliases, env, exports, exportedTypeAliases, td)
          _ => {
            addDiag(state, Diag.CODES.type_.check, "Unsupported top-level declaration in self-hosted checker MVP");
            (env, exports, exportedTypeAliases)
          }
        }
      checkDecls(state, out.0, typeAliases, out.1, out.2, rest)
    }
  }

fun resolvedTypeAliasBindings(opts: TypecheckOptions): Dict<String, Ty.InternalType> =
  match (opts.typeAliasBindings) {
    Some(d) => d
    None => Dict.emptyStringDict()
  }

fun resolvedImportEnv(opts: TypecheckOptions): TypeEnv =
  match (opts.importBindings) {
    Some(e) => e
    None => emptyTypeEnv()
  }

fun emptyTypeRegistry(opts: TypecheckOptions): TypeRegistry = {
  typeAliases = resolvedTypeAliasBindings(opts),
  ctorEnv = Dict.emptyStringDict(),
  adtConstructors = Dict.emptyStringDict(),
  ctorOwners = Dict.emptyStringDict(),
  exportedConstructors = Dict.emptyStringDict(),
  exportedTypeVisibility = Dict.emptyStringDict()
}

fun makeTcState(reporter: Rep.Reporter, reg: TypeRegistry, sourceFile: String): TcState = {
  reporter = reporter,
  mut subst = Dict.emptyIntDict(),
  adtConstructors = reg.adtConstructors,
  ctorOwners = reg.ctorOwners,
  sourceFile = sourceFile,
  mut inferredItems = []
}

fun builtinTypeEnv(): TypeEnv = {
  val optionA = Ty.freshVar()
  val resultOk = Ty.freshVar()
  val resultErr = Ty.freshVar()
  {
    items = Dict.fromStringList([
      ("None", Ty.generalize(Dict.emptyStringDict(), Ty.TApp("Option", [optionA]))),
      ("Some", Ty.generalize(Dict.emptyStringDict(), Ty.TArrow([optionA], Ty.TApp("Option", [optionA])))),
      ("Ok", Ty.generalize(Dict.emptyStringDict(), Ty.TArrow([resultOk], Ty.TApp("Result", [resultOk, resultErr])))),
      ("Err", Ty.generalize(Dict.emptyStringDict(), Ty.TArrow([resultErr], Ty.TApp("Result", [resultOk, resultErr]))))
    ])
  }
}

fun typecheckSucceeded(reporter: Rep.Reporter): Bool =
  if (Rep.hasErrors(reporter)) False else True

fun finishTypecheckResult(reporter: Rep.Reporter, reg: TypeRegistry, checked: (TypeEnv, TypeEnv, Dict<String, Ty.InternalType>), capturedItems: List<InferredEntry>): TypecheckResult = {
  val ok = typecheckSucceeded(reporter)
  val diagnostics = Rep.diagnostics(reporter)
  {
    ok = ok,
    exports = checked.1,
    exportedTypeAliases = checked.2,
    exportedConstructors = reg.exportedConstructors,
    exportedTypeVisibility = reg.exportedTypeVisibility,
    diagnostics = diagnostics,
    getInferredType = (node: Ast.Expr) => getInferredLoop(capturedItems, node)
  }
}

/// Typecheck a parsed program and return inferred exports plus diagnostics.
///
/// The checker resets type-variable allocation for deterministic ids per run,
/// prebinds type and function declarations, then checks top-level declarations
/// to produce export maps and diagnostics.
export fun typecheck(prog: Ast.Program, opts: TypecheckOptions): TypecheckResult = {
  Ty.resetVarId();
  val reporter = Rep.newReporter()
  val reg0 = emptyTypeRegistry(opts)
  val reg = prebindTypeDecls(reg0, prog.body)
  val state = makeTcState(reporter, reg, opts.sourceFile)
  val builtinEnv = builtinTypeEnv()
  val importEnv = resolvedImportEnv(opts)
  val env0 = envUnion(rawToEnv(reg.ctorEnv), envUnion(importEnv, builtinEnv))
  val env1 = rawToEnv(prebindFunDecls(env0.items, reg.typeAliases, prog.body))
  val checked = checkDecls(state, env1, reg.typeAliases, emptyTypeEnv(), Dict.emptyStringDict(), prog.body)
  finishTypecheckResult(reporter, reg, checked, state.inferredItems)
}