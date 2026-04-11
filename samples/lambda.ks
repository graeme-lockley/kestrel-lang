// Lambda calculus parser and reducer.
//
// Parses a string in standard notation (\ or λ for lambda, . for body
// separator) into a Term ADT, then reduces to beta-normal form using
// normal-order (leftmost-outermost) reduction with capture-avoiding
// substitution.
import * as Str from "kestrel:data/string"
import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"

// ── Term ADT ─────────────────────────────────────────────────────────────
type Term =
    Var(String)
  | Lam(String, Term)
  | App(Term, Term)

// ── Parse-result ADT ─────────────────────────────────────────────────────
type ParseResult =
    POk(Term, List<String>)
  | PErr(String)

// ── Pretty-printer ────────────────────────────────────────────────────────
fun pretty(t: Term): String =
  match (t) {
    Var(x) =>
      x,
    Lam(x, b) =>
      "(λ${x}.${pretty(b)})",
    App(f, a) =>
      "(${pretty(f)} ${pretty(a)})"
  }

// ── Free-variable set (as list, no duplicates) ────────────────────────────
fun hasMember(xs: List<String>, s: String): Bool =
  match (xs) {
    [] =>
      False,
    h :: t =>
      if (h == s) True else hasMember(t, s)
  }

fun listUnion(xs: List<String>, ys: List<String>): List<String> =
  match (ys) {
    [] =>
      xs,
    h :: t =>
      if (hasMember(xs, h)) listUnion(xs, t) else listUnion(h :: xs, t)
  }

fun listRemove(xs: List<String>, s: String): List<String> =
  match (xs) {
    [] =>
      [],
    h :: t =>
      if (h == s) listRemove(t, s) else h :: listRemove(t, s)
  }

fun freeVars(t: Term): List<String> =
  match (t) {
    Var(x) =>
      [x],
    Lam(x, b) =>
      listRemove(freeVars(b), x),
    App(f, a) =>
      listUnion(freeVars(f), freeVars(a))
  }

// ── Capture-avoiding substitution subst(t, x, s) = t[x := s] ─────────────
fun freshName(name: String, avoid: List<String>): String =
  if (hasMember(avoid, "${name}'")) freshName("${name}'", avoid) else "${name}'"

fun subst(t: Term, x: String, s: Term): Term =
  match (t) {
    Var(y) =>
      if (y == x) s else Var(y),
    App(f, a) =>
      App(subst(f, x, s), subst(a, x, s)),
    Lam(y, b) =>
      if (y == x)
        Lam(y, b)
      else if (hasMember(freeVars(s), y)) {
        val y2 = freshName(y, listUnion(freeVars(s), freeVars(b)))
        Lam(y2, subst(subst(b, y, Var(y2)), x, s))
      }
      else
        Lam(y, subst(b, x, s))
  }

// ── Single-step normal-order (leftmost-outermost) beta reduction ───────────
// Helpers avoid nested match (Kestrel scoping quirk with inner match bindings).
fun stepLam(lv: String, lb: Term): Option<Term> =
  Opt.map(step(lb), (lb2) => Lam(lv, lb2))

fun stepArg(fn: Term, arg: Term): Option<Term> =
  Opt.map(step(arg), (a2) => App(fn, a2))

fun stepNonLam(fn: Term, arg: Term): Option<Term> =
  match (step(fn)) {
    None =>
      stepArg(fn, arg),
    Some(f2) =>
      Some(App(f2, arg))
  }

// Applies function fn to arg, performing beta reduction if fn is a lambda.
fun applyApp(fn: Term, arg: Term): Option<Term> =
  match (fn) {
    Lam(lv, lb) =>
      Some(subst(lb, lv, arg)),
    _ =>
      stepNonLam(fn, arg)
  }

fun step(t: Term): Option<Term> =
  match (t) {
    Var(_) =>
      None,
    Lam(lv, lb) =>
      stepLam(lv, lb),
    App(fn, arg) =>
      applyApp(fn, arg)
  }

// ── Reduction to normal form ──────────────────────────────────────────────
// Inner loop: key is a dummy String to make this a 3-param function and
// avoid the 2-param Int compiler quirk.
fun reduceLoop(key: String, t: Term, limit: Int): Option<Term> =
  if (limit <= 0) None else match (step(t)) {None => Some(t),Some(t2) => reduceLoop(key, t2, limit - 1)}

