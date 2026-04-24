//! Recursive-descent parser for Kestrel tokens.
//!
//! Parses token streams from [`kestrel:dev/parser/lexer`](/docs/kestrel:dev/parser/lexer)
//! into AST values from [`kestrel:dev/parser/ast`](/docs/kestrel:dev/parser/ast).
//! Entry points: `parse`, `parseExpr`, and `parseFromList`.

import * as Str from "kestrel:data/string"
import * as Lst from "kestrel:data/list"
import * as Arr from "kestrel:data/array"
import * as Token from "kestrel:dev/parser/token"
import {
  TkInt, TkFloat, TkStr, TkChar, TkTemplate, TkIdent, TkUpper, TkKw, TkOp, TkPunct, TkEof,
  TPLiteral, TPInterp
} from "kestrel:dev/parser/token"
import * as Lex from "kestrel:dev/parser/lexer"
import * as Ast from "kestrel:dev/parser/ast"
import {
  ELit, EIdent, ECall, EField, EAwait, EUnary, EBinary, ECons, EPipe,
  EIf, EWhile, ELambda, ETemplate, EList, ERecord, ETuple,
  EMatch, EBlock, EThrow, ETry, EIs, ENever,
  TmplLit, TmplExpr, LElem, LSpread,
  SVal, SVar, SAssign, SExpr, SFun, SBreak, SContinue,
  TDFun, TDSVal, TDSVar, TDSExpr, TDSAssign, TDType, TDException, TDExport, TDVal, TDVar,
  TDExternFun, TDExternImport, TDExternType,
  IDNamed, IDNamespace, IDSideEffect, EIStar, EINamed, EIDecl,
  ATPrim, ATIdent, ATApp, ATArrow, ATRecord, ATTuple, ATUnion, ATInter, ATRowVar, ATQualified,
  PWild, PVar, PLit, PCon, PList, PCons, PTuple,
  TBAdt, TBAlias,
  Case_, Block, Param, TypeField, CtorDef, ConField, RecField, ListElem, TmplPart,
  FunDecl, ExceptionDecl, ImportSpec, Program, ExternOverride
} from "kestrel:dev/parser/ast"

export exception ParseError { message: String, offset: Int, line: Int, col: Int }

val PRIMS = ["Int", "Float", "Bool", "String", "Unit", "Char", "Rune"]

type ParseState = { lex: Lex.LexState, buf: Array<Token.Token>, pos: mut Int }

fun makePs(ls: Lex.LexState): ParseState = {
  { lex = ls, buf = Arr.new(), mut pos = 0 }
}

// Build ParseState from a pre-lexed token list — iterative filter, no recursion.
fun makePsFromList(tokenList: List<Token.Token>): ParseState = {
  val dummy = Lex.create("")
  val buf: Array<Token.Token> = Arr.new()
  // Iterate the linked list directly — avoids allocating a temporary Array.
  var lst = tokenList
  var running = True
  while (running) {
    match (lst) {
      [] => { running := False; () }
      tok :: rest => {
        if (!Token.isTrivia(tok)) Arr.push(buf, tok) else ();
        lst := rest;
        ()
      }
    }
  };
  { lex = dummy, buf = buf, mut pos = 0 }
}

// ─── Lazy token buffer ──────────────────────────────────────────────────────
// Ensures ps.buf has at least ps.pos+ahead+1 elements by pulling non-trivia
// tokens from ps.lex on demand. TkEof is sticky: once EOF lands in buf it is
// duplicated rather than re-lexing (nextToken is idempotent at EOF anyway).

fun fillBuf(ps: ParseState, ahead: Int): Unit = {
  while (Arr.length(ps.buf) <= ps.pos + ahead) {
    val n = Arr.length(ps.buf);
    if (n > 0 & Arr.get(ps.buf, n - 1).kind == TkEof) {
      Arr.push(ps.buf, Arr.get(ps.buf, n - 1))
    } else {
      var tok = Lex.nextToken(ps.lex);
      while (Token.isTrivia(tok)) { tok := Lex.nextToken(ps.lex) };
      Arr.push(ps.buf, tok)
    }
  }
}

// ─── Token accessors ────────────────────────────────────────────────────────

fun cur(ps: ParseState): Token.Token = {
  fillBuf(ps, 0);
  Arr.get(ps.buf, ps.pos)
}

fun pk1(ps: ParseState): Token.Token = {
  fillBuf(ps, 1);
  val nxt = ps.pos + 1
  val len = Arr.length(ps.buf)
  Arr.get(ps.buf, if (nxt < len) nxt else len - 1)
}

fun pk2(ps: ParseState): Token.Token = {
  fillBuf(ps, 2);
  val nxt = ps.pos + 2
  val len = Arr.length(ps.buf)
  Arr.get(ps.buf, if (nxt < len) nxt else len - 1)
}

fun adv(ps: ParseState): Token.Token = {
  val t = cur(ps)
  ps.pos := ps.pos + 1
  t
}

// ─── Token predicates ────────────────────────────────────────────────────────

fun atKw(ps: ParseState, kw: String): Bool =
  cur(ps).kind == TkKw & cur(ps).text == kw

fun atOp(ps: ParseState, op: String): Bool =
  cur(ps).kind == TkOp & cur(ps).text == op

fun atPunct(ps: ParseState, ch: String): Bool =
  cur(ps).kind == TkPunct & cur(ps).text == ch

fun atEof(ps: ParseState): Bool = cur(ps).kind == TkEof

fun atIdent(ps: ParseState): Bool = cur(ps).kind == TkIdent

fun atUpper(ps: ParseState): Bool = cur(ps).kind == TkUpper

fun tokIsKw(t: Token.Token, kw: String): Bool =
  t.kind == TkKw & t.text == kw

fun tokIsOp(t: Token.Token, op: String): Bool =
  t.kind == TkOp & t.text == op

fun tokIsPunct(t: Token.Token, ch: String): Bool =
  t.kind == TkPunct & t.text == ch

// ─── Error helpers ───────────────────────────────────────────────────────────

