//! KTI (Kestrel Type Interface) serialization/deserialization helpers.
//!
//! Encodes and decodes exported type information and codegen metadata to a JSON-
//! based interchange format used by compiler caching and dependency reuse.

import * as Dict from "kestrel:data/dict"
import * as Json from "kestrel:data/json"
import { Null, Bool, Int, Float, StrVal, Array, Object } from "kestrel:data/json"
import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"
import * as Res from "kestrel:data/result"
import * as Str from "kestrel:data/string"
import * as Ast from "kestrel:dev/parser/ast"
import { TDFun, TDVar, TDVal, TDSVal, TDSVar, TDType, TBAdt, TDExternFun, TDException, TDExport, EIDecl, IDNamed, IDNamespace } from "kestrel:dev/parser/ast"
import * as Fs from "kestrel:io/fs"
import { NotFound, PermissionDenied, IoError } from "kestrel:io/fs"
import * as Ty from "kestrel:dev/typecheck/types"
import { TVar, TPrim, TArrow, TRecord, TApp, TTuple, TUnion, TInter, TScheme, TNamespace } from "kestrel:dev/typecheck/types"
import * as Resolve from "kestrel:tools/compiler/resolve"
import * as Crypto from "kestrel:io/crypto"

export type KtiFunctionEntry = { kind: String, function_index: Int, arity: Int, type_: Json.Value }
export type KtiExportEntry = KtiFunction(KtiFunctionEntry)
export type KtiTypeEntry = { visibility: String, kind: String, type_: Option<Json.Value>, constructors: Option<List<(String, Int)>>, typeParams: List<String> }
export type KtiAdtConstructorGroup = { typeName: String, constructors: List<(String, Int)> }
export type KtiExceptionEntry = { name: String, arity: Int }

export type KtiCodegenMeta = {
  funArities: Dict<String, Int>,
  asyncFunNames: List<String>,
  varNames: List<String>,
  valOrVarNames: List<String>,
  adtConstructors: List<KtiAdtConstructorGroup>,
  exceptionDecls: List<KtiExceptionEntry>
}

export type KtiV4 = {
  version: Int,
  functions: Dict<String, KtiExportEntry>,
  types: Dict<String, KtiTypeEntry>,
  sourceHash: String,
  depHashes: Dict<String, String>,
  codegenMeta: KtiCodegenMeta
}

/// Compute the source hash for a Kestrel source string.
/// This must match the hash stored in KTI files by `buildKtiV4`.
export fun sourceHash(s: String): String = Crypto.sha256(s)

fun serializeTypeField(f: Ty.TypeField): Json.Value =
  Object([
    ("n", StrVal(f.name)),
    ("mut", Bool(f.mut_)),
    ("t", serializeType(f.type_))
  ])

export fun serializeType(t: Ty.InternalType): Json.Value =
  match (t) {
    TVar(id) => Object([("k", StrVal("var")), ("id", Int(id))])
    TPrim(name) => Object([("k", StrVal("prim")), ("n", StrVal(name))])
    TArrow(params, ret) =>
      Object([
        ("k", StrVal("arrow")),
        ("ps", Array(Lst.map(params, serializeType))),
        ("r", serializeType(ret))
      ])
    TRecord(fields, rowOpt) => {
      val rowJson = match (rowOpt) {
        None => Null
        Some(rv) => serializeType(rv)
      }
      Object([
        ("k", StrVal("record")),
        ("fs", Array(Lst.map(fields, serializeTypeField))),
        ("row", rowJson)
      ])
    }
    TApp(name, args) =>
      Object([
        ("k", StrVal("app")),
        ("n", StrVal(name)),
        ("as", Array(Lst.map(args, serializeType)))
      ])
    TTuple(elems) =>
      Object([("k", StrVal("tuple")), ("es", Array(Lst.map(elems, serializeType)))])
    TUnion(l, r) =>
      Object([("k", StrVal("union")), ("l", serializeType(l)), ("r", serializeType(r))])
    TInter(l, r) =>
      Object([("k", StrVal("inter")), ("l", serializeType(l)), ("r", serializeType(r))])
    TScheme(vars, body) =>
      Object([
        ("k", StrVal("scheme")),
        ("vs", Array(Lst.map(vars, (id: Int) => Int(id)))),
        ("b", serializeType(body))
      ])
    TNamespace(_bindings) =>
      Object([
        ("k", StrVal("app")),
        ("n", StrVal("__namespace__")),
        ("as", Array([]))
      ])
  }

fun parseNamedType(s: String): Ty.InternalType =
  if (s == "Int") Ty.tInt
  else if (s == "Bool") Ty.tBool
  else if (s == "String") Ty.tString
  else if (s == "Unit") Ty.tUnit
  else Ty.tUnit

fun parseTypeList(parts: List<String>, acc: List<Ty.InternalType>): List<Ty.InternalType> =
  match (parts) {
    [] => Lst.reverse(acc)
    part :: rest => parseTypeList(rest, parseNamedType(Str.trim(part)) :: acc)
  }

export fun deserializeType(v: Json.Value): Ty.InternalType =
  match (v) {
    StrVal(s) => {
      if (Str.contains("->", s)) {
        val parts = Str.split(s, "->")
        match (parts) {
          lhs :: rest =>
            match (rest) {
              rhs :: _ => {
                val paramText = Str.trim(lhs)
                val returnTy = parseNamedType(Str.trim(rhs))
                if (paramText == "()") Ty.TArrow([], returnTy)
                else if (Str.startsWith("(", paramText) & Str.endsWith(")", paramText)) {
                  val inner = Str.dropRight(Str.dropLeft(paramText, 1), 1)
                  Ty.TArrow(parseTypeList(Str.split(inner, ","), []), returnTy)
                } else Ty.TArrow([parseNamedType(paramText)], returnTy)
              }
              _ => Ty.tUnit
            }
          _ => Ty.tUnit
        }
      } else parseNamedType(s)
    }
    Object(ps) => deserializeTypeFromObj(ps)
    _ => Ty.tUnit
  }