fun reduce(t: Term, limit: Int): Option<Term> =
  reduceLoop("", t, limit)

// ── Tokeniser ─────────────────────────────────────────────────────────────
// Produces tokens: "VAR:name", "LAM", "DOT", "LPAREN", "RPAREN"
fun cpIsAlpha(cp: Int): Bool =
  cp >= 65 & cp <= 90 | cp >= 97 & cp <= 122

fun cpIsIdentCont(cp: Int): Bool =
  cp >= 65 & cp <= 90 | cp >= 97 & cp <= 122 | cp >= 48 & cp <= 57 | cp == 95 | cp == 39

// Read an identifier starting at position i, return as "VAR:name".
// 3 params avoids the 2-param Int quirk.
fun readIdent(s: String, i: Int, acc: String): String = {
  val len = Str.length(s)
  if (i >= len)
    acc
  else if (cpIsIdentCont(Str.codePointAt(s, i)))
    readIdent(s, i + 1, "${acc}${Str.slice(s, i, i + 1)}")
  else
    acc
}

// Accumulate tokens in reverse, then reverse at the end.
// 3 params avoids the 2-param Int quirk for i.
fun tokenAt(s: String, i: Int, acc: List<String>): List<String> = {
  val len = Str.length(s)
  if (i >= len)
    Lst.reverse(acc)
  else {
    val cp = Str.codePointAt(s, i)
    if (cp == 32 | cp == 9 | cp == 10 | cp == 13)
      tokenAt(s, i + 1, acc)
    else if (cp == 92 | cp == 955)
      tokenAt(s, i + 1, "LAM" :: acc)
    else if (cp == 46)
      tokenAt(s, i + 1, "DOT" :: acc)  // \ or λ
    else if (cp == 40)
      tokenAt(s, i + 1, "LPAREN" :: acc)  // .
    else if (cp == 41)
      tokenAt(s, i + 1, "RPAREN" :: acc)  // (
    else if (cpIsAlpha(cp)) {
      val name = readIdent(s, i, "")  // )
      tokenAt(s, i + Str.length(name), "VAR:${name}" :: acc)
    }
    else
      tokenAt(s, i + 1, acc)
  }
}

fun tokenize(s: String): List<String> =
  tokenAt(s, 0, [])

// ── Parser ────────────────────────────────────────────────────────────────
// Grammar:
//   term = app
//   app  = atom app | atom          (left-associative)
//   atom = VAR | ( term ) | \VAR.term
//
// Note: each level of nested match must be a separate function because
// Kestrel's pattern binding doesn't work inside nested match arm bodies.
fun varName(tok: String): Option<String> =
  if (Str.length(tok) >= 4 & Str.slice(tok, 0, 4) == "VAR:") Some(Str.slice(tok, 4, Str.length(tok))) else None

fun isAtomStart(tokens: List<String>): Bool =
  match (tokens) {
    [] =>
      False,
    h :: _ =>
      h == "LPAREN" | h == "LAM" | Str.length(h) >= 4 & Str.slice(h, 0, 4) == "VAR:"
  }

// parseParenClose: check for RPAREN after a successfully parsed sub-term.
fun parseParenClose(t: Term, rest2: List<String>): ParseResult =
  match (rest2) {
    [] =>
      PErr("missing ')'"),
    tok2 :: rest3 =>
      if (tok2 == "RPAREN") POk(t, rest3) else PErr("expected ')'")
  }

fun parseParenResult(r: ParseResult): ParseResult =
  // parseParenResult: handle the outcome of parsing the inner term of ( term ).
  match (r) {
    PErr(msg) =>
      PErr(msg),
    POk(t, rest2) =>
      parseParenClose(t, rest2)
  }

// parseAtomVar: parse a variable token.
fun parseAtomVar(tok: String, rest: List<String>): ParseResult =
  match (varName(tok)) {
    None =>
      PErr("unexpected token: ${tok}"),
    Some(name) =>
      POk(Var(name), rest)
  }