fun mkErr(ps: ParseState, msg: String): ParseError = {
  val t = cur(ps)
  ParseError(msg, t.span.start, t.span.line, t.span.col)
}

fun expectKw(ps: ParseState, kw: String): Token.Token =
  if (atKw(ps, kw)) adv(ps)
  else throw mkErr(ps, "Expected keyword '${kw}'")

fun expectIdent(ps: ParseState): Token.Token =
  if (atIdent(ps)) adv(ps)
  else throw mkErr(ps, "Expected identifier, got '${cur(ps).text}'")

fun expectUpper(ps: ParseState): Token.Token =
  if (atUpper(ps)) adv(ps)
  else throw mkErr(ps, "Expected uppercase identifier, got '${cur(ps).text}'")

fun expectOp(ps: ParseState, op: String): Token.Token =
  if (atOp(ps, op)) adv(ps)
  else throw mkErr(ps, "Expected operator '${op}', got '${cur(ps).text}'")

fun expectPunct(ps: ParseState, ch: String): Token.Token =
  if (atPunct(ps, ch)) adv(ps)
  else throw mkErr(ps, "Expected '${ch}', got '${cur(ps).text}'")

fun stripQuotes(s: String): String =
  Str.dropRight(Str.dropLeft(s, 1), 1)

fun expectStrVal(ps: ParseState): String =
  if (cur(ps).kind == TkStr) stripQuotes(adv(ps).text)
  else throw mkErr(ps, "Expected string literal")

// ─── Type parsing ────────────────────────────────────────────────────────────

fun parseTypeH(ps: ParseState): Ast.AstType = parseUnionType(ps)

fun parseUnionType(ps: ParseState): Ast.AstType = {
  var left = parseAndType(ps)
  while (atOp(ps, "|")) {
    adv(ps);
    val right = parseAndType(ps)
    left := ATUnion(left, right)
  }
  left
}

fun parseAndType(ps: ParseState): Ast.AstType = {
  var left = parseArrowType(ps)
  while (atOp(ps, "&")) {
    adv(ps);
    val right = parseArrowType(ps)
    left := ATInter(left, right)
  }
  left
}

fun arrowParams(t: Ast.AstType): List<Ast.AstType> =
  match (t) {
    ATTuple(typeElems) => typeElems,
    _ => [t]
  }

fun parseArrowType(ps: ParseState): Ast.AstType = {
  val left = parseAppType(ps)
  if (atOp(ps, "->")) {
    adv(ps);
    val retType = parseTypeH(ps)
    ATArrow(arrowParams(left), retType)
  } else left
}

fun identName(t: Ast.AstType): Option<String> =
  match (t) {
    ATIdent(n) => Some(n),
    _ => None
  }

fun parseAppType(ps: ParseState): Ast.AstType = {
  val base = parseAtomType(ps)
  if (atOp(ps, "*")) {
    val elemArr = Arr.new()
    Arr.push(elemArr, base);
    while (atOp(ps, "*")) {
      adv(ps);
      Arr.push(elemArr, parseAtomType(ps))
    };
    ATTuple(Arr.toList(elemArr))
  } else {
    val nmOpt = identName(base)
    match (nmOpt) {
      Some(nm) =>
        if (atOp(ps, "<")) {
          adv(ps);
          val argArr = Arr.new()
          Arr.push(argArr, parseTypeH(ps));
          while (atPunct(ps, ",")) {
            adv(ps);
            Arr.push(argArr, parseTypeH(ps))
          };
          expectOp(ps, ">");
          ATApp(nm, Arr.toList(argArr))
        } else base,
      None => base
    }
  }
}

fun parseAtomType(ps: ParseState): Ast.AstType = {
  if (atPunct(ps, "(")) {
    adv(ps);
    val first = parseTypeH(ps)
    if (atPunct(ps, ",")) {
      val elems = Arr.new()
      Arr.push(elems, first);
      while (atPunct(ps, ",")) {
        adv(ps);
        Arr.push(elems, parseTypeH(ps))
      };
      expectPunct(ps, ")");
      if (atOp(ps, "->")) {
        adv(ps);
        ATArrow(Arr.toList(elems), parseTypeH(ps))
      } else ATTuple(Arr.toList(elems))
    } else {
      expectPunct(ps, ")");
      first
    }
  } else if (atPunct(ps, "{")) {
    adv(ps);
    if (atOp(ps, "...")) {
      adv(ps);
      val name = expectIdent(ps).text
      expectPunct(ps, "}");
      ATRowVar(name)
    } else {
      val fields = parseTypeFieldList(ps)
      expectPunct(ps, "}");
      ATRecord(fields)
    }
  } else if (atUpper(ps)) {
    val name = adv(ps).text
    if (Lst.member(PRIMS, name)) {
      if (atOp(ps, "<")) {
        adv(ps);
        val argArr = Arr.new()
        Arr.push(argArr, parseTypeH(ps));
        while (atPunct(ps, ",")) {
          adv(ps);
          Arr.push(argArr, parseTypeH(ps))
        };
        expectOp(ps, ">");
        ATApp(name, Arr.toList(argArr))
      } else ATPrim(name)
    } else {
      if (atOp(ps, "<")) {
        adv(ps);
        val argArr = Arr.new()
        Arr.push(argArr, parseTypeH(ps));
        while (atPunct(ps, ",")) {
          adv(ps);
          Arr.push(argArr, parseTypeH(ps))
        };
        expectOp(ps, ">");
        ATApp(name, Arr.toList(argArr))
      } else if (atPunct(ps, ".")) {
        adv(ps);
        val name2 = if (atUpper(ps)) adv(ps).text else expectIdent(ps).text
        ATQualified(name, name2)
      } else ATIdent(name)
    }
  } else if (atIdent(ps)) {
    val name = adv(ps).text
    ATIdent(name)
  } else {
    throw mkErr(ps, "Expected type, got '${cur(ps).text}'")
  }
}