fun toFsErrorString(e: Fs.FsError): String =
  match (e) {
    NotFound => "not_found"
    PermissionDenied => "permission_denied"
    IoError(msg) => msg
  }

fun exportEntryToJson(entry: KtiExportEntry): Json.Value =
  match (entry) {
    KtiFunction(fe) => Object([
      ("kind", StrVal(fe.kind)),
      ("function_index", Int(fe.function_index)),
      ("arity", Int(fe.arity)),
      ("type", fe.type_)
    ])
  }

fun typeEntryToJson(entry: KtiTypeEntry): Json.Value = {
  val base = [
    ("visibility", StrVal(entry.visibility)),
    ("kind", StrVal(entry.kind)),
    ("typeParams", Array(Lst.map(entry.typeParams, (s: String) => StrVal(s))))
  ]
  val withType = match (entry.type_) {
    Some(tv) => Lst.append(base, [("type", tv)])
    None => base
  }
  val withCtors = match (entry.constructors) {
    None => withType
    Some(ctors) => {
      val ctorJson = Array(Lst.map(ctors, (c: (String, Int)) =>
        Object([("name", StrVal(c.0)), ("params", Array([]))])
      ));
      Lst.append(withType, [("constructors", ctorJson)])
    }
  }
  Object(withCtors)
}

fun intMapToJson(d: Dict<String, Int>): Json.Value =
  Object(Lst.map(Dict.toList(d), (p: (String, Int)) => (p.0, Int(p.1))))

fun strMapToJson(d: Dict<String, String>): Json.Value =
  Object(Lst.map(Dict.toList(d), (p: (String, String)) => (p.0, StrVal(p.1))))

fun adtToJson(g: KtiAdtConstructorGroup): Json.Value =
  Object([
    ("typeName", StrVal(g.typeName)),
    ("constructors", Array(Lst.map(g.constructors, (c: (String, Int)) =>
      Object([("name", StrVal(c.0)), ("params", Int(c.1))])
    )))
  ])

fun exceptionToJson(e: KtiExceptionEntry): Json.Value =
  Object([("name", StrVal(e.name)), ("arity", Int(e.arity))])

fun codegenMetaToJson(meta: KtiCodegenMeta): Json.Value =
  Object([
    ("funArities", intMapToJson(meta.funArities)),
    ("asyncFunNames", Array(Lst.map(meta.asyncFunNames, (s: String) => StrVal(s)))),
    ("varNames", Array(Lst.map(meta.varNames, (s: String) => StrVal(s)))),
    ("valOrVarNames", Array(Lst.map(meta.valOrVarNames, (s: String) => StrVal(s)))),
    ("adtConstructors", Array(Lst.map(meta.adtConstructors, adtToJson))),
    ("exceptionDecls", Array(Lst.map(meta.exceptionDecls, exceptionToJson)))
  ])

fun ktiToJson(kti: KtiV4): Json.Value =
  Object([
    ("version", Int(kti.version)),
    ("functions", Object(Lst.map(Dict.toList(kti.functions), (p: (String, KtiExportEntry)) => (p.0, exportEntryToJson(p.1))))),
    ("types", Object(Lst.map(Dict.toList(kti.types), (p: (String, KtiTypeEntry)) => (p.0, typeEntryToJson(p.1))))),
    ("sourceHash", StrVal(kti.sourceHash)),
    ("depHashes", strMapToJson(kti.depHashes)),
    ("codegenMeta", codegenMetaToJson(kti.codegenMeta))
  ])

fun objGet(ps: List<(String, Json.Value)>, key: String): Option<Json.Value> =
  match (ps) {
    [] => None
    p :: rest => if (p.0 == key) Some(p.1) else objGet(rest, key)
  }

fun asObj(v: Json.Value): Option<List<(String, Json.Value)>> =
  match (v) {
    Object(ps) => Some(ps)
    _ => None
  }

fun asInt(v: Json.Value): Option<Int> =
  match (v) {
    Int(n) => Some(n)
    _ => None
  }

fun asStr(v: Json.Value): Option<String> =
  match (v) {
    StrVal(s) => Some(s)
    _ => None
  }

fun asBool(v: Json.Value): Option<Bool> =
  match (v) {
    Bool(b) => Some(b)
    _ => None
  }

fun deserializeTypeList(v: Json.Value): List<Ty.InternalType> =
  match (v) {
    Array(xs) => Lst.map(xs, deserializeType)
    _ => []
  }

fun deserializeTypeField(v: Json.Value): Ty.TypeField =
  match (asObj(v)) {
    None => { name = "?", mut_ = False, type_ = Ty.tUnit }
    Some(fps) => {
      val n = Opt.getOrElse(Opt.andThen(objGet(fps, "n"), asStr), "?")
      val m = Opt.getOrElse(Opt.andThen(objGet(fps, "mut"), asBool), False)
      val t = match (objGet(fps, "t")) {
        None => Ty.tUnit
        Some(tv) => deserializeType(tv)
      }
      { name = n, mut_ = m, type_ = t }
    }
  }

