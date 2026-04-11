// kestrel:tools/format/formatter — pure Kestrel source code formatting engine.
// Converts AST to pretty-printed source text via a Doc intermediate representation.

import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as Dict from "kestrel:data/dict"
import * as Arr from "kestrel:data/array"
import { readText, writeText } from "kestrel:io/fs"
import * as PP from "kestrel:dev/text/prettyprinter"
import { Doc } from "kestrel:dev/text/prettyprinter"
import * as Token from "kestrel:dev/parser/token"
import { TkLineComment, TkBlockComment, TkWs, TkPunct, TkOp } from "kestrel:dev/parser/token"
import * as Ast from "kestrel:dev/parser/ast"
import {
  ELit, EIdent, ECall, EField, EAwait, EUnary, EBinary, ECons, EPipe,
  EIf, EWhile, ELambda, ETemplate, EList, ERecord, ETuple,
  EMatch, EBlock, EThrow, ETry, EIs, ENever,
  TmplLit, TmplExpr, LElem, LSpread,
  SVal, SVar, SAssign, SExpr, SFun, SBreak, SContinue,
  TDFun, TDExternFun, TDExternImport, TDExternType, TDType, TDException, TDExport,
  TDVal, TDVar, TDSVal, TDSVar, TDSAssign, TDSExpr,
  IDNamed, IDNamespace, IDSideEffect, EIStar, EINamed, EIDecl,
  ATPrim, ATIdent, ATApp, ATArrow, ATRecord, ATTuple, ATUnion, ATInter, ATRowVar, ATQualified,
  PWild, PVar, PLit, PCon, PList, PCons, PTuple,
  TBAdt, TBAlias
} from "kestrel:dev/parser/ast"
import * as Lex from "kestrel:dev/parser/lexer"
import { parse, ParseError } from "kestrel:dev/parser/parser"

// ─── Error type ───────────────────────────────────────────────────────────────

export type FormatError =
    FmtParseError(String, Int, Int, Int)  // (message, offset, line, col)
  | FmtIoError(String)                   // I/O error message

// ─── Constants ────────────────────────────────────────────────────────────────

export val fmtWidth: Int = 120
export val fmtIndent: Int = 2

// ─── Literal encoders ─────────────────────────────────────────────────────────

fun escapeStringChar(c: Char): String =
  if (c == '\n') "\\n"
  else if (c == '\r') "\\r"
  else if (c == '\t') "\\t"
  else if (c == '\\') "\\\\"
  else if (c == '"') "\\\""
  else Str.fromChar(c)

fun escapeCharLitChar(c: Char): String =
  if (c == '\n') "\\n"
  else if (c == '\r') "\\r"
  else if (c == '\t') "\\t"
  else if (c == '\\') "\\\\"
  else if (c == '\'') "\\'"
  else Str.fromChar(c)

export fun encodeString(s: String): String =
  "\"${Str.concat(Lst.map(Str.toList(s), escapeStringChar))}\""

export fun encodeChar(c: String): String =
  match (Str.toList(c)) {
    [] => "''"
    ch :: _ => "'${escapeCharLitChar(ch)}'"
  }

// ─── Doc helpers ──────────────────────────────────────────────────────────────

fun commaDoc(docs: List<Doc>): Doc =
  PP.encloseSep(PP.text("("), PP.text(")"), PP.text(", "), docs)

fun commaSepBreak(open: String, close: String, docs: List<Doc>): Doc =
  PP.group(PP.hcat([
    PP.text(open),
    PP.nest(fmtIndent, PP.hcat(PP.punctuate(PP.concat(PP.comma, PP.line), docs))),
    PP.text(close)
  ]))

// ─── Type expression Doc ─────────────────────────────────────────────────────

fun fmtTypeField(f: Ast.TypeField): Doc =
  if (f.mut_)
    PP.hcat([PP.text("mut "), PP.text(f.name), PP.text(": "), fmtType(f.type_)])
  else
    PP.hcat([PP.text(f.name), PP.text(": "), fmtType(f.type_)])

fun fmtType(t: Ast.AstType): Doc =
  match (t) {
    ATPrim(n) => PP.text(n)
    ATIdent(n) => PP.text(n)
    ATQualified(m, n) => PP.text("${m}.${n}")
    ATRowVar(r) => PP.text("...${r}")
    ATApp(n, args) => PP.hcat([
      PP.text(n),
      PP.text("<"),
      PP.hcat(PP.punctuate(PP.text(", "), Lst.map(args, fmtType))),
      PP.text(">")
    ])
    ATUnion(a, b) => PP.hsep([fmtType(a), PP.text("|"), fmtType(b)])
    ATInter(a, b) => PP.hsep([fmtType(a), PP.text("&"), fmtType(b)])
    ATTuple(ts) => PP.hcat(PP.punctuate(PP.text(" * "), Lst.map(ts, fmtType)))
    ATRecord(fields) =>
      if (Lst.isEmpty(fields)) PP.text("{}")
      else PP.group(PP.encloseSep(
      PP.text("{ "), PP.text(" }"), PP.text(", "), Lst.map(fields, fmtTypeField)
    ))
    ATArrow(params, ret) =>
      if (Lst.isEmpty(params)) fmtType(ret)
      else if (Lst.length(params) == 1)
        match (Lst.head(params)) {
          None => fmtType(ret)
          Some(p) => PP.hcat([fmtType(p), PP.text(" -> "), fmtType(ret)])
        }
      else PP.hcat([
        PP.text("("),
        PP.hcat(PP.punctuate(PP.text(", "), Lst.map(params, fmtType))),
        PP.text(") -> "),
        fmtType(ret)
      ])
  }