fun parseTypeFieldList(ps: ParseState): List<TypeField> = {
  val arr = Arr.new()
  while (!atPunct(ps, "}") & !atEof(ps)) {
    var isMut = if (atKw(ps, "mut")) { adv(ps); True } else False
    val name = if (atIdent(ps)) adv(ps).text else expectUpper(ps).text
    expectPunct(ps, ":");
    if (atKw(ps, "mut")) { adv(ps); isMut := True } else ()
    val typ = parseTypeH(ps)
    Arr.push(arr, { name=name, mut_=isMut, type_=typ });
    if (atPunct(ps, ",")) { adv(ps); () }
  }
  Arr.toList(arr)
}

// ─── Parameter list ──────────────────────────────────────────────────────────

fun parseOneParam(ps: ParseState): Param = {
  val name = expectIdent(ps).text
  val typ = if (atPunct(ps, ":")) { adv(ps); Some(parseTypeH(ps)) } else None
  { name=name, type_=typ }
}

fun parseParamList(ps: ParseState): List<Param> = {
  val arr = Arr.new()
  while (!atPunct(ps, ")") & !atEof(ps)) {
    Arr.push(arr, parseOneParam(ps));
    if (atPunct(ps, ",")) { adv(ps); () }
  }
  Arr.toList(arr)
}

fun parseTypeParamList(ps: ParseState): List<String> = {
  val arr = Arr.new()
  if (atOp(ps, "<")) {
    adv(ps);
    Arr.push(arr, adv(ps).text);
    while (atPunct(ps, ",")) {
      adv(ps);
      Arr.push(arr, adv(ps).text)
    };
    expectOp(ps, ">");
    ()
  };
  Arr.toList(arr)
}

// ─── Lambda speculation ──────────────────────────────────────────────────────

// Detects whether the token stream from the current `(` closes with `)` followed by `=>`.
// This avoids exception-based backtracking, which can trigger JVM verifier issues.
fun looksLikeGenericLambda(ps: ParseState): Bool = {
  if (!atOp(ps, "<")) False
  else {
    val probe = { lex = ps.lex, buf = ps.buf, mut pos = ps.pos }
    adv(probe);
    if (!atIdent(probe) & !atUpper(probe)) False
    else {
      adv(probe);
      while (atPunct(probe, ",") & !atEof(probe)) {
        adv(probe);
        if (atIdent(probe) | atUpper(probe)) { adv(probe); () } else ()
      };
      if (!atOp(probe, ">")) False
      else {
        adv(probe);
        if (!atPunct(probe, "(")) False
        else {
          var depth = 0
          var found = False
          var done = False
          while (!done & !atEof(probe)) {
            if (atPunct(probe, "(")) {
              depth := depth + 1;
              adv(probe);
              ()
            } else if (atPunct(probe, ")")) {
              depth := depth - 1;
              adv(probe);
              if (depth == 0) {
                found := atOp(probe, "=>");
                done := True
              } else ()
            } else {
              adv(probe);
              ()
            }
          };
          found
        }
      }
    }
  }
}

fun looksLikeLambdaHead(ps: ParseState): Bool = {
  if (!atPunct(ps, "(")) False
  else {
    val probe = { lex = ps.lex, buf = ps.buf, mut pos = ps.pos }
    var depth = 0
    var found = False
    var done = False
    while (!done & !atEof(probe)) {
      if (atPunct(probe, "(")) {
        depth := depth + 1;
        adv(probe);
        ()
      } else if (atPunct(probe, ")")) {
        depth := depth - 1;
        adv(probe);
        if (depth == 0) {
          found := atOp(probe, "=>");
          done := True
        } else ()
      } else {
        adv(probe);
        ()
      }
    };
    found
  }
}

fun parseGenericLambda_(ps: ParseState, async_: Bool): Ast.Expr = {
  adv(ps); // <
  val tpArr = Arr.new()
  Arr.push(tpArr, adv(ps).text);
  while (atPunct(ps, ",")) {
    adv(ps);
    Arr.push(tpArr, adv(ps).text)
  };
  expectOp(ps, ">");
  expectPunct(ps, "(");
  val params = parseParamList(ps)
  expectPunct(ps, ")");
  expectOp(ps, "=>");
  val body = parseExprH(ps)
  ELambda(async_, Arr.toList(tpArr), params, body)
}

fun tryLambda(ps: ParseState, async_: Bool): Option<Ast.Expr> = {
  if (looksLikeGenericLambda(ps)) Some(parseGenericLambda_(ps, async_))
  else if (!looksLikeLambdaHead(ps)) None
  else {
    expectPunct(ps, "(");
    val params = parseParamList(ps)
    expectPunct(ps, ")");
    expectOp(ps, "=>");
    val body = parseExprH(ps)
    Some(ELambda(async_, [], params, body))
  }
}

// ─── Pattern parsing ─────────────────────────────────────────────────────────

fun parsePattern(ps: ParseState): Ast.Pattern = {
  var left = parsePatternPrimary(ps)
  if (atOp(ps, "::")) {
    adv(ps);
    val right = parsePattern(ps)
    PCons(left, right)
  } else left
}