fun deserializeTypeFromObj(ps: List<(String, Json.Value)>): Ty.InternalType =
  match (Opt.andThen(objGet(ps, "k"), asStr)) {
    None => Ty.tUnit
    Some(k) =>
      if (k == "prim") {
        Ty.TPrim(Opt.getOrElse(Opt.andThen(objGet(ps, "n"), asStr), "Unit"))
      } else if (k == "var") {
        Ty.TVar(Opt.getOrElse(Opt.andThen(objGet(ps, "id"), asInt), 0))
      } else if (k == "arrow") {
        val paramsV = Opt.getOrElse(objGet(ps, "ps"), Array([]))
        val retV = Opt.getOrElse(objGet(ps, "r"), StrVal("Unit"))
        Ty.TArrow(deserializeTypeList(paramsV), deserializeType(retV))
      } else if (k == "record") {
        val fsV = Opt.getOrElse(objGet(ps, "fs"), Array([]))
        val rowV = objGet(ps, "row")
        val fields = match (fsV) {
          Array(xs) => Lst.map(xs, deserializeTypeField)
          _ => []
        }
        val rowOpt = match (rowV) {
          None => None
          Some(rv) => match (rv) {
            Null => None
            _ => Some(deserializeType(rv))
          }
        }
        Ty.TRecord(fields, rowOpt)
      } else if (k == "app") {
        val n = Opt.getOrElse(Opt.andThen(objGet(ps, "n"), asStr), "?")
        val argsV = Opt.getOrElse(objGet(ps, "as"), Array([]))
        Ty.TApp(n, deserializeTypeList(argsV))
      } else if (k == "tuple") {
        val esV = Opt.getOrElse(objGet(ps, "es"), Array([]))
        Ty.TTuple(deserializeTypeList(esV))
      } else if (k == "union") {
        val lv = Opt.getOrElse(objGet(ps, "l"), StrVal("Unit"))
        val rv = Opt.getOrElse(objGet(ps, "r"), StrVal("Unit"))
        Ty.TUnion(deserializeType(lv), deserializeType(rv))
      } else if (k == "inter") {
        val lv = Opt.getOrElse(objGet(ps, "l"), StrVal("Unit"))
        val rv = Opt.getOrElse(objGet(ps, "r"), StrVal("Unit"))
        Ty.TInter(deserializeType(lv), deserializeType(rv))
      } else if (k == "scheme") {
        val vsV = Opt.getOrElse(objGet(ps, "vs"), Array([]))
        val bv = Opt.getOrElse(objGet(ps, "b"), StrVal("Unit"))
        val vars = match (vsV) {
          Array(xs) => Lst.filterMap(xs, asInt)
          _ => []
        }
        Ty.TScheme(vars, deserializeType(bv))
      } else Ty.tUnit
  }

fun parseFunctions(v: Json.Value): Dict<String, KtiExportEntry> =
  match (asObj(v)) {
    None => Dict.emptyStringDict()
    Some(ps) => Lst.foldl(ps, Dict.emptyStringDict(), (acc: Dict<String, KtiExportEntry>, p: (String, Json.Value)) =>
      match (asObj(p.1)) {
        None => acc
        Some(eps) => {
          val arity = Opt.getOrElse(Opt.andThen(objGet(eps, "arity"), asInt), 0)
          val idx = Opt.getOrElse(Opt.andThen(objGet(eps, "function_index"), asInt), 0)
          val t = Opt.getOrElse(objGet(eps, "type"), StrVal("Unit"))
          Dict.insert(acc, p.0, KtiFunction({ kind = "function", function_index = idx, arity = arity, type_ = t }))
        }
      }
    )
  }

fun parseConstructorsField(v: Json.Value): Option<List<(String, Int)>> =
  match (v) {
    Array(items) =>
      Some(Lst.foldl(items, [], (acc: List<(String, Int)>, item: Json.Value) =>
        match (asObj(item)) {
          None => acc
          Some(ps) => {
            match (Opt.andThen(objGet(ps, "name"), asStr)) {
              None => acc
              Some(name) => {
                val arity = match (objGet(ps, "params")) {
                  None => 0
                  Some(paramsVal) => match (paramsVal) {
                    Array(plist) => Lst.length(plist)
                    _ => 0
                  }
                };
                Lst.append(acc, [(name, arity)])
              }
            }
          }
        }
      ))
    _ => None
  }

fun parseTypeEntry(v: Json.Value): Option<KtiTypeEntry> =
  match (asObj(v)) {
    None => None
    Some(eps) => {
      val visibility = Opt.getOrElse(Opt.andThen(objGet(eps, "visibility"), asStr), "export")
      val kind = Opt.getOrElse(Opt.andThen(objGet(eps, "kind"), asStr), "alias")
      val typeOpt = match (objGet(eps, "type")) {
        None => None
        Some(tv) => Some(tv)
      }
      val typeParams = parseStringList(Opt.getOrElse(objGet(eps, "typeParams"), Array([])))
      val constructors = match (objGet(eps, "constructors")) {
        None => None
        Some(cv) => parseConstructorsField(cv)
      }
      Some({ visibility = visibility, kind = kind, type_ = typeOpt, constructors = constructors, typeParams = typeParams })
    }
  }

fun parseTypes(v: Json.Value): Dict<String, KtiTypeEntry> =
  match (asObj(v)) {
    None => Dict.emptyStringDict()
    Some(ps) => Lst.foldl(ps, Dict.emptyStringDict(), (acc: Dict<String, KtiTypeEntry>, p: (String, Json.Value)) =>
      match (parseTypeEntry(p.1)) {
        None => acc
        Some(te) => Dict.insert(acc, p.0, te)
      }
    )
  }

fun parseStringMap(v: Json.Value): Dict<String, String> =
  match (asObj(v)) {
    None => Dict.emptyStringDict()
    Some(ps) => Lst.foldl(ps, Dict.emptyStringDict(), (acc: Dict<String, String>, p: (String, Json.Value)) =>
      match (asStr(p.1)) {
        Some(s) => Dict.insert(acc, p.0, s)
        None => acc
      }
    )
  }

fun parseIntMap(v: Json.Value): Dict<String, Int> =
  match (asObj(v)) {
    None => Dict.emptyStringDict()
    Some(ps) => Lst.foldl(ps, Dict.emptyStringDict(), (acc: Dict<String, Int>, p: (String, Json.Value)) =>
      match (asInt(p.1)) {
        Some(n) => Dict.insert(acc, p.0, n)
        None => acc
      }
    )
  }

fun parseStringList(v: Json.Value): List<String> =
  match (v) {
    Array(xs) => Lst.filterMap(xs, asStr)
    _ => []
  }

fun parseCodegenMeta(v: Json.Value): KtiCodegenMeta =
  match (asObj(v)) {
    None => { funArities = Dict.emptyStringDict(), asyncFunNames = [], varNames = [], valOrVarNames = [], adtConstructors = [], exceptionDecls = [] }
    Some(ps) => {
      funArities = parseIntMap(Opt.getOrElse(objGet(ps, "funArities"), Object([]))),
      asyncFunNames = parseStringList(Opt.getOrElse(objGet(ps, "asyncFunNames"), Array([]))),
      varNames = parseStringList(Opt.getOrElse(objGet(ps, "varNames"), Array([]))),
      valOrVarNames = parseStringList(Opt.getOrElse(objGet(ps, "valOrVarNames"), Array([]))),
      adtConstructors = [],
      exceptionDecls = []
    }
  }