fun fmtParam(p: Ast.Param): Doc =
  match (p.type_) {
    None => PP.text(p.name)
    Some(t) => PP.hcat([PP.text(p.name), PP.text(": "), fmtType(t)])
  }

fun fmtTypeParams(ps: List<String>): Doc =
  match (ps) {
    [] => PP.empty
    _ => PP.hcat([
      PP.text("<"),
      PP.hcat(PP.punctuate(PP.text(", "), Lst.map(ps, PP.text))),
      PP.text(">")
    ])
  }

fun fmtParamList(ps: List<Ast.Param>): Doc =
  PP.encloseSep(PP.text("("), PP.text(")"), PP.text(", "), Lst.map(ps, fmtParam))

// ─── Pattern Doc ─────────────────────────────────────────────────────────────

fun isPositionalField(f: Ast.ConField): Bool =
  Str.startsWith("__field_", f.name)

fun fmtConField(f: Ast.ConField): Doc =
  if (isPositionalField(f))
    match (f.pattern) {
      None => PP.text("_")
      Some(p) => fmtPattern(p)
    }
  else
    match (f.pattern) {
      None => PP.text(f.name)
      Some(pat) =>
        match (pat) {
          PVar(n) =>
            if (Str.equals(n, f.name))
              PP.text(f.name)
            else
              PP.hcat([PP.text(f.name), PP.text(" = "), PP.text(n)])
          _ => PP.hcat([PP.text(f.name), PP.text(" = "), fmtPattern(pat)])
        }
    }

fun fmtPattern(p: Ast.Pattern): Doc =
  match (p) {
    PWild => PP.text("_")
    PVar(x) => PP.text(x)
    PLit(kind, v) =>
      if (Str.equals(kind, "unit")) PP.text("()")
      else if (Str.equals(kind, "true")) PP.text("True")
      else if (Str.equals(kind, "false")) PP.text("False")
      else if (Str.equals(kind, "string")) PP.text("\"${v}\"")
      else if (Str.equals(kind, "char")) PP.text("'${v}'")
      else PP.text(v)
    PCon(n, fields) =>
      if (Lst.isEmpty(fields)) PP.text(n)
      else if (Lst.all(fields, isPositionalField))
        PP.hcat([PP.text(n), commaDoc(Lst.map(fields, fmtConField))])
      else
        PP.hcat([
          PP.text(n),
          PP.text("{"),
          PP.hcat(PP.punctuate(PP.text(", "), Lst.map(fields, fmtConField))),
          PP.text("}")
        ])
    PList(pats, tail) =>
      match (tail) {
        None =>
          if (Lst.isEmpty(pats)) PP.text("[]")
          else PP.hcat([
            PP.text("["),
            PP.hcat(PP.punctuate(PP.text(", "), Lst.map(pats, fmtPattern))),
            PP.text("]")
          ])
        Some(rest) => PP.hcat([
          PP.text("["),
          PP.hcat(PP.punctuate(PP.text(", "), Lst.map(pats, fmtPattern))),
          PP.text(", ...${rest}]")
        ])
      }
    PCons(h, t) => PP.hsep([fmtPatternAtom(h), PP.text("::"), fmtPattern(t)])
    PTuple(ps) => commaDoc(Lst.map(ps, fmtPattern))
  }

fun fmtPatternAtom(p: Ast.Pattern): Doc =
  match (p) {
    PCons(_, _) => PP.hcat([PP.text("("), fmtPattern(p), PP.text(")")])
    _ => fmtPattern(p)
  }

// ─── Expression Doc ───────────────────────────────────────────────────────────

fun exprPrec(e: Ast.Expr): Int =
  match (e) {
    EPipe(_, _, _) => 0
    ECons(_, _) => 1
    EBinary(op, _, _) =>
      if (Str.equals(op, "|")) 2
      else if (Str.equals(op, "&")) 3
      else if (Str.equals(op, "==") | Str.equals(op, "!=") |
               Str.equals(op, "<")  | Str.equals(op, ">")  |
               Str.equals(op, "<=") | Str.equals(op, ">=")) 5
      else if (Str.equals(op, "+") | Str.equals(op, "-")) 6
      else if (Str.equals(op, "*") | Str.equals(op, "/") | Str.equals(op, "%")) 7
      else if (Str.equals(op, "**")) 8
      else 10
    EIs(_, _) => 4
    EUnary(_, _) => 9
    _ => 10
  }

fun isRightAssoc(op: String): Bool =
  Str.equals(op, "**") | Str.equals(op, "::") | Str.equals(op, "|>") | Str.equals(op, "<|")

fun needsParens(parentPrec: Int, childExpr: Ast.Expr, isRightChild: Bool): Bool = {
  val cp = exprPrec(childExpr)
  if (cp < parentPrec) True
  else if (cp == parentPrec) {
    match (childExpr) {
      EPipe(op, _, _) => if (isRightAssoc(op)) !isRightChild else isRightChild
      ECons(_, _) => if (isRightAssoc("::")) !isRightChild else isRightChild
      EBinary(op, _, _) => if (isRightAssoc(op)) !isRightChild else isRightChild
      _ => False
    }
  }
  else False
}

fun wrapParens(d: Doc): Doc =
  PP.hcat([PP.text("("), d, PP.text(")")])