fun parsePatternPrimary(ps: ParseState): Ast.Pattern = {
  if (atIdent(ps) & cur(ps).text == "_") {
    adv(ps);
    PWild
  } else if (atPunct(ps, "(")) {
    adv(ps);
    if (atPunct(ps, ")")) {
      adv(ps);
      PLit("unit","()")
    } else {
      val first = parsePattern(ps)
      if (atPunct(ps, ",")) {
        val elems = Arr.new()
        Arr.push(elems, first);
        while (atPunct(ps, ",")) {
          adv(ps);
          Arr.push(elems, parsePattern(ps))
        };
        expectPunct(ps, ")");
        PTuple(Arr.toList(elems))
      } else {
        expectPunct(ps, ")");
        first
      }
    }
  } else if (atPunct(ps, "[")) {
    adv(ps);
    val elems = Arr.new()
    var rest: Option<String> = None
    while (!atPunct(ps, "]") & !atEof(ps)) {
      if (atOp(ps, "...")) {
        adv(ps);
        rest := Some(expectIdent(ps).text)
      } else {
        Arr.push(elems, parsePattern(ps))
      };
      if (atPunct(ps, ",")) { adv(ps); () }
    };
    expectPunct(ps, "]");
    PList(Arr.toList(elems), rest)
  } else if (cur(ps).kind == TkInt) {
    val t = adv(ps)
    PLit("int", t.text)
  } else if (cur(ps).kind == TkFloat) {
    val t = adv(ps)
    PLit("float", t.text)
  } else if (cur(ps).kind == TkStr) {
    val t = adv(ps)
    PLit("string", stripQuotes(t.text))
  } else if (cur(ps).kind == TkChar) {
    val t = adv(ps)
    PLit("char", stripQuotes(t.text))
  } else if (atUpper(ps)) {
    val name = adv(ps).text
    if (atPunct(ps, "(")) {
      adv(ps);
      val fields = Arr.new()
      var idx = 0
      while (!atPunct(ps, ")") & !atEof(ps)) {
        val p = parsePattern(ps)
        Arr.push(fields, { name = "__field_${idx}", pattern = Some(p) });
        idx := idx + 1;
        if (atPunct(ps, ",")) { adv(ps); () }
      };
      expectPunct(ps, ")");
      PCon(name, Arr.toList(fields))
    } else {
      PCon(name, [])
    }
  } else if (atIdent(ps)) {
    val name = adv(ps).text
    PVar(name)
  } else {
    throw mkErr(ps, "Expected pattern")
  }
}

fun parseCase_(ps: ParseState): Case_ = {
  val p = parsePattern(ps)
  expectOp(ps, "=>");
  val e = parseExprH(ps)
  { pattern=p, body=e }
}

// ─── Block parsing ───────────────────────────────────────────────────────────

fun extractResult(stmtList: List<Ast.Stmt>): Block = {
  val rev = Lst.reverse(stmtList)
  match (Lst.head(rev)) {
    Some(SExpr(e)) => { stmts=Lst.reverse(Lst.tail(rev)), result=e },
    Some(SBreak) => { stmts=stmtList, result=ENever },
    Some(SContinue) => { stmts=stmtList, result=ENever },
    _ => { stmts=stmtList, result=ELit("unit","()") }
  }
}

fun parseBlockH(ps: ParseState): Block = {
  expectPunct(ps, "{");
  val stmts = Arr.new()
  while (!atPunct(ps, "}") & !atEof(ps)) {
    parseAndAddStmt(ps, stmts);
    // consume optional semicolons
    while (atPunct(ps, ";")) { adv(ps); () }
  };
  expectPunct(ps, "}");
  extractResult(Arr.toList(stmts))
}

fun parseLocalAsyncFun_(ps: ParseState, stmts: Array<Ast.Stmt>): Unit = {
  adv(ps); // async
  adv(ps); // fun
  val name = if (atIdent(ps)) adv(ps).text else expectUpper(ps).text
  val typeParams = parseTypeParamList(ps)
  expectPunct(ps, "(");
  val params = parseParamList(ps)
  expectPunct(ps, ")");
  expectPunct(ps, ":");
  val retType = parseTypeH(ps)
  expectOp(ps, "=");
  val body = parseExprH(ps)
  Arr.push(stmts, SFun(True, name, typeParams, params, retType, body));
  ()
}

fun parseValStmt(ps: ParseState, stmts: Array<Ast.Stmt>): Unit = {
  adv(ps);
  val name = if (atIdent(ps)) adv(ps).text else expectUpper(ps).text
  var typ: Option<Ast.AstType> = None
  if (atPunct(ps, ":")) {
    adv(ps);
    typ := Some(parseTypeH(ps));
    ()
  } else ()
  expectOp(ps, "=");
  var expr = parseExprH(ps)
  Arr.push(stmts, SVal(name, typ, expr));
  ()
}

fun parseVarStmt(ps: ParseState, stmts: Array<Ast.Stmt>): Unit = {
  adv(ps);
  val name = if (atIdent(ps)) adv(ps).text else expectUpper(ps).text
  var typ: Option<Ast.AstType> = None
  if (atPunct(ps, ":")) {
    adv(ps);
    typ := Some(parseTypeH(ps));
    ()
  } else ()
  expectOp(ps, "=");
  var expr = parseExprH(ps)
  Arr.push(stmts, SVar(name, typ, expr));
  ()
}

fun parseLocalFunStmt(ps: ParseState, stmts: Array<Ast.Stmt>): Unit = {
  adv(ps);
  val name = expectIdent(ps).text
  val typeParams = parseTypeParamList(ps)
  expectPunct(ps, "(");
  val params = parseParamList(ps)
  expectPunct(ps, ")");
  expectPunct(ps, ":");
  val retType = parseTypeH(ps)
  expectOp(ps, "=");
  val body = parseExprH(ps)
  Arr.push(stmts, SFun(False, name, typeParams, params, retType, body));
  ()
}

fun parseExprOrAssignStmt(ps: ParseState, stmts: Array<Ast.Stmt>): Unit = {
  var expr = parseExprH(ps)
  if (atOp(ps, ":=")) {
    adv(ps);
    val rhs = parseExprH(ps)
    Arr.push(stmts, SAssign(expr, rhs));
    ()
  } else {
    Arr.push(stmts, SExpr(expr));
    ()
  }
}

fun parseAndAddStmt(ps: ParseState, stmts: Array<Ast.Stmt>): Unit = {
  if (atKw(ps, "val")) {
    parseValStmt(ps, stmts)
  } else if (atKw(ps, "var")) {
    parseVarStmt(ps, stmts)
  } else if (atKw(ps, "fun")) {
    parseLocalFunStmt(ps, stmts)
  } else if (atKw(ps, "async") & tokIsKw(pk1(ps), "fun")) {
    parseLocalAsyncFun_(ps, stmts)
  } else if (atKw(ps, "break")) {
    adv(ps);
    Arr.push(stmts, SBreak);
    ()
  } else if (atKw(ps, "continue")) {
    adv(ps);
    Arr.push(stmts, SContinue);
    ()
  } else {
    parseExprOrAssignStmt(ps, stmts)
  }
}

// ─── Expression parsing ──────────────────────────────────────────────────────

fun parseExprH(ps: ParseState): Ast.Expr = parsePipeExpr(ps)