fun parseKti(v: Json.Value): Result<KtiV4, String> =
  match (asObj(v)) {
    None => Err("invalid kti root")
    Some(ps) => {
      val version = Opt.getOrElse(Opt.andThen(objGet(ps, "version"), asInt), 0)
      if (version != 4) Err("unsupported kti version") else
      Ok({
        version = 4,
        functions = parseFunctions(Opt.getOrElse(objGet(ps, "functions"), Object([]))),
        types = parseTypes(Opt.getOrElse(objGet(ps, "types"), Object([]))),
        sourceHash = Opt.getOrElse(Opt.andThen(objGet(ps, "sourceHash"), asStr), ""),
        depHashes = parseStringMap(Opt.getOrElse(objGet(ps, "depHashes"), Object([]))),
        codegenMeta = parseCodegenMeta(Opt.getOrElse(objGet(ps, "codegenMeta"), Object([])))
      })
    }
  }

fun extractDeclCodegen(decl: Ast.TopDecl, meta: KtiCodegenMeta): KtiCodegenMeta =
  match (decl) {
    TDFun(fd) => {
      val newAsync = if (fd.async_) fd.name :: meta.asyncFunNames else meta.asyncFunNames
      {
        funArities = Dict.insert(meta.funArities, fd.name, Lst.length(fd.params)),
        asyncFunNames = newAsync,
        varNames = meta.varNames,
        valOrVarNames = meta.valOrVarNames,
        adtConstructors = meta.adtConstructors,
        exceptionDecls = meta.exceptionDecls
      }
    }
    TDExternFun(efd) => {
      {
        funArities = Dict.insert(meta.funArities, efd.name, Lst.length(efd.params)),
        asyncFunNames = meta.asyncFunNames,
        varNames = meta.varNames,
        valOrVarNames = meta.valOrVarNames,
        adtConstructors = meta.adtConstructors,
        exceptionDecls = meta.exceptionDecls
      }
    }
    TDVar(name, _, _) => {
      {
        funArities = meta.funArities,
        asyncFunNames = meta.asyncFunNames,
        varNames = name :: meta.varNames,
        valOrVarNames = name :: meta.valOrVarNames,
        adtConstructors = meta.adtConstructors,
        exceptionDecls = meta.exceptionDecls
      }
    }
    TDSVar(name, _, _) => {
      {
        funArities = meta.funArities,
        asyncFunNames = meta.asyncFunNames,
        varNames = name :: meta.varNames,
        valOrVarNames = name :: meta.valOrVarNames,
        adtConstructors = meta.adtConstructors,
        exceptionDecls = meta.exceptionDecls
      }
    }
    TDVal(name, _, _) => {
      {
        funArities = meta.funArities,
        asyncFunNames = meta.asyncFunNames,
        varNames = meta.varNames,
        valOrVarNames = name :: meta.valOrVarNames,
        adtConstructors = meta.adtConstructors,
        exceptionDecls = meta.exceptionDecls
      }
    }
    TDSVal(name, _, _) => {
      {
        funArities = meta.funArities,
        asyncFunNames = meta.asyncFunNames,
        varNames = meta.varNames,
        valOrVarNames = name :: meta.valOrVarNames,
        adtConstructors = meta.adtConstructors,
        exceptionDecls = meta.exceptionDecls
      }
    }
    TDType(td) => {
      match (td.body) {
        TBAdt(ctors) => {
          val group = {
            typeName = td.name,
            constructors = Lst.map(ctors, (c: Ast.CtorDef) => (c.name, Lst.length(c.params)))
          }
          {
            funArities = meta.funArities,
            asyncFunNames = meta.asyncFunNames,
            varNames = meta.varNames,
            valOrVarNames = meta.valOrVarNames,
            adtConstructors = group :: meta.adtConstructors,
            exceptionDecls = meta.exceptionDecls
          }
        }
        _ => meta
      }
    }
    TDException(exn) => {
      val arity = match (exn.fields) {
        Some(fs) => Lst.length(fs)
        None => 0
      }
      {
        funArities = meta.funArities,
        asyncFunNames = meta.asyncFunNames,
        varNames = meta.varNames,
        valOrVarNames = meta.valOrVarNames,
        adtConstructors = meta.adtConstructors,
        exceptionDecls = { name = exn.name, arity = arity } :: meta.exceptionDecls
      }
    }
    TDExport(inner) => {
      match (inner) {
        EIDecl(d) => extractDeclCodegen(d, meta)
        _ => meta
      }
    }
    _ => meta
  }

export fun extractCodegenMeta(prog: Ast.Program, _exports: Dict<String, Ty.InternalType>): KtiCodegenMeta =
  Lst.foldl(prog.body, {
    funArities = Dict.emptyStringDict(),
    asyncFunNames = [],
    varNames = [],
    valOrVarNames = [],
    adtConstructors = [],
    exceptionDecls = []
  }, (meta: KtiCodegenMeta, d: Ast.TopDecl) => extractDeclCodegen(d, meta))

fun buildEntries(names: List<String>, exports: Dict<String, Ty.InternalType>, idx: Int, acc: Dict<String, KtiExportEntry>): Dict<String, KtiExportEntry> =
  match (names) {
    [] => acc
    n :: rest => buildEntries(rest, exports, idx + 1, Dict.insert(acc, n, KtiFunction({ kind = "function", function_index = idx, arity = 0, type_ = serializeType(Opt.getOrElse(Dict.get(exports, n), Ty.tUnit)) })))
  }