// parseLamBodyResult: wrap result of parsing a lambda body.
fun parseLamBodyResult(name: String, r: ParseResult): ParseResult =
  match (r) {
    PErr(msg) =>
      PErr(msg),
    POk(body, rest3) =>
      POk(Lam(name, body), rest3)
  }

// parseLamBody: expect "." then term.
fun parseLamBody(name: String, rest: List<String>): ParseResult =
  match (rest) {
    [] =>
      PErr("missing '.' after λ${name}"),
    dot :: rest2 =>
      if (dot != "DOT") PErr("expected '.' after λ${name}") else parseLamBodyResult(name, parseTerm(rest2))
  }

// parseLamVar: match the variable token after λ.
fun parseLamVar(varOpt: Option<String>, rest: List<String>): ParseResult =
  match (varOpt) {
    None =>
      PErr("expected identifier after λ"),
    Some(name) =>
      parseLamBody(name, rest)
  }

// parseLam: parse \VAR.term
fun parseLam(rest: List<String>): ParseResult =
  match (rest) {
    [] =>
      PErr("missing variable after λ"),
    tok :: rest2 =>
      parseLamVar(varName(tok), rest2)
  }

// parseAtom: parse a single atomic term.
fun parseAtom(tokens: List<String>): ParseResult =
  match (tokens) {
    [] =>
      PErr("unexpected end of input"),
    tok :: rest =>
      if (tok == "LPAREN")
        parseParenResult(parseTerm(rest))
      else if (tok == "LAM")
        parseLam(rest)
      else
        parseAtomVar(tok, rest)
  }

fun parseTerm(tokens: List<String>): ParseResult =
  parseApp(tokens)

fun parseApp(tokens: List<String>): ParseResult =
  match (parseAtom(tokens)) {
    PErr(msg) =>
      PErr(msg),
    POk(f, rest) =>
      parseAppCont(f, rest)
  }

fun parseAppCont(f: Term, tokens: List<String>): ParseResult =
  if (isAtomStart(tokens))
    match (parseAtom(tokens)) {
      PErr(msg) =>
        PErr(msg),
      POk(a, rest) =>
        parseAppCont(App(f, a), rest)
    }
  else
    POk(f, tokens)

// parseEnd: verify no trailing tokens remain.
fun parseEnd(t: Term, rest: List<String>): ParseResult =
  match (rest) {
    [] =>
      POk(t, []),
    _ =>
      PErr("trailing input after expression")
  }

fun parseTermResult(r: ParseResult): ParseResult =
  match (r) {
    PErr(msg) =>
      PErr(msg),
    POk(t, rest) =>
      parseEnd(t, rest)
  }

fun parse(input: String): ParseResult =
  parseTermResult(parseTerm(tokenize(input)))

// ── Demo ──────────────────────────────────────────────────────────────────
fun demo(title: String, source: String): Unit = {
  println("")
  println("${title}")
  println("  input:  ${source}")
  match (parse(source)) {
    PErr(msg) =>
      println("  error:  ${msg}"),
    POk(t, _) => {
      println("  parsed: ${pretty(t)}")
      match (reduce(t, 500)) {
        None =>
          println("  nf:     (diverges or exceeds 500 steps)"),
        Some(r) =>
          println("  nf:     ${pretty(r)}")
      }
    }
  }
}

demo("Identity  I = \\x.x", "\\x.x")

demo("Apply I to z", "(\\x.x) z")

// Classic combinators and reductions
demo("K = \\x.\\y.x  applied", "(\\x.\\y.x) a b")

demo("S = \\f.\\g.\\x.f x (g x)", "\\f.\\g.\\x.f x (g x)")

demo("S K K z  reduces to  z", "(\\f.\\g.\\x.f x (g x)) (\\x.\\y.x) (\\x.\\y.x) z")

demo("Church 0 = \\f.\\x.x", "\\f.\\x.x")

demo("Succ applied to Church 0", "(\\n.\\f.\\x.f (n f x)) (\\f.\\x.x)")

demo("Church add applied to 1+1", "((\\m.\\n.\\f.\\x.m f (n f x)) (\\f.\\x.f x)) (\\f.\\x.f x)")

demo("Omega diverges", "(\\x.x x) (\\x.x x)")
