import * as Str from "kestrel:data/string"
import * as Lst from "kestrel:data/list"
import * as Arr from "kestrel:array"
import * as Token from "kestrel:dev/parser/token"
import {
  TkInt, TkFloat, TkStr, TkChar, TkTemplate, TkIdent, TkUpper, TkKw, TkOp, TkPunct, TkEof,
  TPLiteral, TPInterp
} from "kestrel:dev/parser/token"
import { lex } from "kestrel:dev/parser/lexer"
import * as Ast from "kestrel:dev/parser/ast"
import {
  ELit, EIdent, ECall, EField, EAwait, EUnary, EBinary, ECons, EPipe,
  EIf, EWhile, ELambda, ETemplate, EList, ERecord, ETuple,
  EMatch, EBlock, EThrow, ETry, EIs, ENever,
  TmplLit, TmplExpr, LElem, LSpread,
  SVal, SVar, SAssign, SExpr, SFun, SBreak, SContinue,
  TDFun, TDSVal, TDSVar, TDSExpr, TDSAssign, TDType, TDException, TDExport, TDVal, TDVar,
  IDNamed, IDNamespace, IDSideEffect, EIStar, EINamed, EIDecl,
  ATPrim, ATIdent, ATApp, ATArrow, ATRecord, ATTuple, ATUnion, ATInter, ATRowVar, ATQualified,
  PWild, PVar, PLit, PCon, PList, PCons, PTuple,
  TBAdt, TBAlias
} from "kestrel:dev/parser/ast"

export exception ParseError { message: String, offset: Int, line: Int, col: Int }

val PRIMS = ["Int", "Float", "Bool", "String", "Unit", "Char", "Rune"]

type ParseState = { tokens: Array<Token.Token>, pos: mut Int }

fun makePs(tokenList: List<Token.Token>): ParseState = {
  val filtered = Lst.filter(tokenList, (t: Token.Token) => !Token.isTrivia(t))
  { tokens = Arr.fromList(filtered), mut pos = 0 }
}

// ─── Token accessors ────────────────────────────────────────────────────────

fun cur(ps: ParseState): Token.Token = {
  val len = Arr.length(ps.tokens)
  val safeIdx = if (ps.pos < len) ps.pos else len - 1
  Arr.get(ps.tokens, safeIdx)
}

fun pk1(ps: ParseState): Token.Token = {
  val len = Arr.length(ps.tokens)
  val nxt = ps.pos + 1
  val safeIdx = if (nxt < len) nxt else len - 1
  Arr.get(ps.tokens, safeIdx)
}

fun pk2(ps: ParseState): Token.Token = {
  val len = Arr.length(ps.tokens)
  val nxt = ps.pos + 2
  val safeIdx = if (nxt < len) nxt else len - 1
  Arr.get(ps.tokens, safeIdx)
}