fun buildTypeEntries(names: List<String>, exportedTypeAliases: Dict<String, Ty.InternalType>, exportedTypeVisibility: Dict<String, String>, adtCtorGroups: Dict<String, List<String>>, acc: Dict<String, KtiTypeEntry>): Dict<String, KtiTypeEntry> =
  match (names) {
    [] => acc
    n :: rest => {
      val vis = Opt.getOrElse(Dict.get(exportedTypeVisibility, n), "export")
      val ty = Opt.getOrElse(Dict.get(exportedTypeAliases, n), Ty.TApp(n, []))
      val typeOpt = if (vis == "opaque") None else Some(serializeType(ty))
      val ctors = match (Dict.get(adtCtorGroups, n)) {
        None => None
        Some(ctorNames) => Some(Lst.map(ctorNames, (c: String) => (c, 0)))
      }
      val entryKind = if (ctors == None) "alias" else "adt"
      val entry = { visibility = vis, kind = entryKind, type_ = typeOpt, constructors = ctors, typeParams = [] }
      buildTypeEntries(rest, exportedTypeAliases, exportedTypeVisibility, adtCtorGroups, Dict.insert(acc, n, entry))
    }
  }

fun computeAdtCtorGroups(decls: List<Ast.TopDecl>, exportedTypeVisibility: Dict<String, String>, acc: Dict<String, List<String>>): Dict<String, List<String>> =
  match (decls) {
    [] => acc
    d :: rest =>
      match (d) {
        TDType(td) =>
          match (td.body) {
            TBAdt(ctors) => {
              val vis = Opt.getOrElse(Dict.get(exportedTypeVisibility, td.name), "export");
              if (vis == "opaque") computeAdtCtorGroups(rest, exportedTypeVisibility, acc)
              else computeAdtCtorGroups(rest, exportedTypeVisibility, Dict.insert(acc, td.name, Lst.map(ctors, (c: Ast.CtorDef) => c.name)))
            }
            _ => computeAdtCtorGroups(rest, exportedTypeVisibility, acc)
          }
        _ => computeAdtCtorGroups(rest, exportedTypeVisibility, acc)
      }
  }

export fun buildKtiV4(prog: Ast.Program, exports: Dict<String, Ty.InternalType>, exportedTypeAliases: Dict<String, Ty.InternalType>, exportedConstructors: Dict<String, Ty.InternalType>, exportedTypeVisibility: Dict<String, String>, source: String, depHashes: Dict<String, String>): KtiV4 = {
  val allFunctions = Dict.union(exports, exportedConstructors)
  val adtCtorGroups = computeAdtCtorGroups(prog.body, exportedTypeVisibility, Dict.emptyStringDict())
  {
    version = 4,
    functions = buildEntries(Dict.keys(allFunctions), allFunctions, 0, Dict.emptyStringDict()),
    types = buildTypeEntries(Dict.keys(exportedTypeAliases), exportedTypeAliases, exportedTypeVisibility, adtCtorGroups, Dict.emptyStringDict()),
    sourceHash = sourceHash(source),
    depHashes = depHashes,
    codegenMeta = extractCodegenMeta(prog, allFunctions)
  }
}

export async fun writeKtiFile(path: String, kti: KtiV4): Task<Result<Unit, String>> = {
  val wr = await Fs.writeTextAtomic(path, Json.stringify(ktiToJson(kti)))
  Res.mapError(wr, toFsErrorString)
}

export async fun readKtiFile(path: String): Task<Result<KtiV4, String>> = {
  val rr = await Fs.readText(path)
  match (rr) {
    Err(e) => Err(toFsErrorString(e))
    Ok(content) => match (Json.parse(content)) {
      Ok(v) => parseKti(v)
      Err(pe) => Err(Json.errorAsString(pe))
    }
  }
}

export fun deserializeExports(kti: KtiV4): Dict<String, Ty.InternalType> =
  Lst.foldl(Dict.toList(kti.functions), Dict.emptyStringDict(), (acc: Dict<String, Ty.InternalType>, p: (String, KtiExportEntry)) =>
    match (p.1) {
      KtiFunction(fe) => Dict.insert(acc, p.0, deserializeType(fe.type_))
    }
  )

export fun deserializeTypeAliases(kti: KtiV4): Dict<String, Ty.InternalType> =
  Lst.foldl(Dict.toList(kti.types), Dict.emptyStringDict(), (acc: Dict<String, Ty.InternalType>, p: (String, KtiTypeEntry)) => {
    val t = match (p.1.type_) {
      Some(tv) => deserializeType(tv)
      None => Ty.TApp(p.0, [])
    }
    Dict.insert(acc, p.0, t)
  })

export fun deserializeTypeVisibility(kti: KtiV4): Dict<String, String> =
  Lst.foldl(Dict.toList(kti.types), Dict.emptyStringDict(), (acc: Dict<String, String>, p: (String, KtiTypeEntry)) =>
    Dict.insert(acc, p.0, p.1.visibility)
  )

/// Deserialize ADT constructor maps from a KTI's `types` section.
///
/// Returns a 3-tuple:
/// 1. `ctorEnv`        — ctor name → deserialized InternalType (from `functions`)
/// 2. `adtConstructors` — ADT type name → ordered list of ctor names
/// 3. `ctorOwners`     — ctor name → owning ADT type name
export fun deserializeCtorMaps(kti: KtiV4): (Dict<String, Ty.InternalType>, Dict<String, List<String>>, Dict<String, String>) =
  Lst.foldl(Dict.toList(kti.types), (Dict.emptyStringDict(), Dict.emptyStringDict(), Dict.emptyStringDict()), (acc: (Dict<String, Ty.InternalType>, Dict<String, List<String>>, Dict<String, String>), p: (String, KtiTypeEntry)) =>
    match (p.1.constructors) {
      None => acc
      Some(ctors) => {
        val typeName = p.0
        val ctorNames = Lst.map(ctors, (c: (String, Int)) => c.0)
        val ctorEnv = Lst.foldl(ctors, acc.0, (env: Dict<String, Ty.InternalType>, c: (String, Int)) =>
          match (Dict.get(kti.functions, c.0)) {
            None => env
            Some(KtiFunction(fe)) => Dict.insert(env, c.0, deserializeType(fe.type_))
          }
        )
        val adtCtors = Dict.insert(acc.1, typeName, ctorNames)
        val ctorOwners = Lst.foldl(ctorNames, acc.2, (owners: Dict<String, String>, cn: String) =>
          Dict.insert(owners, cn, typeName)
        );
        (ctorEnv, adtCtors, ctorOwners)
      }
    }
  )