fun parsePipeExpr(ps: ParseState): Ast.Expr = {
  var left = parseConsExpr(ps)
  while (atOp(ps, "|>") | atOp(ps, "<|")) {
    val op = adv(ps).text
    val right = parseConsExpr(ps)
    left := EPipe(op, left, right)
  }
  left
}

fun parseConsExpr(ps: ParseState): Ast.Expr = {
  var left = parseOrExpr(ps)
  if (atOp(ps, "::")) {
    adv(ps);
    val right = parseConsExpr(ps)
    ECons(left, right)
  } else left
}

fun parseOrExpr(ps: ParseState): Ast.Expr = {
  var left = parseAndExpr(ps)
  while (atOp(ps, "|")) {
    adv(ps);
    val right = parseAndExpr(ps)
    left := EBinary("|", left, right)
  }
  left
}

fun parseAndExpr(ps: ParseState): Ast.Expr = {
  var left = parseIsExpr(ps)
  while (atOp(ps, "&")) {
    adv(ps);
    val right = parseIsExpr(ps)
    left := EBinary("&", left, right)
  }
  left
}

fun parseIsExpr(ps: ParseState): Ast.Expr = {
  var left = parseRelExpr(ps)
  if (atKw(ps, "is")) {
    adv(ps);
    val typ = parseTypeH(ps)
    EIs(left, typ)
  } else left
}

fun parseRelExpr(ps: ParseState): Ast.Expr = {
  var left = parseAddExpr(ps)
  while (atOp(ps, "==") | atOp(ps, "!=") | atOp(ps, "<") | atOp(ps, "<=") | atOp(ps, ">") | atOp(ps, ">=")) {
    val op = adv(ps).text
    val right = parseAddExpr(ps)
    left := EBinary(op, left, right)
  }
  left
}

fun parseAddExpr(ps: ParseState): Ast.Expr = {
  var left = parseMulExpr(ps)
  while (atOp(ps, "+") | atOp(ps, "-") | atOp(ps, "++")) {
    val op = adv(ps).text
    val right = parseMulExpr(ps)
    left := EBinary(op, left, right)
  }
  left
}

fun parseMulExpr(ps: ParseState): Ast.Expr = {
  var left = parsePowExpr(ps)
  while (atOp(ps, "*") | atOp(ps, "/") | atOp(ps, "%")) {
    val op = adv(ps).text
    val right = parsePowExpr(ps)
    left := EBinary(op, left, right)
  }
  left
}

fun parsePowExpr(ps: ParseState): Ast.Expr = {
  var left = parseUnaryExpr(ps)
  if (atOp(ps, "**")) {
    adv(ps);
    val right = parsePowExpr(ps)
    EBinary("**", left, right)
  } else left
}

fun parseUnaryExpr(ps: ParseState): Ast.Expr = {
  if (atOp(ps, "-") | atOp(ps, "!") | atOp(ps, "+")) {
    val op = adv(ps).text
    val operand = parseUnaryExpr(ps)
    EUnary(op, operand)
  } else parsePrimaryExpr(ps)
}

fun tmplInterpResult(res: Result<Ast.Expr, ParseError>, fallback: String): TmplPart =
  match (res) {
    Ok(expr) => TmplExpr(expr),
    Err(_) => TmplLit(fallback)
  }

fun parseTmplPart(tp: Token.TemplatePart): TmplPart =
  match (tp) {
    TPLiteral(s) => TmplLit(s),
    TPInterp(s) => tmplInterpResult(parseExpr(Lex.create(s)), s)
  }

fun exprOkAsCallee(expr: Ast.Expr): Bool =
  match (expr) {
    EIdent(_) => True,
    EField(_, _) => True,
    ECall(_, _) => True,
    _ => False
  }

fun parsePrimaryExpr(ps: ParseState): Ast.Expr = {
  var expr = parseAtomExpr(ps)
  var go = True
  while (go) {
    if (atPunct(ps, ".")) {
      adv(ps);
      val field = adv(ps).text
      expr := EField(expr, field)
    } else if (cur(ps).kind == TkFloat & Str.slice(cur(ps).text, 0, 1) == ".") {
      // Tuple index access: a.0, a.1 etc. are lexed as TkFloat ".0", ".1"
      val dotText = cur(ps).text
      val field = Str.slice(dotText, 1, Str.length(dotText))
      adv(ps);
      expr := EField(expr, field)
    } else if (atPunct(ps, "(") & exprOkAsCallee(expr)) {
      adv(ps);
      val args = Arr.new()
      while (!atPunct(ps, ")") & !atEof(ps)) {
        Arr.push(args, parseExprH(ps));
        if (atPunct(ps, ",")) { adv(ps); () }
      };
      expectPunct(ps, ")");
      expr := ECall(expr, Arr.toList(args))
    } else {
      go := False
    }
  };
  expr
}

fun parseIfExpr(ps: ParseState): Ast.Expr = {
  adv(ps);
  expectPunct(ps, "(");
  val cond = parseExprH(ps)
  expectPunct(ps, ")");
  val thenBranch = parseExprH(ps)
  var elseBranch: Option<Ast.Expr> = None
  if (atKw(ps, "else")) {
    adv(ps);
    elseBranch := Some(parseExprH(ps));
    ()
  } else ()
  EIf(cond, thenBranch, elseBranch)
}

fun parseWhileExpr(ps: ParseState): Ast.Expr = {
  adv(ps);
  expectPunct(ps, "(");
  val cond = parseExprH(ps)
  expectPunct(ps, ")");
  val body = parseBlockH(ps)
  EWhile(cond, body)
}

fun parseCases(ps: ParseState): List<Case_> = {
  expectPunct(ps, "{");
  val cases = Arr.new()
  while (!atPunct(ps, "}") & !atEof(ps)) {
    Arr.push(cases, parseCase_(ps));
    if (atPunct(ps, ",")) { adv(ps); () }
  };
  expectPunct(ps, "}");
  Arr.toList(cases)
}

