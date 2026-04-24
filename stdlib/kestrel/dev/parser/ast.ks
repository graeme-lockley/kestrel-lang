//! AST definitions for the Kestrel development parser.
//!
//! This module defines type-level AST nodes (`AstType`), expression and statement
//! nodes, declaration nodes, import/export nodes, and the top-level `Program` shape.
//! It is consumed by [`kestrel:dev/parser/parser`](/docs/kestrel:dev/parser/parser)
//! and downstream tools such as formatter, typechecker, and code generators.

import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"
import * as Token from "kestrel:dev/parser/token"

// Naming convention: field/type names that clash with Kestrel reserved words
// get a trailing underscore: type_, mut_, async_.

// ─── Type-level AST ──────────────────────────────────────────────────────────

// TypeField is a single field in a record type expression.
export type TypeField = { name: String, mut_: Bool, type_: AstType }

// AstType represents a parsed type expression.
export type AstType =
    ATIdent(String)                    // simple name e.g. "Foo"
  | ATQualified(String, String)         // qualified Mod.T (module name, type name)
  | ATPrim(String)                     // primitive: "Int" | "Float" | "Bool" | "String" | "Unit" | "Char"
  | ATArrow(List<AstType>, AstType)    // function type (A, B) -> C
  | ATRecord(List<TypeField>)          // record type { x: Int, mut y: Bool }
  | ATRowVar(String)                   // row type variable { ...r }
  | ATApp(String, List<AstType>)       // generic application List<T>
  | ATUnion(AstType, AstType)          // union A | B
  | ATInter(AstType, AstType)          // intersection A & B
  | ATTuple(List<AstType>)             // tuple product A * B * C

/// Stable tag for `AstType` nodes.
export fun astTypeTag(t: AstType): String =
  match (t) {
    ATIdent(_) => "ident"
    ATQualified(_, _) => "qualified"
    ATPrim(_) => "prim"
    ATArrow(_, _) => "arrow"
    ATRecord(_) => "record"
    ATRowVar(_) => "rowvar"
    ATApp(_, _) => "app"
    ATUnion(_, _) => "union"
    ATInter(_, _) => "inter"
    ATTuple(_) => "tuple"
  }

export fun astTypeIdentName(t: AstType): Option<String> =
  match (t) {
    ATIdent(name) => Some(name)
    _ => None
  }

export fun astTypeQualifiedParts(t: AstType): Option<(String, String)> =
  match (t) {
    ATQualified(ns, name) => Some((ns, name))
    _ => None
  }

export fun astTypePrimName(t: AstType): Option<String> =
  match (t) {
    ATPrim(name) => Some(name)
    _ => None
  }

export fun astTypeArrowParts(t: AstType): Option<(List<AstType>, AstType)> =
  match (t) {
    ATArrow(params, ret) => Some((params, ret))
    _ => None
  }

export fun astTypeRecordFields(t: AstType): Option<List<TypeField>> =
  match (t) {
    ATRecord(fields) => Some(fields)
    _ => None
  }

export fun astTypeRowVarName(t: AstType): Option<String> =
  match (t) {
    ATRowVar(name) => Some(name)
    _ => None
  }

export fun astTypeAppParts(t: AstType): Option<(String, List<AstType>)> =
  match (t) {
    ATApp(name, args) => Some((name, args))
    _ => None
  }

export fun astTypeUnionParts(t: AstType): Option<(AstType, AstType)> =
  match (t) {
    ATUnion(left, right) => Some((left, right))
    _ => None
  }

export fun astTypeInterParts(t: AstType): Option<(AstType, AstType)> =
  match (t) {
    ATInter(left, right) => Some((left, right))
    _ => None
  }

export fun astTypeTupleElements(t: AstType): Option<List<AstType>> =
  match (t) {
    ATTuple(elements) => Some(elements)
    _ => None
  }

// Param is a function or lambda parameter.
export type Param = { name: String, type_: Option<AstType> }

// ─── Pattern AST ─────────────────────────────────────────────────────────────

// ConField is one argument position in a constructor pattern.
// Positional: { name = "__field_0", pattern = Some(p) }
// Record-style: { name = "fieldName", pattern = Some(p) } or { name = "fieldName", pattern = None }
export type ConField = { name: String, pattern: Option<Pattern> }

export type Pattern =
    PWild                                     // wildcard _
  | PVar(String)                              // variable binding x
  | PLit(String, String)                      // literal pattern (kind, raw-value) e.g. ("int","42")
  | PCon(String, List<ConField>)              // constructor pattern Some(x) or Con{f=p}
  | PList(List<Pattern>, Option<String>)      // list pattern [a, b, ...rest]
  | PCons(Pattern, Pattern)                   // cons pattern head :: tail
  | PTuple(List<Pattern>)                     // tuple pattern (a, b, c)

// ─── Expression AST ──────────────────────────────────────────────────────────