/// Wrap a namespace export map as a TNamespace InternalType (for import * as X bindings).
export fun makeNamespaceType(exports: Dict<String, Ty.InternalType>): Ty.InternalType =
  Ty.TNamespace(exports)

/// Build import bindings for a named import: add each requested name from dep exports to bindings.
export fun addNamedImportBindings(specs: List<Ast.ImportSpec>, depExports: Dict<String, Ty.InternalType>, bindings: Dict<String, Ty.InternalType>): Dict<String, Ty.InternalType> =
  match (specs) {
    [] => bindings
    h :: rest => {
      val t = Dict.get(depExports, h.external);
      val b2 = match (t) {
        None => bindings
        Some(ty) => Dict.insert(bindings, h.local, ty)
      };
      addNamedImportBindings(rest, depExports, b2)
    }
  }

export fun addNamedTypeAliasBindings(specs: List<Ast.ImportSpec>, depTypeAliases: Dict<String, Ty.InternalType>, bindings: Dict<String, Ty.InternalType>): Dict<String, Ty.InternalType> =
  match (specs) {
    [] => bindings
    h :: rest => {
      val t = Dict.get(depTypeAliases, h.external);
      val b2 = match (t) {
        None => bindings
        Some(ty) => Dict.insert(bindings, h.local, ty)
      };
      addNamedTypeAliasBindings(rest, depTypeAliases, b2)
    }
  }

fun appendUniqueStrings(existing: List<String>, extras: List<String>): List<String> =
  match (extras) {
    [] => existing
    x :: rest =>
      if (Lst.member(existing, x)) appendUniqueStrings(existing, rest)
      else appendUniqueStrings(Lst.append(existing, [x]), rest)
  }

fun collectOpaqueNamedImports(specs: List<Ast.ImportSpec>, depTypeAliases: Dict<String, Ty.InternalType>, depTypeVisibility: Dict<String, String>, acc: List<String>): List<String> =
  match (specs) {
    [] => Lst.reverse(acc)
    h :: rest => {
      val hasAlias = Dict.member(depTypeAliases, h.external)
      val isOpaque = match (Dict.get(depTypeVisibility, h.external)) {
        Some(v) => v == "opaque"
        None => False
      }
      if (hasAlias & isOpaque) collectOpaqueNamedImports(rest, depTypeAliases, depTypeVisibility, h.local :: acc)
      else collectOpaqueNamedImports(rest, depTypeAliases, depTypeVisibility, acc)
    }
  }

/// Per-dependency export snapshot used for re-export resolution in the self-hosted checker.
///
/// Holds the raw, unadapted export dictionaries for a single dependency module so that
/// `typecheck` can forward selected (or all) names when it sees `export * from` /
/// `export { x } from` declarations.
export type DepSnapshotEntry = {
  depExports: Dict<String, Ty.InternalType>,
  depTypeAliases: Dict<String, Ty.InternalType>,
  depTypeVisibility: Dict<String, String>
}

export type DepBindingBundle = {
  importBindings: Dict<String, Ty.InternalType>,
  typeAliasBindings: Dict<String, Ty.InternalType>,
  importOpaqueTypes: List<String>,
  depSnapshotsBySpec: Dict<String, DepSnapshotEntry>,
  importCtorEnv: Dict<String, Ty.InternalType>,
  importAdtConstructors: Dict<String, List<String>>,
  importCtorOwners: Dict<String, String>,
  importedNameToClass: Dict<String, String>,
  importedFunArities: Dict<String, Int>,
  importedValVarToClass: Dict<String, String>,
  importedVarNames: Dict<String, Unit>,
  importedNameToOriginal: Dict<String, String>,
  namespaceClasses: Dict<String, String>,
  namespaceAdtConstructors: Dict<String, Dict<String, String>>
}

/// Result of loading all dep KTIs — either a combined binding bundle or an error message.
export type DepLoadResult = DepLoadOk(DepBindingBundle) | DepLoadErr(String)

// Collect ctorEnv entries (local name → type) for named imports that are ADT constructors.
fun collectNamedImportCtorEnv(specs: List<Ast.ImportSpec>, depCtorEnv: Dict<String, Ty.InternalType>, depCtorOwners: Dict<String, String>, acc: Dict<String, Ty.InternalType>): Dict<String, Ty.InternalType> =
  match (specs) {
    [] => acc
    h :: rest =>
      match (Dict.get(depCtorOwners, h.external)) {
        None => collectNamedImportCtorEnv(rest, depCtorEnv, depCtorOwners, acc)
        Some(_) =>
          match (Dict.get(depCtorEnv, h.external)) {
            None => collectNamedImportCtorEnv(rest, depCtorEnv, depCtorOwners, acc)
            Some(ty) => collectNamedImportCtorEnv(rest, depCtorEnv, depCtorOwners, Dict.insert(acc, h.local, ty))
          }
      }
  }

// Collect ADT type names that have at least one constructor in the named import spec.
fun collectNamedImportAdtTypeNames(specs: List<Ast.ImportSpec>, depCtorOwners: Dict<String, String>, acc: List<String>): List<String> =
  match (specs) {
    [] => acc
    h :: rest =>
      match (Dict.get(depCtorOwners, h.external)) {
        None => collectNamedImportAdtTypeNames(rest, depCtorOwners, acc)
        Some(typeName) =>
          if (Lst.member(acc, typeName)) collectNamedImportAdtTypeNames(rest, depCtorOwners, acc)
          else collectNamedImportAdtTypeNames(rest, depCtorOwners, typeName :: acc)
      }
  }