fun parseMatchExpr(ps: ParseState): Ast.Expr = {
  adv(ps);
  expectPunct(ps, "(");
  val scrutinee = parseExprH(ps)
  expectPunct(ps, ")");
  EMatch(scrutinee, parseCases(ps))
}

fun parseTryExpr(ps: ParseState): Ast.Expr = {
  adv(ps);
  val body = parseBlockH(ps)
  expectKw(ps, "catch");
  if (atPunct(ps, "(")) {
    adv(ps);
    adv(ps); // skip binding variable
    expectPunct(ps, ")");
    ()
  } else ()
  ETry(body, None, parseCases(ps))
}

fun parseParenOrLambdaExpr(ps: ParseState): Ast.Expr = {
  if (tokIsPunct(pk1(ps), ")")) {
    adv(ps);
    adv(ps);
    ELit("unit", "()")
  } else {
    match (tryLambda(ps, False)) {
      Some(lam) => lam,
      None => {
        adv(ps);
        val first = parseExprH(ps)
        if (atPunct(ps, ",")) {
          val elems = Arr.new()
          Arr.push(elems, first);
          while (atPunct(ps, ",")) {
            adv(ps);
            Arr.push(elems, parseExprH(ps))
          };
          expectPunct(ps, ")");
          ETuple(Arr.toList(elems))
        } else {
          expectPunct(ps, ")");
          first
        }
      }
    }
  }
}

fun parseListExpr(ps: ParseState): Ast.Expr = {
  adv(ps);
  val elems = Arr.new()
  while (!atPunct(ps, "]") & !atEof(ps)) {
    if (atOp(ps, "...")) {
      adv(ps);
      Arr.push(elems, LSpread(parseExprH(ps)))
    } else {
      Arr.push(elems, LElem(parseExprH(ps)))
    };
    if (atPunct(ps, ",")) { adv(ps); () }
  };
  expectPunct(ps, "]");
  EList(Arr.toList(elems))
}

fun parseAtomExpr0(ps: ParseState): Ast.Expr = {
  if (atKw(ps, "if")) parseIfExpr(ps)
  else if (atKw(ps, "while")) parseWhileExpr(ps)
  else if (atKw(ps, "match")) parseMatchExpr(ps)
  else if (atKw(ps, "await")) {
    adv(ps);
    EAwait(parseUnaryExpr(ps))
  } else if (atKw(ps, "throw")) {
    adv(ps);
    EThrow(parseUnaryExpr(ps))
  } else if (atKw(ps, "try")) parseTryExpr(ps)
  else if (atKw(ps, "async")) {
    adv(ps);
    match (tryLambda(ps, True)) {
      Some(lam) => lam,
      None => throw mkErr(ps, "Expected async lambda")
    }
  } else parseAtomExpr1(ps)
}

fun parseAtomExpr1(ps: ParseState): Ast.Expr = {
  if (cur(ps).kind == TkInt) {
    val t = adv(ps)
    ELit("int", t.text)
  } else if (cur(ps).kind == TkFloat) {
    val t = adv(ps)
    ELit("float", t.text)
  } else if (cur(ps).kind == TkStr) {
    val t = adv(ps)
    ELit("string", stripQuotes(t.text))
  } else if (cur(ps).kind == TkChar) {
    val t = adv(ps)
    ELit("char", stripQuotes(t.text))
  } else if (match (cur(ps).kind) { TkTemplate(_) => True, _ => False }) {
    val t = adv(ps)
    val parts = match (t.kind) {
      TkTemplate(tps) => Lst.map(tps, parseTmplPart),
      _ => []
    }
    ETemplate(parts)
  } else if (atUpper(ps) & cur(ps).text == "True") {
    adv(ps);
    ELit("true", "True")
  } else if (atUpper(ps) & cur(ps).text == "False") {
    adv(ps);
    ELit("false", "False")
  } else parseAtomExpr2(ps)
}

fun parseAtomExpr2(ps: ParseState): Ast.Expr = {
  if (atPunct(ps, "(")) {
    parseParenOrLambdaExpr(ps)
  } else if (atPunct(ps, "[")) {
    parseListExpr(ps)
  } else if (atPunct(ps, "{")) {
    parseRecordOrBlock(ps)
  } else if (atUpper(ps)) {
    val name = adv(ps).text
    EIdent(name)
  } else if (atIdent(ps)) {
    val name = adv(ps).text
    EIdent(name)
  } else {
    throw mkErr(ps, "Expected expression")
  }
}

fun parseAtomExpr(ps: ParseState): Ast.Expr = parseAtomExpr0(ps)

fun parseRecordOrBlock(ps: ParseState): Ast.Expr = {
  // Disambiguate { } as record vs block:
  // - {} is empty record
  // - {name = ...} is record
  // - {mut name = ...} is record
  // - {...spread, ...} is record
  // - otherwise it's a block
  val saved = ps.pos
  adv(ps); // consume {
  if (atPunct(ps, "}")) {
    adv(ps);
    ERecord(None, [])
  } else if (atOp(ps, "...")) {
    ps.pos := saved;
    parseRecord(ps)
  } else if (atKw(ps, "mut")) {
    ps.pos := saved;
    parseRecord(ps)
  } else if (atIdent(ps) & tokIsOp(pk1(ps), "=")) {
    ps.pos := saved;
    parseRecord(ps)
  } else {
    // It's a block expression
    ps.pos := saved;
    val blk = parseBlockH(ps)
    EBlock(blk)
  }
}

fun parseRecord(ps: ParseState): Ast.Expr = {
  expectPunct(ps, "{");
  var spread: Option<Ast.Expr> = None
  val fields = Arr.new()
  if (atOp(ps, "...")) {
    adv(ps);
    spread := Some(parsePrimaryExpr(ps));
    if (atPunct(ps, ",")) { adv(ps); () }
  };
  while (!atPunct(ps, "}") & !atEof(ps)) {
    var isMut = if (atKw(ps, "mut")) { adv(ps); True } else False
    val name = expectIdent(ps).text
    expectOp(ps, "=");
    val value = parseExprH(ps)
    Arr.push(fields, { name=name, mut_=isMut, value=value });
    if (atPunct(ps, ",")) { adv(ps); () }
  };
  expectPunct(ps, "}");
  ERecord(spread, Arr.toList(fields))
}