export type RecField = { name: String, mut_: Bool, value: Expr }
export type ListElem = LElem(Expr) | LSpread(Expr)
export type TmplPart = TmplLit(String) | TmplExpr(Expr)
export type Case_ = { pattern: Pattern, body: Expr }
export type Block = { stmts: List<Stmt>, result: Expr }

export type Expr =
    ELit(String, String)                      // literal (kind, raw-value)
  | EIdent(String)                            // identifier
  | ECall(Expr, List<Expr>)                   // function call f(args)
  | EField(Expr, String)                      // field access obj.field
  | EAwait(Expr)                              // await e
  | EUnary(String, Expr)                      // unary operator op e
  | EBinary(String, Expr, Expr)               // binary operator l op r
  | ECons(Expr, Expr)                         // list cons a :: b
  | EPipe(String, Expr, Expr)                 // pipe left |> right or left <| right
  | EIf(Expr, Expr, Option<Expr>)             // if cond then else?
  | EWhile(Expr, Block)                       // while cond body
  | EMatch(Expr, List<Case_>)                 // match scrutinee { cases }
  | ELambda(Bool, List<String>, List<Param>, Expr)  // lambda (async, typeParams, params, body)
  | ETemplate(List<TmplPart>)                 // interpolated string
  | EList(List<ListElem>)                     // list literal [elems]
  | ERecord(Option<Expr>, List<RecField>)     // record literal { ...spread?, fields }
  | ETuple(List<Expr>)                        // tuple (a, b, c)
  | EThrow(Expr)                              // throw e
  | ETry(Block, Option<String>, List<Case_>)  // try { } catch(var?) { cases }
  | EBlock(Block)                             // block expression { stmts; result }
  | EIs(Expr, AstType)                        // type test e is T
  | ENever                                    // synthetic unreachable (break/continue result)

// ─── Statement AST ───────────────────────────────────────────────────────────

export type Stmt =
    SVal(String, Option<AstType>, Expr)                          // val name : T? = e
  | SVar(String, Option<AstType>, Expr)                          // var name : T? = e
  | SAssign(Expr, Expr)                                          // target := rhs
  | SExpr(Expr)                                                  // standalone expression
  | SFun(Bool, String, List<String>, List<Param>, AstType, Expr) // local fun (async, name, typeParams, params, retType, body)
  | SBreak                                                       // break
  | SContinue                                                    // continue

// ─── Declaration AST ─────────────────────────────────────────────────────────

export type CtorDef = { name: String, params: List<AstType> }
export type TypeBody = TBAdt(List<CtorDef>) | TBAlias(AstType)
export type FunDecl = {
  exported: Bool,
  async_: Bool,
  name: String,
  typeParams: List<String>,
  params: List<Param>,
  retType: AstType,
  body: Expr
}
export type ExternFunDecl = {
  exported: Bool,
  name: String,
  typeParams: List<String>,
  params: List<Param>,
  retType: AstType,
  jvmDesc: String
}
export type ExternTypeDecl = {
  visibility: String,         // "local" | "opaque" | "export"
  name: String,
  typeParams: List<String>,
  jvmClass: String
}
export type ExternOverride = { name: String, params: List<Param>, retType: AstType }
export type ExternImportDecl = { target: String, alias: String, overrides: List<ExternOverride> }
export type TypeDecl = { visibility: String, name: String, typeParams: List<String>, body: TypeBody }
export type ExceptionDecl = { exported: Bool, name: String, fields: Option<List<TypeField>> }

// ─── Import / Export / Program AST ───────────────────────────────────────────

export type ImportSpec = { external: String, local: String }

export type ImportDecl =
    IDNamed(String, List<ImportSpec>)  // import { x, y as z } from "spec"
  | IDNamespace(String, String)        // import * as M from "spec" (spec, alias)
  | IDSideEffect(String)              // import "spec"

export type ExportInner =
    EIStar(String)                     // export * from "spec"
  | EINamed(String, List<ImportSpec>)  // export { x } from "spec"
  | EIDecl(TopDecl)                    // export <decl>

export type TopDecl =
    TDFun(FunDecl)
  | TDExternFun(ExternFunDecl)
  | TDExternImport(ExternImportDecl)
  | TDExternType(ExternTypeDecl)
  | TDType(TypeDecl)
  | TDException(ExceptionDecl)
  | TDExport(ExportInner)
  | TDVal(String, Option<AstType>, Expr)  // export val name : T? = e
  | TDVar(String, Option<AstType>, Expr)  // export var name : T? = e
  | TDSVal(String, Expr)                  // top-level val name = e (no type, no export)
  | TDSVar(String, Expr)                  // top-level var name = e (no type, no export)
  | TDSAssign(Expr, Expr)                 // top-level assignment
  | TDSExpr(Expr)                         // top-level expression statement

export type Program = { imports: List<ImportDecl>, body: List<TopDecl> }