fun fmtExprInCtx(prec: Int, isRight: Bool, e: Ast.Expr): Doc =
  if (needsParens(prec, e, isRight))
    wrapParens(fmtExpr(e))
  else
    fmtExpr(e)

fun fmtLit(kind: String, value: String): Doc =
  if (Str.equals(kind, "string")) PP.text("\"${value}\"")
  else if (Str.equals(kind, "char")) PP.text("'${value}'")
  else if (Str.equals(kind, "unit")) PP.text("()")
  else if (Str.equals(kind, "true")) PP.text("True")
  else if (Str.equals(kind, "false")) PP.text("False")
  else PP.text(value)

fun fmtCallExpr(callee: Ast.Expr, args: List<Ast.Expr>): Doc =
  PP.hcat([fmtExpr(callee), commaSepBreak("(", ")", Lst.map(args, fmtExpr))])

fun fmtBinaryExpr(op: String, l: Ast.Expr, r: Ast.Expr): Doc = {
  val prec = exprPrec(EBinary(op, l, r))
  val leftDoc = fmtExprInCtx(prec, False, l)
  val rightDoc = fmtExprInCtx(prec, True, r)
  PP.group(PP.hsep([leftDoc, PP.text(op), rightDoc]))
}

fun fmtIfExpr(cond: Ast.Expr, then_: Ast.Expr, else_: Option<Ast.Expr>): Doc = {
  val condDoc = PP.hcat([PP.text("if ("), fmtExpr(cond), PP.text(")")])
  val thenDoc = match (then_) {
    EBlock(b) => PP.beside(condDoc, fmtBlock(b))
    _ => PP.group(PP.hcat([condDoc, PP.nest(fmtIndent, PP.concat(PP.line, fmtExpr(then_)))]))
  }
  match (else_) {
    None => thenDoc
    Some(e) =>
      match (e) {
        EIf(c2, t2, e2) =>
          PP.hcat([thenDoc, PP.text(" else "), fmtIfExpr(c2, t2, e2)])
        EBlock(b) =>
          PP.hcat([thenDoc, PP.text(" else "), fmtBlock(b)])
        _ =>
          PP.hcat([
            thenDoc,
            PP.group(PP.hcat([
              PP.text(" else"),
              PP.nest(fmtIndent, PP.concat(PP.line, fmtExpr(e)))
            ]))
          ])
      }
  }
}

fun fmtWhileExpr(cond: Ast.Expr, body: Ast.Block): Doc =
  PP.hcat([PP.text("while ("), fmtExpr(cond), PP.text(") "), fmtBlock(body)])

fun fmtCase(c: Ast.Case_): Doc =
  PP.hcat([
    fmtPattern(c.pattern),
    PP.text(" =>"),
    PP.nest(fmtIndent, PP.concat(PP.line, fmtExpr(c.body)))
  ])

fun fmtMatchExpr(scrutinee: Ast.Expr, cases: List<Ast.Case_>): Doc = {
  val header = PP.hcat([PP.text("match ("), fmtExpr(scrutinee), PP.text(") {")])
  val caseItem = (c: Ast.Case_) =>
    PP.nest(fmtIndent, PP.concat(PP.lineBreak, fmtCase(c)))
  val caseDoc = PP.hcat(PP.punctuate(PP.text(","), Lst.map(cases, caseItem)))
  PP.hcat([header, caseDoc, PP.lineBreak, PP.text("}")])
}

fun fmtLambdaExpr(async_: Bool, typeParams: List<String>, params: List<Ast.Param>, body: Ast.Expr): Doc = {
  val asyncPrefix = if (async_) PP.text("async ") else PP.empty
  val tpDoc = fmtTypeParams(typeParams)
  val paramsDoc = fmtParamList(params)
  val bodyDoc = fmtExpr(body)
  PP.group(PP.hcat([asyncPrefix, tpDoc, paramsDoc, PP.text(" => "), bodyDoc]))
}

val dollarBrace = Str.concat([Str.fromChar('$'), "{"])

fun fmtTmplPart(p: Ast.TmplPart): String =
  match (p) {
    TmplLit(s) => s
    TmplExpr(e) => Str.concat([dollarBrace, PP.pretty(fmtWidth, fmtExpr(e)), "}"])
  }

fun fmtTemplateExpr(parts: List<Ast.TmplPart>): Doc =
  PP.text("\"${Str.concat(Lst.map(parts, fmtTmplPart))}\"")

fun fmtListElem(e: Ast.ListElem): Doc =
  match (e) {
    LElem(ex) => fmtExpr(ex)
    LSpread(ex) => PP.hcat([PP.text("..."), fmtExpr(ex)])
  }

fun fmtListLiteral(elems: List<Ast.ListElem>): Doc =
  match (elems) {
    [] => PP.text("[]")
    _ => commaSepBreak("[", "]", Lst.map(elems, fmtListElem))
  }

fun fmtRecField(f: Ast.RecField): Doc = {
  val prefix = if (f.mut_) PP.text("mut ") else PP.empty
  PP.hcat([prefix, PP.text(f.name), PP.text(" = "), fmtExpr(f.value)])
}