// ─── Import parsing ──────────────────────────────────────────────────────────

fun parseOneImportSpec(ps: ParseState): ImportSpec = {
  val external = adv(ps).text
  val local = if (atKw(ps, "as")) { adv(ps); adv(ps).text } else external
  { external=external, local=local }
}

fun parseImport_(ps: ParseState): Ast.ImportDecl = {
  expectKw(ps, "import");
  if (atPunct(ps, "{")) {
    adv(ps);
    val specs = Arr.new()
    while (!atPunct(ps, "}") & !atEof(ps)) {
      Arr.push(specs, parseOneImportSpec(ps));
      if (atPunct(ps, ",")) { adv(ps); () }
    };
    expectPunct(ps, "}");
    expectKw(ps, "from");
    val spec = expectStrVal(ps)
    IDNamed(spec, Arr.toList(specs))
  } else if (atOp(ps, "*")) {
    adv(ps);
    expectKw(ps, "as");
    val alias = adv(ps).text
    expectKw(ps, "from");
    val spec = expectStrVal(ps)
    IDNamespace(spec, alias)
  } else {
    val spec = expectStrVal(ps)
    IDSideEffect(spec)
  }
}

// ─── Export / Top-level declaration parsing ───────────────────────────────────

fun parseExport_(ps: ParseState): Ast.TopDecl = {
  expectKw(ps, "export");
  if (atOp(ps, "*")) {
    adv(ps);
    expectKw(ps, "from");
    val spec = expectStrVal(ps)
    TDExport(EIStar(spec))
  } else if (atPunct(ps, "{")) {
    adv(ps);
    val specs = Arr.new()
    while (!atPunct(ps, "}") & !atEof(ps)) {
      Arr.push(specs, parseOneImportSpec(ps));
      if (atPunct(ps, ",")) { adv(ps); () }
    };
    expectPunct(ps, "}");
    expectKw(ps, "from");
    val spec = expectStrVal(ps)
    TDExport(EINamed(spec, Arr.toList(specs)))
  } else {
    parseTopDecl_(ps, True)
  }
}

fun parseOneExternOverride_(ps: ParseState): ExternOverride = {
  adv(ps); // consume 'fun'
  val oname = expectIdent(ps).text
  expectPunct(ps, "(");
  val oparams = parseParamList(ps)
  expectPunct(ps, ")");
  expectPunct(ps, ":");
  val oret = parseTypeH(ps)
  { name=oname, params=oparams, retType=oret }
}

fun parseExternOverrides_(ps: ParseState, overrides: Array<ExternOverride>): Unit = {
  while (!atPunct(ps, "}") & !atEof(ps)) {
    while (atPunct(ps, ";")) { adv(ps); () };
    if (atKw(ps, "fun")) {
      Arr.push(overrides, parseOneExternOverride_(ps));
      ()
    } else if (!atPunct(ps, "}")) {
      adv(ps); // skip unexpected token
      ()
    }
  }
}

fun parseExternImport_(ps: ParseState): Ast.TopDecl = {
  adv(ps); // consume 'import'
  val target = expectStrVal(ps)
  expectKw(ps, "as");
  val alias = if (atIdent(ps)) adv(ps).text else expectUpper(ps).text
  val overrides = Arr.new()
  if (atPunct(ps, "{")) {
    adv(ps);
    parseExternOverrides_(ps, overrides);
    expectPunct(ps, "}");
    ()
  };
  TDExternImport({ target=target, alias=alias, overrides=Arr.toList(overrides) })
}

fun parseExternFun_(ps: ParseState, exported: Bool): Ast.TopDecl = {
  adv(ps); // consume 'fun'
  val ename = expectIdent(ps).text
  val etypeParams = parseTypeParamList(ps)
  expectPunct(ps, "(");
  val eparams = parseParamList(ps)
  expectPunct(ps, ")");
  expectPunct(ps, ":");
  val eretType = parseTypeH(ps)
  expectOp(ps, "=");
  val _jvmFunId = expectIdent(ps);
  expectPunct(ps, "(");
  val jvmDesc = expectStrVal(ps)
  expectPunct(ps, ")");
  TDExternFun({ exported=exported, name=ename, typeParams=etypeParams, params=eparams, retType=eretType, jvmDesc=jvmDesc })
}

fun parseExternType_(ps: ParseState, exported: Bool): Ast.TopDecl = {
  val isOpaque = if (atKw(ps, "opaque")) { adv(ps); True } else False
  val vis = if (isOpaque) "opaque" else if (exported) "export" else "local"
  expectKw(ps, "type");
  val tname = if (atIdent(ps)) adv(ps).text else expectUpper(ps).text
  val ttypeParams = parseTypeParamList(ps)
  expectOp(ps, "=");
  val _jvmTypeId = expectIdent(ps);
  expectPunct(ps, "(");
  val jvmClass = expectStrVal(ps)
  expectPunct(ps, ")");
  TDExternType({ visibility=vis, name=tname, typeParams=ttypeParams, jvmClass=jvmClass })
}

fun parseExternDecl_(ps: ParseState, exported: Bool): Ast.TopDecl = {
  expectKw(ps, "extern");
  if (atKw(ps, "import")) {
    parseExternImport_(ps)
  } else if (atKw(ps, "fun")) {
    parseExternFun_(ps, exported)
  } else {
    parseExternType_(ps, exported)
  }
}