// Merge full ADT ctor groups for the given type names into the accumulators.
fun mergeAdtCtorMapsForTypes(typeNames: List<String>, depAdtCtors: Dict<String, List<String>>, accAdtCtors: Dict<String, List<String>>, accCtorOwners: Dict<String, String>): (Dict<String, List<String>>, Dict<String, String>) =
  match (typeNames) {
    [] => (accAdtCtors, accCtorOwners)
    typeName :: rest =>
      match (Dict.get(depAdtCtors, typeName)) {
        None => mergeAdtCtorMapsForTypes(rest, depAdtCtors, accAdtCtors, accCtorOwners)
        Some(ctorNames) => {
          val newAdtCtors = Dict.insert(accAdtCtors, typeName, ctorNames)
          val newCtorOwners = Lst.foldl(ctorNames, accCtorOwners, (co: Dict<String, String>, cn: String) => Dict.insert(co, cn, typeName))
          mergeAdtCtorMapsForTypes(rest, depAdtCtors, newAdtCtors, newCtorOwners)
        }
      }
  }

// Accumulate codegen import maps for one ImportSpec from a named import statement.
// Returns updated (importedNameToClass, importedFunArities, importedValVarToClass, importedVarNames, importedNameToOriginal).
fun addSpecCodegenFun(ext: String, loc: String, arity: Int, depClassName: String, nameToClass: Dict<String, String>, funArities: Dict<String, Int>, nameToOriginal: Dict<String, String>): (Dict<String, String>, Dict<String, Int>, Dict<String, String>) = {
  val nc = Dict.insert(nameToClass, loc, depClassName);
  val na = Dict.insert(funArities, loc, arity);
  val no = if (loc != ext) { Dict.insert(nameToOriginal, loc, ext) } else { nameToOriginal };
  (nc, na, no)
}

fun addSpecCodegenVal(ext: String, loc: String, depClassName: String, isVar: Bool, valVarToClass: Dict<String, String>, varNames: Dict<String, Unit>, nameToOriginal: Dict<String, String>): (Dict<String, String>, Dict<String, Unit>, Dict<String, String>) = {
  val nv = Dict.insert(valVarToClass, loc, depClassName);
  val nvn = if (isVar) { Dict.insert(varNames, loc, ()) } else { varNames };
  val no = if (loc != ext) { Dict.insert(nameToOriginal, loc, ext) } else { nameToOriginal };
  (nv, nvn, no)
}

fun applySpecCodegen(spec: Ast.ImportSpec, meta: KtiCodegenMeta, depClassName: String, b: DepBindingBundle): DepBindingBundle = {
  val ext = spec.external;
  val loc = spec.local;
  if (Dict.member(meta.funArities, ext)) {
    val arity = Opt.getOrElse(Dict.get(meta.funArities, ext), 0);
    val updated = addSpecCodegenFun(ext, loc, arity, depClassName, b.importedNameToClass, b.importedFunArities, b.importedNameToOriginal);
    {
      importBindings = b.importBindings,
      typeAliasBindings = b.typeAliasBindings,
      importOpaqueTypes = b.importOpaqueTypes,
      depSnapshotsBySpec = b.depSnapshotsBySpec,
      importCtorEnv = b.importCtorEnv,
      importAdtConstructors = b.importAdtConstructors,
      importCtorOwners = b.importCtorOwners,
      importedNameToClass = updated.0,
      importedFunArities = updated.1,
      importedValVarToClass = b.importedValVarToClass,
      importedVarNames = b.importedVarNames,
      importedNameToOriginal = updated.2,
      namespaceClasses = b.namespaceClasses,
      namespaceAdtConstructors = b.namespaceAdtConstructors
    }
  } else if (Lst.member(meta.valOrVarNames, ext)) {
    val isVar = Lst.member(meta.varNames, ext);
    val updated = addSpecCodegenVal(ext, loc, depClassName, isVar, b.importedValVarToClass, b.importedVarNames, b.importedNameToOriginal);
    {
      importBindings = b.importBindings,
      typeAliasBindings = b.typeAliasBindings,
      importOpaqueTypes = b.importOpaqueTypes,
      depSnapshotsBySpec = b.depSnapshotsBySpec,
      importCtorEnv = b.importCtorEnv,
      importAdtConstructors = b.importAdtConstructors,
      importCtorOwners = b.importCtorOwners,
      importedNameToClass = b.importedNameToClass,
      importedFunArities = b.importedFunArities,
      importedValVarToClass = updated.0,
      importedVarNames = updated.1,
      importedNameToOriginal = updated.2,
      namespaceClasses = b.namespaceClasses,
      namespaceAdtConstructors = b.namespaceAdtConstructors
    }
  } else {
    b
  }
}

fun applySpecsCodegen(specs: List<Ast.ImportSpec>, meta: KtiCodegenMeta, depClassName: String, b: DepBindingBundle): DepBindingBundle =
  match (specs) {
    [] => b
    sp :: rest => applySpecsCodegen(rest, meta, depClassName, applySpecCodegen(sp, meta, depClassName, b))
  }

fun addNamedImportCodegen(specs: List<Ast.ImportSpec>, meta: KtiCodegenMeta, depClassName: String, b: DepBindingBundle): DepBindingBundle =
  applySpecsCodegen(specs, meta, depClassName, b)

// Build ctor-name → JVM-class map for a namespace dep's ADT constructors.
// depCtorOwners: ctor-name → ADT-type-name; ctorClass = depClassName + "$" + typeName + "$" + ctorName.
fun buildNsAdtCtorMap(entries: List<(String, String)>, depClassName: String, acc: Dict<String, String>): Dict<String, String> =
  match (entries) {
    [] => acc
    e :: rest => {
      val ctorName = e.0
      val typeName = e.1
      val ctorClass = "${depClassName}$${typeName}$${ctorName}"
      buildNsAdtCtorMap(rest, depClassName, Dict.insert(acc, ctorName, ctorClass))
    }
  }

fun emptyDepBundle(): DepBindingBundle = {
  importBindings = Dict.emptyStringDict(),
  typeAliasBindings = Dict.emptyStringDict(),
  importOpaqueTypes = [],
  depSnapshotsBySpec = Dict.emptyStringDict(),
  importCtorEnv = Dict.emptyStringDict(),
  importAdtConstructors = Dict.emptyStringDict(),
  importCtorOwners = Dict.emptyStringDict(),
  importedNameToClass = Dict.emptyStringDict(),
  importedFunArities = Dict.emptyStringDict(),
  importedValVarToClass = Dict.emptyStringDict(),
  importedVarNames = Dict.emptyStringDict(),
  importedNameToOriginal = Dict.emptyStringDict(),
  namespaceClasses = Dict.emptyStringDict(),
  namespaceAdtConstructors = Dict.emptyStringDict()
}