fun fmtRecordLiteral(spread: Option<Ast.Expr>, fields: List<Ast.RecField>): Doc = {
  val spreadDocs = match (spread) {
    None => []
    Some(e) => [PP.hcat([PP.text("..."), fmtExpr(e)])]
  }
  val fieldDocs = Lst.map(fields, fmtRecField)
  val allDocs = Lst.append(spreadDocs, fieldDocs)
  match (allDocs) {
    [] => PP.text("{}")
    _ =>
      PP.group(PP.hcat([
        PP.text("{ "),
        PP.nest(fmtIndent, PP.hcat(PP.punctuate(PP.concat(PP.comma, PP.line), allDocs))),
        PP.text(" }")
      ]))
  }
}

fun fmtTupleLiteral(elems: List<Ast.Expr>): Doc =
  commaDoc(Lst.map(elems, fmtExpr))

fun fmtPipeExpr(op: String, l: Ast.Expr, r: Ast.Expr): Doc =
  PP.hcat([
    fmtExpr(l),
    PP.nest(fmtIndent, PP.hcat([
      PP.lineBreak,
      PP.text("${op} "),
      fmtExpr(r)
    ]))
  ])

fun fmtConsExpr(l: Ast.Expr, r: Ast.Expr): Doc =
  PP.hsep([fmtExprInCtx(1, False, l), PP.text("::"), fmtExprInCtx(1, True, r)])

fun fmtTryExpr(body: Ast.Block, catchVar: Option<String>, cases: List<Ast.Case_>): Doc = {
  val tryPart = PP.hcat([PP.text("try "), fmtBlock(body)])
  val catchHeader = match (catchVar) {
    None => PP.text(" catch {")
    Some(v) => PP.text(" catch(${v}) {")
  }
  val caseItem = (c: Ast.Case_) =>
    PP.nest(fmtIndent, PP.concat(PP.lineBreak, fmtCase(c)))
  val caseDoc = PP.hcat(PP.punctuate(PP.text(","), Lst.map(cases, caseItem)))
  PP.hcat([tryPart, catchHeader, caseDoc, PP.lineBreak, PP.text("}")])
}

fun fmtExpr(e: Ast.Expr): Doc =
  match (e) {
    ELit(kind, value) => fmtLit(kind, value)
    EIdent(name) => PP.text(name)
    ECall(callee, args) => fmtCallExpr(callee, args)
    EField(obj, field) => PP.hcat([fmtExpr(obj), PP.text(".${field}")])
    EAwait(inner) => PP.beside(PP.text("await"), fmtExpr(inner))
    EUnary(op, inner) => PP.hcat([PP.text(op), fmtExprInCtx(9, False, inner)])
    EBinary(op, l, r) => fmtBinaryExpr(op, l, r)
    ECons(l, r) => fmtConsExpr(l, r)
    EPipe(op, l, r) => fmtPipeExpr(op, l, r)
    EIf(cond, then_, else_) => fmtIfExpr(cond, then_, else_)
    EWhile(cond, body) => fmtWhileExpr(cond, body)
    EMatch(scrutinee, cases) => fmtMatchExpr(scrutinee, cases)
    ELambda(async_, typeParams, params, body) => fmtLambdaExpr(async_, typeParams, params, body)
    ETemplate(parts) => fmtTemplateExpr(parts)
    EList(elems) => fmtListLiteral(elems)
    ERecord(spread, fields) => fmtRecordLiteral(spread, fields)
    ETuple(elems) => fmtTupleLiteral(elems)
    EThrow(inner) => PP.beside(PP.text("throw"), fmtExpr(inner))
    ETry(body, catchVar, cases) => fmtTryExpr(body, catchVar, cases)
    EBlock(b) => fmtBlock(b)
    EIs(expr, t) => PP.hsep([fmtExpr(expr), PP.text("is"), fmtType(t)])
    ENever => PP.empty
  }

// ─── Statement and Block Doc ─────────────────────────────────────────────────

// exprTailNeedsGuard returns True when an expression's final rendered token is
// an identifier, field name, or ')' (call result) — i.e. something that the
// parser would treat as a call callee if the very next token were '('.  When
// such a stmt is immediately followed in a block by an item whose text starts
// with '(' (a tuple or unit literal), we must emit a trailing ';' to prevent
// the second format pass from fusing them into a function call.
fun exprTailNeedsGuard(e: Ast.Expr): Bool =
  match (e) {
    EIdent(_)              => True
    EField(_, _)           => True
    ECall(_, _)            => True
    EBinary(_, _, r)       => exprTailNeedsGuard(r)
    ECons(_, r)            => exprTailNeedsGuard(r)
    EPipe(_, _, r)         => exprTailNeedsGuard(r)
    EIf(_, t, elseBr)      =>
      match (elseBr) {
        None     => exprTailNeedsGuard(t)
        Some(el) => exprTailNeedsGuard(el)
      }
    EUnary(_, inner)       => exprTailNeedsGuard(inner)
    EAwait(inner)          => exprTailNeedsGuard(inner)
    EThrow(inner)          => exprTailNeedsGuard(inner)
    ELambda(_, _, _, body) => exprTailNeedsGuard(body)
    _                      => False
  }

fun stmtTailNeedsGuard(s: Ast.Stmt): Bool =
  match (s) {
    SVal(_, _, e)        => exprTailNeedsGuard(e)
    SVar(_, _, e)        => exprTailNeedsGuard(e)
    SExpr(e)             => exprTailNeedsGuard(e)
    SAssign(_, rhs)      => exprTailNeedsGuard(rhs)
    SFun(_, _, _, _, _, body) => exprTailNeedsGuard(body)
    _                    => False
  }