fun adv(ps: ParseState): Token.Token = {
  val t = cur(ps)
  val newPos = ps.pos + 1
  val maxPos = Arr.length(ps.tokens) - 1
  val nextPos = if (newPos <= maxPos) newPos else maxPos
  ps.pos := nextPos
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
  ParseError { message=msg, offset=t.span.start, line=t.span.line, col=t.span.col }
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

fun parseTypeFieldList(ps: ParseState): List<Ast.TypeField> = {
  val arr = Arr.new()
  while (!atPunct(ps, "}") & !atEof(ps)) {
    val isMut = if (atKw(ps, "mut")) { adv(ps); True } else False
    val name = if (atIdent(ps)) adv(ps).text else expectUpper(ps).text
    expectPunct(ps, ":");
    val typ = parseTypeH(ps)
    Arr.push(arr, { name=name, mut_=isMut, type_=typ });
    if (atPunct(ps, ",")) { adv(ps); () }
  }
  Arr.toList(arr)
}

// ─── Parameter list ──────────────────────────────────────────────────────────

fun parseOneParam(ps: ParseState): Ast.Param = {
  val name = expectIdent(ps).text
  val typ = if (atPunct(ps, ":")) { adv(ps); Some(parseTypeH(ps)) } else None
  { name=name, type_=typ }
}

fun parseParamList(ps: ParseState): List<Ast.Param> = {
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

// Check if current position looks like a lambda: (params) => body or async (params) => body
// Saves position, tries to parse params and =>, restores on failure.
fun tryLambda(ps: ParseState, async_: Bool): Option<Ast.Expr> = {
  val saved = ps.pos
  var ok = try {
    expectPunct(ps, "(");
    var params = parseParamList(ps)
    expectPunct(ps, ")");
    expectOp(ps, "=>");
    var body = parseExprH(ps)
    Some(ELambda(async_, [], params, body))
  } catch {
    _ => {
      ps.pos := saved
      None
    }
  }
  ok
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
  if (atKw(ps, "_")) {
    adv(ps);
    PWild
  } else if (atPunct(ps, "(")) {
    adv(ps);
    if (atPunct(ps, ")")) {
      adv(ps);
      PLit("unit","()")
    } else {
      var first = parsePattern(ps)
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
    var t = adv(ps)
    PLit("int", t.text)
  } else if (cur(ps).kind == TkFloat) {
    var t = adv(ps)
    PLit("float", t.text)
  } else if (cur(ps).kind == TkStr) {
    var t = adv(ps)
    PLit("string", stripQuotes(t.text))
  } else if (cur(ps).kind == TkChar) {
    var t = adv(ps)
    PLit("char", stripQuotes(t.text))
  } else if (atUpper(ps)) {
    var name = adv(ps).text
    if (atPunct(ps, "(")) {
      adv(ps);
      val fields = Arr.new()
      var idx = 0
      while (!atPunct(ps, ")") & !atEof(ps)) {
        var p = parsePattern(ps)
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

fun parseCase_(ps: ParseState): Ast.Case_ = {
  var pat = parsePattern(ps)
  expectOp(ps, "=>");
  var body = parseExprH(ps)
  { pattern=pat, body=body }
}

// ─── Block parsing ───────────────────────────────────────────────────────────

fun extractResult(stmtList: List<Ast.Stmt>): Ast.Block = {
  var rev = Lst.reverse(stmtList)
  match (Lst.head(rev)) {
    Some(SExpr(e)) => { stmts=Lst.reverse(Lst.tail(rev)), result=e },
    Some(SBreak) => { stmts=stmtList, result=ENever },
    Some(SContinue) => { stmts=stmtList, result=ENever },
    _ => { stmts=stmtList, result=ELit("unit","()") }
  }
}

fun parseBlockH(ps: ParseState): Ast.Block = {
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

fun parseAndAddStmt(ps: ParseState, stmts: Array<Ast.Stmt>): Unit = {
  if (atKw(ps, "val")) {
    adv(ps);
    var name = expectIdent(ps).text
    var typ = if (atPunct(ps, ":")) { adv(ps); Some(parseTypeH(ps)) } else None
    expectOp(ps, "=");
    var expr = parseExprH(ps)
    Arr.push(stmts, SVal(name, typ, expr));
    ()
  } else if (atKw(ps, "var")) {
    adv(ps);
    var name = expectIdent(ps).text
    var typ = if (atPunct(ps, ":")) { adv(ps); Some(parseTypeH(ps)) } else None
    expectOp(ps, "=");
    var expr = parseExprH(ps)
    Arr.push(stmts, SVar(name, typ, expr));
    ()
  } else if (atKw(ps, "fun")) {
    adv(ps);
    var name = expectIdent(ps).text
    var typeParams = parseTypeParamList(ps)
    expectPunct(ps, "(");
    var params = parseParamList(ps)
    expectPunct(ps, ")");
    expectPunct(ps, ":");
    var retType = parseTypeH(ps)
    expectOp(ps, "=");
    var body = parseExprH(ps)
    Arr.push(stmts, SFun(False, name, typeParams, params, retType, body));
    ()
  } else if (atKw(ps, "break")) {
    adv(ps);
    Arr.push(stmts, SBreak);
    ()
  } else if (atKw(ps, "continue")) {
    adv(ps);
    Arr.push(stmts, SContinue);
    ()
  } else {
    var expr = parseExprH(ps)
    if (atOp(ps, ":=")) {
      adv(ps);
      var rhs = parseExprH(ps)
      Arr.push(stmts, SAssign(expr, rhs));
      ()
    } else {
      Arr.push(stmts, SExpr(expr));
      ()
    }
  }
}

// ─── Expression parsing ──────────────────────────────────────────────────────

fun parseExprH(ps: ParseState): Ast.Expr = parsePipeExpr(ps)

fun parsePipeExpr(ps: ParseState): Ast.Expr = {
  var left = parseConsExpr(ps)
  while (atOp(ps, "|>") | atOp(ps, "<|")) {
    var op = adv(ps).text
    var right = parseConsExpr(ps)
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
    var right = parseAndExpr(ps)
    left := EBinary("|", left, right)
  }
  left
}

fun parseAndExpr(ps: ParseState): Ast.Expr = {
  var left = parseIsExpr(ps)
  while (atOp(ps, "&")) {
    adv(ps);
    var right = parseIsExpr(ps)
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
    var op = adv(ps).text
    var right = parseAddExpr(ps)
    left := EBinary(op, left, right)
  }
  left
}

fun parseAddExpr(ps: ParseState): Ast.Expr = {
  var left = parseMulExpr(ps)
  while (atOp(ps, "+") | atOp(ps, "-") | atOp(ps, "++")) {
    var op = adv(ps).text
    var right = parseMulExpr(ps)
    left := EBinary(op, left, right)
  }
  left
}

fun parseMulExpr(ps: ParseState): Ast.Expr = {
  var left = parsePowExpr(ps)
  while (atOp(ps, "*") | atOp(ps, "/") | atOp(ps, "%")) {
    var op = adv(ps).text
    var right = parsePowExpr(ps)
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
  if (atOp(ps, "-") | atOp(ps, "!")) {
    var op = adv(ps).text
    var operand = parseUnaryExpr(ps)
    EUnary(op, operand)
  } else parsePrimaryExpr(ps)
}

fun tmplInterpResult(res: Result<Ast.Expr, ParseError>, fallback: String): Ast.TmplPart =
  match (res) {
    Ok(expr) => TmplExpr(expr),
    Err(_) => TmplLit(fallback)
  }

fun parseTmplPart(tp: Token.TemplatePart): Ast.TmplPart =
  match (tp) {
    TPLiteral(s) => TmplLit(s),
    TPInterp(s) => tmplInterpResult(parseExpr(lex(s)), s)
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
      var field = adv(ps).text
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

fun parseAtomExpr(ps: ParseState): Ast.Expr = {
  if (atKw(ps, "if")) {
    adv(ps);
    expectPunct(ps, "(");
    var cond = parseExprH(ps)
    expectPunct(ps, ")");
    var thenBranch = parseExprH(ps)
    var elseBranch = if (atKw(ps, "else")) { adv(ps); Some(parseExprH(ps)) } else None
    EIf(cond, thenBranch, elseBranch)
  } else if (atKw(ps, "while")) {
    adv(ps);
    expectPunct(ps, "(");
    var cond = parseExprH(ps)
    expectPunct(ps, ")");
    var body = parseBlockH(ps)
    EWhile(cond, body)
  } else if (atKw(ps, "match")) {
    adv(ps);
    expectPunct(ps, "(");
    var scrutinee = parseExprH(ps)
    expectPunct(ps, ")");
    expectPunct(ps, "{");
    val cases = Arr.new()
    while (!atPunct(ps, "}") & !atEof(ps)) {
      Arr.push(cases, parseCase_(ps));
      if (atPunct(ps, ",")) { adv(ps); () }
    };
    expectPunct(ps, "}");
    EMatch(scrutinee, Arr.toList(cases))
  } else if (atKw(ps, "await")) {
    adv(ps);
    var expr = parseUnaryExpr(ps)
    EAwait(expr)
  } else if (atKw(ps, "throw")) {
    adv(ps);
    var expr = parseUnaryExpr(ps)
    EThrow(expr)
  } else if (atKw(ps, "try")) {
    adv(ps);
    var body = parseBlockH(ps)
    expectKw(ps, "catch");
    expectPunct(ps, "{");
    val cases = Arr.new()
    while (!atPunct(ps, "}") & !atEof(ps)) {
      Arr.push(cases, parseCase_(ps));
      if (atPunct(ps, ",")) { adv(ps); () }
    };
    expectPunct(ps, "}");
    ETry(body, None, Arr.toList(cases))
  } else if (atKw(ps, "async")) {
    adv(ps);
    match (tryLambda(ps, True)) {
      Some(lam) => lam,
      None => throw mkErr(ps, "Expected async lambda")
    }
  } else if (cur(ps).kind == TkInt) {
    var t = adv(ps)
    ELit("int", t.text)
  } else if (cur(ps).kind == TkFloat) {
    var t = adv(ps)
    ELit("float", t.text)
  } else if (cur(ps).kind == TkStr) {
    var t = adv(ps)
    ELit("string", stripQuotes(t.text))
  } else if (cur(ps).kind == TkChar) {
    var t = adv(ps)
    ELit("char", stripQuotes(t.text))
  } else if (match (cur(ps).kind) { TkTemplate(_) => True, _ => False }) {
    var t = adv(ps)
    var parts = match (t.kind) {
      TkTemplate(tps) => Lst.map(tps, parseTmplPart),
      _ => []
    }
    ETemplate(parts)
  } else if (atKw(ps, "True")) {
    adv(ps);
    ELit("true", "True")
  } else if (atKw(ps, "False")) {
    adv(ps);
    ELit("false", "False")
  } else if (atPunct(ps, "(")) {
    // Could be: unit (), tuple, lambda, or grouped expression
    if (tokIsPunct(pk1(ps), ")")) {
      adv(ps);
      adv(ps);
      ELit("unit", "()")
    } else {
      // Try lambda first
      match (tryLambda(ps, False)) {
        Some(lam) => lam,
        None => {
          adv(ps);
          var first = parseExprH(ps)
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
  } else if (atPunct(ps, "[")) {
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
    var blk = parseBlockH(ps)
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
    var name = expectIdent(ps).text
    expectOp(ps, "=");
    var value = parseExprH(ps)
    Arr.push(fields, { name=name, mut_=isMut, value=value });
    if (atPunct(ps, ",")) { adv(ps); () }
  };
  expectPunct(ps, "}");
  ERecord(spread, Arr.toList(fields))
}

// ─── Import parsing ──────────────────────────────────────────────────────────

fun parseOneImportSpec(ps: ParseState): Ast.ImportSpec = {
  var external = adv(ps).text
  var local = if (atKw(ps, "as")) { adv(ps); adv(ps).text } else external
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
    var spec = expectStrVal(ps)
    IDNamed(spec, Arr.toList(specs))
  } else if (atOp(ps, "*")) {
    adv(ps);
    expectKw(ps, "as");
    var alias = adv(ps).text
    expectKw(ps, "from");
    var spec = expectStrVal(ps)
    IDNamespace(spec, alias)
  } else {
    var spec = expectStrVal(ps)
    IDSideEffect(spec)
  }
}

// ─── Export / Top-level declaration parsing ───────────────────────────────────

fun parseExport_(ps: ParseState): Ast.TopDecl = {
  expectKw(ps, "export");
  if (atOp(ps, "*")) {
    adv(ps);
    expectKw(ps, "from");
    var spec = expectStrVal(ps)
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
    var spec = expectStrVal(ps)
    TDExport(EINamed(spec, Arr.toList(specs)))
  } else {
    parseTopDecl_(ps, True)
  }
}

fun parseTopDecl_(ps: ParseState, exported: Bool): Ast.TopDecl = {
  if (atKw(ps, "fun") | atKw(ps, "async")) {
    parseFunDecl_(ps, exported)
  } else if (atKw(ps, "type") | atKw(ps, "opaque")) {
    parseTypeDecl_(ps, exported)
  } else if (atKw(ps, "exception")) {
    adv(ps);
    var name = expectUpper(ps).text
    var fields = if (atPunct(ps, "{")) {
      adv(ps);
      var fs = parseTypeFieldList(ps)
      expectPunct(ps, "}");
      Some(fs)
    } else None
    TDException({ exported=exported, name=name, fields=fields })
  } else if (atKw(ps, "val")) {
    adv(ps);
    var name = expectIdent(ps).text
    var typ = if (atPunct(ps, ":")) { adv(ps); Some(parseTypeH(ps)) } else None
    expectOp(ps, "=");
    var expr = parseExprH(ps)
    if (exported) TDVal(name, typ, expr) else TDSVal(name, expr)
  } else if (atKw(ps, "var")) {
    adv(ps);
    var name = expectIdent(ps).text
    var typ = if (atPunct(ps, ":")) { adv(ps); Some(parseTypeH(ps)) } else None
    expectOp(ps, "=");
    var expr = parseExprH(ps)
    if (exported) TDVar(name, typ, expr) else TDSVar(name, expr)
  } else {
    var expr = parseExprH(ps)
    if (atOp(ps, ":=")) {
      adv(ps);
      var rhs = parseExprH(ps)
      TDSAssign(expr, rhs)
    } else TDSExpr(expr)
  }
}

fun parseFunDecl_(ps: ParseState, exported: Bool): Ast.TopDecl = {
  var isAsync = if (atKw(ps, "async")) { adv(ps); True } else False
  expectKw(ps, "fun");
  var name = expectIdent(ps).text
  var typeParams = parseTypeParamList(ps)
  expectPunct(ps, "(");
  var params = parseParamList(ps)
  expectPunct(ps, ")");
  expectPunct(ps, ":");
  var retType = parseTypeH(ps)
  expectOp(ps, "=");
  var body = parseExprH(ps)
  TDFun({ exported=exported, async_=isAsync, name=name, typeParams=typeParams, params=params, retType=retType, body=body })
}

fun parseTypeDecl_(ps: ParseState, exported: Bool): Ast.TopDecl = {
  var visibility = if (atKw(ps, "opaque")) { adv(ps); "opaque" }
    else if (exported) "export"
    else "local"
  expectKw(ps, "type");
  var name = adv(ps).text
  var typeParams = parseTypeParamList(ps)
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

fun parseCtor(ps: ParseState): Ast.CtorDef = {
  var name = expectUpper(ps).text
  var params = if (atPunct(ps, "(")) {
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

fun parseProgram_(ps: ParseState): Ast.Program = {
  val imports = Arr.new()
  val body = Arr.new()
  // Parse imports (they must come first)
  while (atKw(ps, "import")) {
    Arr.push(imports, parseImport_(ps))
  };
  // Parse top-level declarations
  while (!atEof(ps)) {
    if (atKw(ps, "export")) {
      Arr.push(body, parseExport_(ps))
    } else {
      Arr.push(body, parseTopDecl_(ps, False))
    }
  };
  { imports=Arr.toList(imports), body=Arr.toList(body) }
}

// ─── Entry points ────────────────────────────────────────────────────────────

export fun parse(tokenList: List<Token.Token>): Result<Ast.Program, ParseError> =
  try {
    val ps = makePs(tokenList)
    Ok(parseProgram_(ps))
  } catch {
    e => Err(e)
  }

export fun parseExpr(tokenList: List<Token.Token>): Result<Ast.Expr, ParseError> =
  try {
    val ps = makePs(tokenList)
    Ok(parseExprH(ps))
  } catch {
    e => Err(e)
  }