/// Load import bindings from dep KTIs. deps is a list of (spec, ktiPath, className) triples.
/// For each dep, read its KTI and process matching import decls.
export async fun loadDepBindings(deps: List<(String, String, String)>, imports: List<Ast.ImportDecl>): Task<DepLoadResult> =
  match (deps) {
    [] => DepLoadOk(emptyDepBundle())
    dep :: rest => {
      match (await readKtiFile(dep.1)) {
        Err(_) => DepLoadErr("dependency not compiled yet: ${dep.0} (missing ${dep.1})")
        Ok(depKti) => {
          val depClassName = dep.2;
          val depExports = deserializeExports(depKti);
          val depTypeAliases = deserializeTypeAliases(depKti);
          val depTypeVisibility = deserializeTypeVisibility(depKti);
          val depCtorMaps = deserializeCtorMaps(depKti);
          val depCtorEnv = depCtorMaps.0;
          val depAdtCtors = depCtorMaps.1;
          val depCtorOwners = depCtorMaps.2;
          val next: Task<DepLoadResult> = loadDepBindings(rest, imports)
          match (await next) {
            DepLoadErr(e) => DepLoadErr(e)
            DepLoadOk(acc) => {
              val merged = Lst.foldl(imports, acc, (b: DepBindingBundle, imp: Ast.ImportDecl) =>
                match (imp) {
                  IDNamed(spec, specs2) => {
                    if (spec == dep.0) {
                      val valueBindings = addNamedImportBindings(specs2, depExports, b.importBindings);
                      val typeBindings = addNamedTypeAliasBindings(specs2, depTypeAliases, b.typeAliasBindings);
                      val opaqueLocals = collectOpaqueNamedImports(specs2, depTypeAliases, depTypeVisibility, []);
                      val newCtorEnv = collectNamedImportCtorEnv(specs2, depCtorEnv, depCtorOwners, b.importCtorEnv);
                      val adtTypeNames = collectNamedImportAdtTypeNames(specs2, depCtorOwners, []);
                      val adtMaps = mergeAdtCtorMapsForTypes(adtTypeNames, depAdtCtors, b.importAdtConstructors, b.importCtorOwners);
                      val codegenBundle = addNamedImportCodegen(specs2, depKti.codegenMeta, depClassName, b);
                      {
                        importBindings = valueBindings,
                        typeAliasBindings = typeBindings,
                        importOpaqueTypes = appendUniqueStrings(b.importOpaqueTypes, opaqueLocals),
                        depSnapshotsBySpec = b.depSnapshotsBySpec,
                        importCtorEnv = newCtorEnv,
                        importAdtConstructors = adtMaps.0,
                        importCtorOwners = adtMaps.1,
                        importedNameToClass = codegenBundle.importedNameToClass,
                        importedFunArities = codegenBundle.importedFunArities,
                        importedValVarToClass = codegenBundle.importedValVarToClass,
                        importedVarNames = codegenBundle.importedVarNames,
                        importedNameToOriginal = codegenBundle.importedNameToOriginal,
                        namespaceClasses = b.namespaceClasses,
                        namespaceAdtConstructors = b.namespaceAdtConstructors
                      }
                    } else b
                  }
                  IDNamespace(spec, alias) => {
                    if (spec == dep.0) {
                      val nsBindings = Dict.union(depExports, depTypeAliases)
                      val nsAdtCtorMap = buildNsAdtCtorMap(Dict.toList(depCtorOwners), depClassName, Dict.emptyStringDict())
                      val newNsAdtCtors = if (Dict.isEmpty(nsAdtCtorMap)) b.namespaceAdtConstructors else Dict.insert(b.namespaceAdtConstructors, alias, nsAdtCtorMap)
                      {
                        importBindings = Dict.insert(b.importBindings, alias, makeNamespaceType(nsBindings)),
                        typeAliasBindings = b.typeAliasBindings,
                        importOpaqueTypes = b.importOpaqueTypes,
                        depSnapshotsBySpec = b.depSnapshotsBySpec,
                        importCtorEnv = b.importCtorEnv,
                        importAdtConstructors = Dict.union(depAdtCtors, b.importAdtConstructors),
                        importCtorOwners = Dict.union(depCtorOwners, b.importCtorOwners),
                        importedNameToClass = b.importedNameToClass,
                        importedFunArities = b.importedFunArities,
                        importedValVarToClass = b.importedValVarToClass,
                        importedVarNames = b.importedVarNames,
                        importedNameToOriginal = b.importedNameToOriginal,
                        namespaceClasses = Dict.insert(b.namespaceClasses, alias, depClassName),
                        namespaceAdtConstructors = newNsAdtCtors
                      }
                    } else b
                  }
                  _ => b
                }
              );
              // Record the full export snapshot for this dep (used by re-export resolution).
              val snapshot = { depExports = depExports, depTypeAliases = depTypeAliases, depTypeVisibility = depTypeVisibility }
              DepLoadOk({
                importBindings = merged.importBindings,
                typeAliasBindings = merged.typeAliasBindings,
                importOpaqueTypes = merged.importOpaqueTypes,
                depSnapshotsBySpec = Dict.insert(merged.depSnapshotsBySpec, dep.0, snapshot),
                importCtorEnv = merged.importCtorEnv,
                importAdtConstructors = merged.importAdtConstructors,
                importCtorOwners = merged.importCtorOwners,
                importedNameToClass = merged.importedNameToClass,
                importedFunArities = merged.importedFunArities,
                importedValVarToClass = merged.importedValVarToClass,
                importedVarNames = merged.importedVarNames,
                importedNameToOriginal = merged.importedNameToOriginal,
                namespaceClasses = merged.namespaceClasses,
                namespaceAdtConstructors = merged.namespaceAdtConstructors
              })
            }
          }
        }
      }
    }
  }