// Returns True when an expression, when formatted, starts with '('.
fun exprStartsWithParen(e: Ast.Expr): Bool =
  match (e) {
    ETuple(_)   => True
    ELit(k, _) => Str.equals(k, "unit")
    _           => False
  }

// Returns True when a statement, when formatted, starts with '('.
fun stmtStartsWithParen(s: Ast.Stmt): Bool =
  match (s) {
    SExpr(e)        => exprStartsWithParen(e)
    SAssign(lhs, _) => exprStartsWithParen(lhs)
    _               => False
  }

fun fmtStmt(s: Ast.Stmt): Doc =
  match (s) {
    SVal(name, typeAnn, e) =>
      match (typeAnn) {
        None => PP.hsep([PP.text("val"), PP.text(name), PP.text("="), fmtExpr(e)])
        Some(t) => PP.hsep([PP.text("val"), PP.hcat([PP.text(name), PP.text(": "), fmtType(t)]), PP.text("="), fmtExpr(e)])
      }
    SVar(name, typeAnn, e) =>
      match (typeAnn) {
        None => PP.hsep([PP.text("var"), PP.text(name), PP.text("="), fmtExpr(e)])
        Some(t) => PP.hsep([PP.text("var"), PP.hcat([PP.text(name), PP.text(": "), fmtType(t)]), PP.text("="), fmtExpr(e)])
      }
    SAssign(target, rhs) => PP.hsep([fmtExpr(target), PP.text(":="), fmtExpr(rhs)])
    SExpr(expr) => fmtExpr(expr)
    SFun(async_, name, typeParams, params, retType, body) =>
      fmtFunBody(fmtFunSignature(False, async_, name, typeParams, params, retType), body)
    SBreak => PP.text("break")
    SContinue => PP.text("continue")
  }

// Returns the stmt docs for a block, appending ';' where necessary to prevent
// the parser from fusing a callee-tailed stmt with a following '('-started item.
fun buildGuardedStmtDocs(stmts: List<Ast.Stmt>, nextParen: Bool): List<Doc> =
  match (stmts) {
    [] => []
    s :: rest => {
      val thisNextParen = match (Lst.head(rest)) {
        None    => nextParen
        Some(n) => stmtStartsWithParen(n)
      }
      val doc = fmtStmt(s)
      val guarded =
        if (thisNextParen & stmtTailNeedsGuard(s)) PP.hcat([doc, PP.text(";")])
        else doc
      guarded :: buildGuardedStmtDocs(rest, nextParen)
    }
  }

fun fmtBlock(b: Ast.Block): Doc = {
  val isUnitResult = match (b.result) {
    ELit(k, _) => Str.equals(k, "unit")
    _ => False
  }
  val isNeverResult = match (b.result) {
    ENever => True
    _ => False
  }
  // When the result starts with '(', the last stmt before it may need a ';'
  // guard so it isn't fused with the '(' on a subsequent format pass.
  val resultNextParen =
    if (isNeverResult | isUnitResult) False
    else exprStartsWithParen(b.result)
  val stmtDocs = buildGuardedStmtDocs(b.stmts, resultNextParen)
  val items =
    if (isNeverResult) stmtDocs
    else if (isUnitResult & !Lst.isEmpty(b.stmts)) stmtDocs
    else Lst.append(stmtDocs, [fmtExpr(b.result)])
  match (items) {
    [] => PP.text("{}")
    _ =>
      PP.hcat([
        PP.text("{"),
        PP.nest(fmtIndent, PP.hcat(Lst.map(items, (d: Doc) => PP.concat(PP.lineBreak, d)))),
        PP.lineBreak,
        PP.text("}")
      ])
  }
}

// ─── Declaration Doc ─────────────────────────────────────────────────────────

fun fmtImportSpec(s: Ast.ImportSpec): Doc =
  if (Str.equals(s.external, s.local))
    PP.text(s.external)
  else
    PP.text("${s.external} as ${s.local}")

fun fmtImportDecl(d: Ast.ImportDecl): Doc =
  match (d) {
    IDSideEffect(spec) => PP.text("import \"${spec}\"")
    IDNamespace(spec, alias) => PP.text("import * as ${alias} from \"${spec}\"")
    IDNamed(spec, specs) =>
      PP.group(PP.hcat([
        PP.text("import { "),
        PP.nest(fmtIndent, PP.hcat(PP.punctuate(PP.text(", "), Lst.map(specs, fmtImportSpec)))),
        PP.text(" } from \"${spec}\"")
      ]))
  }

fun fmtFunSignature(
  exported: Bool,
  async_: Bool,
  name: String,
  typeParams: List<String>,
  params: List<Ast.Param>,
  retType: Ast.AstType
): Doc = {
  val exportPart = if (exported) PP.text("export ") else PP.empty
  val asyncPart = if (async_) PP.text("async ") else PP.empty
  PP.hcat([
    exportPart, asyncPart, PP.text("fun "), PP.text(name),
    fmtTypeParams(typeParams), fmtParamList(params),
    PP.text(": "), fmtType(retType), PP.text(" =")
  ])
}

fun fmtFunBody(sig: Doc, body: Ast.Expr): Doc =
  match (body) {
    EBlock(b) => PP.hcat([sig, PP.text(" "), fmtBlock(b)])
    _ => PP.hcat([sig, PP.nest(fmtIndent, PP.concat(PP.lineBreak, fmtExpr(body)))])
  }

fun fmtFunDecl(d: Ast.FunDecl): Doc =
  fmtFunBody(
    fmtFunSignature(d.exported, d.async_, d.name, d.typeParams, d.params, d.retType),
    d.body
  )