fun parseTopDecl_(ps: ParseState, exported: Bool): Ast.TopDecl = {
  if (atKw(ps, "fun") | atKw(ps, "async")) {
    parseFunDecl_(ps, exported)
  } else if (atKw(ps, "type") | atKw(ps, "opaque")) {
    parseTypeDecl_(ps, exported)
  } else if (atKw(ps, "extern")) {
    parseExternDecl_(ps, exported)
  } else if (atKw(ps, "exception")) {
    adv(ps);
    val name = expectUpper(ps).text
    val fields = if (atPunct(ps, "{")) {
      adv(ps);
      val fs = parseTypeFieldList(ps)
      expectPunct(ps, "}");
      Some(fs)
    } else None
    TDException({ exported=exported, name=name, fields=fields })
  } else if (atKw(ps, "val")) {
    adv(ps);
    val name = if (atIdent(ps)) adv(ps).text else expectUpper(ps).text
    var typ = if (atPunct(ps, ":")) { adv(ps); Some(parseTypeH(ps)) } else None
    expectOp(ps, "=");
    var expr = parseExprH(ps)
    if (exported) TDVal(name, typ, expr) else TDSVal(name, expr)
  } else if (atKw(ps, "var")) {
    adv(ps);
    val name = if (atIdent(ps)) adv(ps).text else expectUpper(ps).text
    var typ = if (atPunct(ps, ":")) { adv(ps); Some(parseTypeH(ps)) } else None
    expectOp(ps, "=");
    var expr = parseExprH(ps)
    if (exported) TDVar(name, typ, expr) else TDSVar(name, expr)
  } else {
    var expr = parseExprH(ps)
    if (atOp(ps, ":=")) {
      adv(ps);
      val rhs = parseExprH(ps)
      TDSAssign(expr, rhs)
    } else TDSExpr(expr)
  }
}

fun parseFunDecl_(ps: ParseState, exported: Bool): Ast.TopDecl = {
  val isAsync = if (atKw(ps, "async")) { adv(ps); True } else False
  expectKw(ps, "fun");
  val name = expectIdent(ps).text
  val typeParams = parseTypeParamList(ps)
  expectPunct(ps, "(");
  val params = parseParamList(ps)
  expectPunct(ps, ")");
  expectPunct(ps, ":");
  val retType = parseTypeH(ps)
  expectOp(ps, "=");
  val body = parseExprH(ps)
  TDFun({ exported=exported, async_=isAsync, name=name, typeParams=typeParams, params=params, retType=retType, body=body })
}

fun parseTypeDecl_(ps: ParseState, exported: Bool): Ast.TopDecl = {
  val visibility = if (atKw(ps, "opaque")) { adv(ps); "opaque" }
    else if (exported) "export"
    else "local"
  expectKw(ps, "type");
  val name = adv(ps).text
  val typeParams = parseTypeParamList(ps)
  expectOp(ps, "=");
  // ADT: starts with an uppercase identifier or is a sequence of Ctor | Ctor | ...
  if (atUpper(ps) & (tokIsPunct(pk1(ps), "(") | tokIsOp(pk1(ps), "|"))) {
    // ADT body
    val ctors = Arr.new()
    Arr.push(ctors, parseCtor(ps));
    while (atOp(ps, "|")) {
      adv(ps);
      Arr.push(ctors, parseCtor(ps))
    };
    TDType({ visibility=visibility, name=name, typeParams=typeParams, body=TBAdt(Arr.toList(ctors)) })
  } else if (atUpper(ps) & !tokIsOp(pk1(ps), "<") & !tokIsPunct(pk1(ps), ".") & !tokIsOp(pk1(ps), "*") & !tokIsOp(pk1(ps), "|") & !tokIsOp(pk1(ps), "&") & !tokIsOp(pk1(ps), "->") & !tokIsPunct(pk1(ps), "{") & !tokIsPunct(pk1(ps), "(")) {
    // Could be a single nullary constructor (no params, no pipes after)
    // Check if the next token after the name indicates more declarations (pipes)
    // If it's just a single uppercase name followed by newline/eof/another decl, treat as ADT
    // Actually, for `type Color = Red | Green | Blue`, after `=` we see `Red` then `|`
    // For `type Alias = SomeType`, after `=` we see `SomeType` with no `(` or `|`
    // Let's default to alias since simple `type X = Y` is more common for non-pipe cases
    val body = parseTypeH(ps)
    TDType({ visibility=visibility, name=name, typeParams=typeParams, body=TBAlias(body) })
  } else {
    val body = parseTypeH(ps)
    TDType({ visibility=visibility, name=name, typeParams=typeParams, body=TBAlias(body) })
  }
}

fun parseCtor(ps: ParseState): CtorDef = {
  val name = expectUpper(ps).text
  val params = if (atPunct(ps, "(")) {
    adv(ps);
    val arr = Arr.new()
    while (!atPunct(ps, ")") & !atEof(ps)) {
      Arr.push(arr, parseTypeH(ps));
      if (atPunct(ps, ",")) { adv(ps); () }
    };
    expectPunct(ps, ")");
    Arr.toList(arr)
  } else []
  { name=name, params=params }
}

fun parseProgram_(ps: ParseState): Program = {
  val imports = Arr.new()
  val body = Arr.new()
  // Parse imports (they must come first)
  while (atKw(ps, "import")) {
    Arr.push(imports, parseImport_(ps))
  };
  // Parse top-level declarations; skip bare semicolons
  while (!atEof(ps)) {
    if (atPunct(ps, ";")) {
      adv(ps);
      ()
    } else if (atKw(ps, "export")) {
      Arr.push(body, parseExport_(ps))
    } else {
      Arr.push(body, parseTopDecl_(ps, False))
    }
  };
  { imports=Arr.toList(imports), body=Arr.toList(body) }
}

// ─── Entry points ────────────────────────────────────────────────────────────

export fun parse(ls: Lex.LexState): Result<Program, ParseError> =
  try {
    val ps = makePs(ls)
    Ok(parseProgram_(ps))
  } catch {
    e => Err(e)
  }

export fun parseExpr(ls: Lex.LexState): Result<Ast.Expr, ParseError> =
  try {
    val ps = makePs(ls)
    Ok(parseExprH(ps))
  } catch {
    e => Err(e)
  }

export fun parseFromList(tokens: List<Token.Token>): Result<Program, ParseError> =
  try {
    val ps = makePsFromList(tokens)
    Ok(parseProgram_(ps))
  } catch {
    e => Err(e)
  }

export fun parseExprFromList(tokens: List<Token.Token>): Result<Ast.Expr, ParseError> =
  try {
    val ps = makePsFromList(tokens)
    Ok(parseExprH(ps))
  } catch {
    e => Err(e)
  }