fun fmtCtorDef(c: Ast.CtorDef): Doc =
  match (c.params) {
    [] => PP.text(c.name)
    ps => PP.hcat([
      PP.text(c.name),
      PP.text("("),
      PP.hcat(PP.punctuate(PP.text(", "), Lst.map(ps, fmtType))),
      PP.text(")")
    ])
  }

fun fmtTypeBody(body: Ast.TypeBody): Doc =
  match (body) {
    TBAlias(t) => fmtType(t)
    TBAdt(ctors) =>
      if (Lst.length(ctors) == 1)
        match (Lst.head(ctors)) {
          None => PP.empty
          Some(c) => fmtCtorDef(c)
        }
      else
        match (ctors) {
          [] => PP.empty
          first :: rest =>
            PP.hcat([
              PP.hcat([PP.text("  "), fmtCtorDef(first)]),
              PP.hcat(Lst.map(rest, (c: Ast.CtorDef) =>
                PP.hcat([PP.lineBreak, PP.text("| "), fmtCtorDef(c)])
              ))
            ])
        }
  }

fun fmtTypeDecl(d: Ast.TypeDecl): Doc = {
  val visPrefix =
    if (Str.equals(d.visibility, "export")) PP.text("export ")
    else if (Str.equals(d.visibility, "opaque")) PP.text("opaque ")
    else PP.empty
  val header = PP.hcat([visPrefix, PP.text("type "), PP.text(d.name), fmtTypeParams(d.typeParams), PP.text(" =")])
  match (d.body) {
    TBAdt(ctors) =>
      if (Lst.length(ctors) == 1)
        match (Lst.head(ctors)) {
          None => PP.hcat([header, PP.nest(fmtIndent, PP.concat(PP.lineBreak, fmtTypeBody(d.body)))])
          Some(c) => PP.hcat([header, PP.text(" "), fmtCtorDef(c)])
        }
      else PP.hcat([header, PP.nest(fmtIndent, PP.concat(PP.lineBreak, fmtTypeBody(d.body)))])
    _ =>
      PP.hcat([header, PP.nest(fmtIndent, PP.concat(PP.lineBreak, fmtTypeBody(d.body)))])
  }
}

fun fmtExceptionDecl(d: Ast.ExceptionDecl): Doc = {
  val exportPart = if (d.exported) PP.text("export ") else PP.empty
  val header = PP.hcat([exportPart, PP.text("exception "), PP.text(d.name)])
  match (d.fields) {
    None => header
    Some(fs) =>
      PP.hcat([
        header,
        PP.text(" "),
        PP.group(PP.encloseSep(PP.text("{ "), PP.text(" }"), PP.text(", "), Lst.map(fs, fmtTypeField)))
      ])
  }
}

fun fmtExternFunDecl(d: Ast.ExternFunDecl): Doc = {
  val exportPart = if (d.exported) PP.text("export ") else PP.empty
  val sig = PP.hcat([
    exportPart, PP.text("extern fun "), PP.text(d.name),
    fmtTypeParams(d.typeParams), fmtParamList(d.params),
    PP.text(": "), fmtType(d.retType), PP.text(" =")
  ])
  PP.hcat([sig, PP.nest(fmtIndent, PP.concat(PP.lineBreak, PP.text("jvm(\"${d.jvmDesc}\")")))])
}

fun fmtExternTypeDecl(d: Ast.ExternTypeDecl): Doc = {
  val visPart =
    if (Str.equals(d.visibility, "export")) PP.text("export ")
    else if (Str.equals(d.visibility, "opaque")) PP.text("opaque ")
    else PP.empty
  val sig = PP.hcat([visPart, PP.text("extern type "), PP.text(d.name), fmtTypeParams(d.typeParams), PP.text(" =")])
  PP.hcat([sig, PP.nest(fmtIndent, PP.concat(PP.lineBreak, PP.text("jvm(\"${d.jvmClass}\")")))])
}

fun fmtExternOverride(o: Ast.ExternOverride): Doc =
  PP.hcat([PP.text("fun "), PP.text(o.name), fmtParamList(o.params), PP.text(": "), fmtType(o.retType)])

fun fmtExternImportDecl(d: Ast.ExternImportDecl): Doc = {
  val header = PP.text("extern import \"${d.target}\" as ${d.alias} {")
  val overrides = Lst.map(d.overrides, (o: Ast.ExternOverride) =>
    PP.nest(fmtIndent, PP.concat(PP.lineBreak, fmtExternOverride(o)))
  )
  PP.hcat([header, PP.hcat(overrides), PP.lineBreak, PP.text("}")])
}

fun fmtImportSpecList(specs: List<Ast.ImportSpec>): Doc =
  PP.group(PP.hcat([
    PP.text("{ "),
    PP.nest(fmtIndent, PP.hcat(PP.punctuate(PP.text(", "), Lst.map(specs, fmtImportSpec)))),
    PP.text(" }")
  ]))

fun fmtExportInner(e: Ast.ExportInner): Doc =
  match (e) {
    EIStar(spec) => PP.text("export * from \"${spec}\"")
    EINamed(spec, specs) =>
      PP.hcat([PP.text("export "), fmtImportSpecList(specs), PP.text(" from \"${spec}\"")])
    EIDecl(decl) => fmtTopDecl(decl)
  }

fun fmtTopDecl(d: Ast.TopDecl): Doc =
  match (d) {
    TDFun(fd) => fmtFunDecl(fd)
    TDExternFun(efd) => fmtExternFunDecl(efd)
    TDExternImport(eid) => fmtExternImportDecl(eid)
    TDExternType(etd) => fmtExternTypeDecl(etd)
    TDType(td) => fmtTypeDecl(td)
    TDException(ed) => fmtExceptionDecl(ed)
    TDExport(inner) => fmtExportInner(inner)
    TDVal(name, typeAnn, e) =>
      match (typeAnn) {
        None => PP.hsep([PP.text("export val"), PP.text(name), PP.text("="), fmtExpr(e)])
        Some(t) => PP.hsep([PP.text("export val"), PP.hcat([PP.text(name), PP.text(": "), fmtType(t)]), PP.text("="), fmtExpr(e)])
      }
    TDVar(name, typeAnn, e) =>
      match (typeAnn) {
        None => PP.hsep([PP.text("export var"), PP.text(name), PP.text("="), fmtExpr(e)])
        Some(t) => PP.hsep([PP.text("export var"), PP.hcat([PP.text(name), PP.text(": "), fmtType(t)]), PP.text("="), fmtExpr(e)])
      }
    TDSVal(name, e) =>
      PP.hsep([PP.text("val"), PP.text(name), PP.text("="), fmtExpr(e)])
    TDSVar(name, e) =>
      PP.hsep([PP.text("var"), PP.text(name), PP.text("="), fmtExpr(e)])
    TDSAssign(target, rhs) =>
      PP.hsep([fmtExpr(target), PP.text(":="), fmtExpr(rhs)])
    TDSExpr(e) => fmtExpr(e)
  }

// ─── Comment extraction ───────────────────────────────────────────────────────

// ─── Comment re-attachment ─────────────────────────────────────────────────
// After AST-based formatting strips all trivia, this pass re-weaves the
// original comments back into the formatted output.
//
// A comment token in the original source is either:
//   trailing — it is on the same source line as the preceding significant
//               token  →  append to the end of that token's formatted line.
//   leading  — it is on its own line before the next significant token
//               →  insert (with matching indent) before that token's line.
//
// "Significant" = non-trivia AND not a formatter-added semicolon guard.
// The formatter is strictly order-preserving for significant tokens, so
// original sig-token[i] and formatted sig-token[i] are the same thing.

fun isCommentTok_(t: Token.Token): Bool =
  t.kind == TkLineComment | t.kind == TkBlockComment

fun isSigTok_(t: Token.Token): Bool =
  !Token.isTrivia(t) & !(t.kind == TkPunct & (Str.equals(t.text, ";") | Str.equals(t.text, ",")))

// Count leading spaces on a string line.
fun lineIndent_(line: String): Int = {
  val len = Str.length(line)
  var i = 0
  while (i < len & Str.slice(line, i, i + 1) == " ") {
    i := i + 1
  }
  i
}

// Walk original tokens and produce (isTrailing, sigIdx, text) associations.
//   isTrailing=True  → comment trails sig token #sigIdx (same line)
//   isTrailing=False → comment leads sig token #sigIdx (precedes it)
//                      (sigIdx = total-sig-count means end-of-file)
fun extractCommentAssocs_(tokens: List<Token.Token>): List<(Bool, Int, String)> = {
  val result: Array<(Bool, Int, String)> = Arr.new()
  val tokArr = Arr.fromList(tokens)
  val n = Arr.length(tokArr)
  var pending: Array<String> = Arr.new()
  var sigIdx = 0
  var prevSigLine = 0
  var i = 0
  while (i < n) {
    val t = Arr.get(tokArr, i)
    i := i + 1
    if (isCommentTok_(t)) {
      if (prevSigLine > 0 & t.span.line == prevSigLine) {
        Arr.push(result, (True, sigIdx - 1, t.text))
      } else {
        Arr.push(pending, t.text)
      }
    } else if (isSigTok_(t)) {
      val np = Arr.length(pending)
      var j = 0
      while (j < np) {
        Arr.push(result, (False, sigIdx, Arr.get(pending, j)))
        j := j + 1
      }
      pending := Arr.new()
      prevSigLine := t.span.line
      sigIdx := sigIdx + 1
    }
  }
  // Any remaining pending comments come after all sig tokens.
  val nrem = Arr.length(pending)
  var k = 0
  while (k < nrem) {
    Arr.push(result, (False, sigIdx, Arr.get(pending, k)))
    k := k + 1
  }
  Arr.toList(result)
}

// Re-lex the formatted text and record (0-based lineIdx, 1-based col) for
// each significant token.  The i-th entry corresponds to original sig-tok i.
fun buildSigLineArr_(formattedText: String): Array<(Int, Int)> = {
  val result: Array<(Int, Int)> = Arr.new()
  val tokArr = Arr.fromList(Lex.lex(formattedText))
  val n = Arr.length(tokArr)
  var i = 0
  while (i < n) {
    val t = Arr.get(tokArr, i)
    i := i + 1
    if (isSigTok_(t)) {
      Arr.push(result, (t.span.line - 1, t.span.col))
    }
  }
  result
}

// Re-weave original comments into the formatted source text.
fun reattachComments_(origSrc: String, formattedText: String): String = {
  val origToks = Lex.lex(origSrc)
  val assocs = extractCommentAssocs_(origToks)
  if (Lst.isEmpty(assocs)) formattedText
  else {
    val sigLineArr = buildSigLineArr_(formattedText)
    val numSig = Arr.length(sigLineArr)
    // Split into content lines; discard the extra empty string that results
    // from the trailing "\n" at the end of the formatted text.
    val allLines = Str.lines(formattedText)
    val numRealLines =
      if (Str.endsWith("\n", formattedText)) Lst.length(allLines) - 1
      else Lst.length(allLines)
    val linesArr = Arr.fromList(allLines)
    // Build per-line comment maps:
    //   trailingMap: lineIdx → single trailing comment text
    //   leadingMap:  lineIdx → ordered list of leading comment texts
    //   (lineIdx = numRealLines means "after last line")
    var trailingMap: Dict<Int, String> = Dict.emptyIntDict()
    var leadingMap: Dict<Int, List<String>> = Dict.emptyIntDict()
    val assocsArr = Arr.fromList(assocs)
    val na = Arr.length(assocsArr)
    var ai = 0
    while (ai < na) {
      val a = Arr.get(assocsArr, ai)
      ai := ai + 1
      val isTrailing = a.0
      val idx = a.1
      val text = a.2
      if (isTrailing) {
        if (idx < numSig) {
          val lineIdx = Arr.get(sigLineArr, idx).0
          if (!Dict.member(trailingMap, lineIdx)) {
            trailingMap := Dict.insert(trailingMap, lineIdx, text)
          }
        }
      } else {
        val lineIdx =
          if (idx < numSig) Arr.get(sigLineArr, idx).0
          else numRealLines
        val existing = match (Dict.get(leadingMap, lineIdx)) {
          None => []
          Some(ls) => ls
        }
        leadingMap := Dict.insert(leadingMap, lineIdx, Lst.append(existing, [text]))
      }
    }
    // Reconstruct output line by line.
    val out: Array<String> = Arr.new()
    var i = 0
    while (i < numRealLines) {
      val line = Arr.get(linesArr, i)
      val indent = Str.repeat(lineIndent_(line), " ")
      // Insert leading comments before this line (with matching indentation).
      match (Dict.get(leadingMap, i)) {
        None => ()
        Some(cmts) => {
          val cmtsArr = Arr.fromList(cmts)
          val nc = Arr.length(cmtsArr)
          var ci = 0
          while (ci < nc) {
            Arr.push(out, "${indent}${Arr.get(cmtsArr, ci)}\n")
            ci := ci + 1
          }
        }
      }
      // Emit this line, appending any trailing comment.
      val lineOut = match (Dict.get(trailingMap, i)) {
        None => line
        Some(cmt) => "${line}  ${cmt}"
      }
      Arr.push(out, "${lineOut}\n")
      i := i + 1
    }
    // Post-last-line leading comments (e.g. trailing comment block at EOF).
    match (Dict.get(leadingMap, numRealLines)) {
      None => ()
      Some(cmts) => {
        val cmtsArr = Arr.fromList(cmts)
        val nc = Arr.length(cmtsArr)
        var ci = 0
        while (ci < nc) {
          Arr.push(out, "${Arr.get(cmtsArr, ci)}\n")
          ci := ci + 1
        }
      }
    }
    Str.concat(Arr.toList(out))
  }
}

// ─── Program formatter ───────────────────────────────────────────────────────

fun fmtProgramDoc(prog: Ast.Program): Doc = {
  val importDocs = Lst.map(prog.imports, fmtImportDecl)
  val bodyDocs = Lst.map(prog.body, fmtTopDecl)
  val importSection = PP.hcat(PP.punctuate(PP.lineBreak, importDocs))
  val bodySection = PP.hcat(PP.punctuate(PP.concat(PP.lineBreak, PP.lineBreak), bodyDocs))
  if (Lst.isEmpty(importDocs) & Lst.isEmpty(bodyDocs)) PP.empty
  else if (Lst.isEmpty(importDocs)) bodySection
  else if (Lst.isEmpty(bodyDocs)) importSection
  else PP.hcat([importSection, PP.lineBreak, PP.lineBreak, bodySection])
}

// ─── Public API ──────────────────────────────────────────────────────────────

export fun format(src: String): Result<String, FormatError> = {
  val ls = Lex.create(src)
  match (parse(ls)) {
    Err(e) => match (e) {
      ParseError(msg, off, ln, col) => Err(FmtParseError(msg, off, ln, col))
    }
    Ok(prog) => {
      val doc = fmtProgramDoc(prog)
      val rendered = PP.pretty(fmtWidth, doc)
      if (Str.endsWith("\n", rendered))
        Ok(reattachComments_(src, rendered))
      else
        Ok(reattachComments_(src, "${rendered}\n"))
    }
  }
}

export async fun formatFile(path: String): Task<Result<Unit, FormatError>> = {
  val readResult = await readText(path)
  match (readResult) {
    Err(fsErr) => Err(FmtIoError("${fsErr}"))
    Ok(src) =>
      match (format(src)) {
        Err(e) => Err(e)
        Ok(formatted) =>
          match (await writeText(path, formatted)) {
            Err(fsErr) => Err(FmtIoError("${fsErr}"))
            Ok(_) => Ok(())
          }
      }
  }
}

export async fun checkFile(path: String): Task<Result<Bool, FormatError>> = {
  val readResult = await readText(path)
  match (readResult) {
    Err(fsErr) => Err(FmtIoError("${fsErr}"))
    Ok(src) =>
      match (format(src)) {
        Err(e) => Err(e)
        Ok(formatted) => Ok(Str.equals(src, formatted))
      }
  }
}
