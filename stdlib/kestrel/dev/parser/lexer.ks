import * as Str from "kestrel:data/string"
import * as Lst from "kestrel:data/list"
import * as Arr from "kestrel:data/array"
import * as Dict from "kestrel:data/dict"
import * as Token from "kestrel:dev/parser/token"
import { TPLiteral, TPInterp, TkInt, TkFloat, TkStr, TkTemplate, TkChar,
         TkIdent, TkUpper, TkKw, TkOp, TkPunct, TkWs,
         TkLineComment, TkBlockComment, TkEof } from "kestrel:dev/parser/token"

// Fast O(1) lexer helpers: treat positions as code-unit (char) indices.
// Kestrel source files are ASCII/BMP so code units == code points.
// Declared before the computed module-level vals that call lexLen at init time.
extern fun cpOf(src: String, pos: Int): Int =
  jvm("kestrel.runtime.KRuntime#lexCharAt(java.lang.Object,java.lang.Object)")
extern fun lexLen(src: String): Int =
  jvm("kestrel.runtime.KRuntime#lexLength(java.lang.Object)")
extern fun lexSlice(src: String, start: Int, end: Int): String =
  jvm("kestrel.runtime.KRuntime#lexSlice(java.lang.Object,java.lang.Object,java.lang.Object)")

val KEYWORDS = [
  "exception", "continue", "opaque", "extern", "export", "import",
  "async", "await", "break", "catch", "match", "throw", "while",
  "else", "from", "type", "fun", "mut", "try", "val", "var", "as", "if", "is"
]

// O(1) keyword lookup: HashMap.containsKey instead of 24-deep recursive list scan.
val KEYWORD_SET = Dict.fromList(Dict.hashString, Dict.eqString,
  Lst.map(KEYWORDS, (kw: String) => (kw, True)))

val MULTI_OPS = [
  "=>", ":=", "==", "!=", ">=", "<=", "**", "<|", "::", "|>", "->", "..."
]

// Precomputed arrays so matchMultiOp pays no lexLen(op) cost per invocation.
val MULTI_OPS_ARR = Arr.fromList(MULTI_OPS)
val MULTI_OPS_LENS = Arr.fromList(Lst.map(MULTI_OPS, (op: String) => lexLen(op)))

val SINGLE_OPS = "+-*/%|&<>=!"

val PUNCT_CHARS = "(){}[],:.;"

fun isAlpha(cp: Int): Bool =
  (cp >= 65 & cp <= 90) | (cp >= 97 & cp <= 122)

fun isUpper(cp: Int): Bool =
  cp >= 65 & cp <= 90

fun isDigit(cp: Int): Bool =
  cp >= 48 & cp <= 57

fun isAlNum(cp: Int): Bool =
  isAlpha(cp) | isDigit(cp) | cp == 95

fun isHexDigit(cp: Int): Bool =
  isDigit(cp) | (cp >= 65 & cp <= 70) | (cp >= 97 & cp <= 102)

fun isBinDigit(cp: Int): Bool = cp == 48 | cp == 49

fun isOctDigit(cp: Int): Bool = cp >= 48 & cp <= 55

fun isWs(cp: Int): Bool =
  cp == 32 | cp == 9 | cp == 13 | cp == 10

// Code-point predicates — integer comparisons, no substring or string search.
// SINGLE_OPS = "+-*/%|&<>=!"
fun isSingleOp(cp: Int): Bool =
  cp == 43 | cp == 45 | cp == 42 | cp == 37 | cp == 47 |
  cp == 124 | cp == 38 | cp == 60 | cp == 62 | cp == 61 | cp == 33

// PUNCT_CHARS = "(){}[],:.;"
fun isPunct(cp: Int): Bool =
  cp == 40 | cp == 41 | cp == 123 | cp == 125 | cp == 91 | cp == 93 |
  cp == 44 | cp == 58 | cp == 46 | cp == 59

// First chars of MULTI_OPS: = : ! > < * | - .
fun canBeMultiOp(cp: Int): Bool =
  cp == 61 | cp == 58 | cp == 33 | cp == 62 | cp == 60 |
  cp == 42 | cp == 124 | cp == 45 | cp == 46

fun chrAt(src: String, pos: Int): String =
  if (pos >= lexLen(src)) "" else lexSlice(src, pos, pos + 1)

fun makeSpan(start: Int, end: Int, line: Int, col: Int): Token.Span =
  { start = start, end = end, line = line, col = col }

fun makeTok(kind: Token.TokenKind, text: String, span: Token.Span): Token.Token =
  { kind = kind, text = text, span = span }

fun lexWsEnd(src: String, pos: Int): Int = {
  var p = pos
  val len = lexLen(src)
  while (p < len & isWs(cpOf(src, p))) {
    p := p + 1
  }
  p
}

fun lexLineEnd(src: String, pos: Int): Int = {
  var p = pos
  val len = lexLen(src)
  while (p < len & cpOf(src, p) != 10) {
    p := p + 1
  }
  p
}

fun lexBlockEnd(src: String, pos: Int): Int = {
  var p = pos
  val len = lexLen(src)
  var found = False
  while (p < len & !found) {
    val cp = cpOf(src, p)
    if (cp == 42 & p + 1 < len & cpOf(src, p + 1) == 47) {
      p := p + 2
      found := True
    } else {
      p := p + 1
    }
  }
  p
}

fun lexIdentEnd(src: String, pos: Int): Int = {
  var p = pos
  val len = lexLen(src)
  while (p < len & isAlNum(cpOf(src, p))) {
    p := p + 1
  }
  p
}

fun lexHexEnd(src: String, pos: Int): Int = {
  var p = pos
  val len = lexLen(src)
  var go = True
  while (p < len & go) {
    val cp = cpOf(src, p)
    if (isHexDigit(cp) | cp == 95) {
      p := p + 1
    } else {
      go := False
    }
  }
  p
}

fun lexBinEnd(src: String, pos: Int): Int = {
  var p = pos
  val len = lexLen(src)
  var go = True
  while (p < len & go) {
    val cp = cpOf(src, p)
    if (isBinDigit(cp) | cp == 95) {
      p := p + 1
    } else {
      go := False
    }
  }
  p
}

fun lexOctEnd(src: String, pos: Int): Int = {
  var p = pos
  val len = lexLen(src)
  var go = True
  while (p < len & go) {
    val cp = cpOf(src, p)
    if (isOctDigit(cp) | cp == 95) {
      p := p + 1
    } else {
      go := False
    }
  }
  p
}

fun lexDecEnd(src: String, pos: Int): Int = {
  var p = pos
  val len = lexLen(src)
  var go = True
  while (p < len & go) {
    val cp = cpOf(src, p)
    if (isDigit(cp) | cp == 95) {
      p := p + 1
    } else {
      go := False
    }
  }
  p
}

fun lexExpEnd(src: String, pos: Int): Int = {
  val len = lexLen(src)
  if (pos >= len) pos
  else {
    val cp = cpOf(src, pos)
    if (cp == 69 | cp == 101) {
      var p = pos + 1
      val hasSign = p < len & (cpOf(src, p) == 43 | cpOf(src, p) == 45)
      val p2 = if (hasSign) p + 1 else p
      if (p2 < len & isDigit(cpOf(src, p2))) {
        var ep = p2
        val elen = lexLen(src)
        while (ep < elen & isDigit(cpOf(src, ep))) {
          ep := ep + 1
        }
        ep
      } else pos
    } else pos
  }
}

fun lexEscEnd(src: String, pos: Int): Int = {
  val len = lexLen(src)
  if (pos >= len) -1
  else {
    val esc = cpOf(src, pos)
    if (esc == 110 | esc == 114 | esc == 116 | esc == 34 | esc == 92 | esc == 39) {
      pos + 1
    } else if (esc == 117 & pos + 1 < len & cpOf(src, pos + 1) == 123) {
      var p = pos + 2
      val hlen = lexLen(src)
      while (p < hlen & isHexDigit(cpOf(src, p))) {
        p := p + 1
      }
      if (p < hlen & cpOf(src, p) == 125) p + 1 else -1
    } else -1
  }
}

type StringResult = SROk(Int, Token.TokenKind) | SRError

fun lexStringFrom(src: String, pos: Int): StringResult = {
  val len = lexLen(src)
  val parts: Array<Token.TemplatePart> = Arr.new()
  var p = pos
  var litStart = pos
  var running = True
  var success = False

  while (p < len & running) {
    val cp = cpOf(src, p)
    if (cp == 34) {
      val litText = lexSlice(src, litStart, p)
      if (lexLen(litText) > 0) {
        Arr.push(parts, TPLiteral(litText))
      }
      p := p + 1
      running := False
      success := True
    } else if (cp == 92) {
      val escEnd = lexEscEnd(src, p + 1)
      if (escEnd < 0) {
        running := False
      } else {
        p := escEnd
      }
    } else if (cp == 36) {
      val litText = lexSlice(src, litStart, p)
      if (lexLen(litText) > 0) {
        Arr.push(parts, TPLiteral(litText))
      }
      p := p + 1
      if (p < len & cpOf(src, p) == 123) {
        p := p + 1
        val interpStart = p
        var depth = 1
        var interpRunning = True
        while (p < len & interpRunning) {
          val ic = cpOf(src, p)
          if (ic == 123) {
            depth := depth + 1
            p := p + 1
          } else if (ic == 125) {
            depth := depth - 1
            if (depth == 0) {
              interpRunning := False
            } else {
              p := p + 1
            }
          } else {
            p := p + 1
          }
        }
        if (depth != 0) {
          running := False
        } else {
          val interpSrc = lexSlice(src, interpStart, p)
          Arr.push(parts, TPInterp(interpSrc))
          p := p + 1
          litStart := p
        }
      } else if (p < len & (isAlpha(cpOf(src, p)) | cpOf(src, p) == 95)) {
        val identEnd = lexIdentEnd(src, p)
        val identSrc = lexSlice(src, p, identEnd)
        Arr.push(parts, TPInterp(identSrc))
        p := identEnd
        litStart := p
      } else {
        litStart := p - 1
      }
    } else if (cp == 10) {
      running := False
    } else {
      p := p + 1
    }
  }

  if (!success) {
    SRError
  } else {
    val nParts = Arr.length(parts)
    if (nParts == 0) {
      SROk(p, TkStr)
    } else if (nParts == 1) {
      match (Arr.get(parts, 0)) {
        TPLiteral(_) => SROk(p, TkStr),
        TPInterp(s) => SROk(p, TkTemplate([TPInterp(s)]))
      }
    } else {
      SROk(p, TkTemplate(Arr.toList(parts)))
    }
  }
}

fun matchMultiOp(src: String, pos: Int): String = {
  val len = lexLen(src)
  val n = Arr.length(MULTI_OPS_ARR)
  var i = 0
  var result = ""
  var done = False
  while (i < n & !done) {
    val opLen = Arr.get(MULTI_OPS_LENS, i)
    val op = Arr.get(MULTI_OPS_ARR, i)
    if (pos + opLen <= len & lexSlice(src, pos, pos + opLen) == op) {
      result := op
      done := True
    } else {
      i := i + 1
    }
  }
  result
}

fun advanceLc(src: String, start: Int, end: Int, line0: Int, col0: Int): (Int, Int) = {
  var l = line0
  var c = col0
  var i = start
  while (i < end) {
    val cp = cpOf(src, i)
    if (cp == 10) {
      l := l + 1
      c := 1
    } else {
      c := c + 1
    }
    i := i + 1
  }
  (l, c)
}

// Returns end position of a decimal-or-float number starting at pos.
// Also pushes the token. Returns (endPos, isFloat) packed as endPos*2 + boolBit.
fun lexNumEnd(src: String, pos: Int): (Int, Bool) = {
  val len = lexLen(src)
  val afterDigs = lexDecEnd(src, pos)
  val hasDot = afterDigs < len & cpOf(src, afterDigs) == 46
  var afterDot2 = afterDigs
  var go = hasDot
  while (go) {
    val ad = afterDigs + 1
    afterDot2 := lexDecEnd(src, ad)
    go := False
    ()
  }
  val afterExp = lexExpEnd(src, afterDot2);
  val isFloat = hasDot | (afterExp > afterDot2);
  (afterExp, isFloat)
}

fun makeWsTok(src: String, pos: Int, line: Int, col: Int): (Token.Token, Int, Int, Int) = {
  val endPos = lexWsEnd(src, pos)
  val text = lexSlice(src, pos, endPos)
  val span = makeSpan(pos, endPos, line, col)
  val lc = advanceLc(src, pos, endPos, line, col);
  (makeTok(TkWs, text, span), endPos, lc.0, lc.1)
}

fun makeLineCmtTok(src: String, pos: Int, line: Int, col: Int): (Token.Token, Int, Int, Int) = {
  val endPos = lexLineEnd(src, pos + 2)
  val text = lexSlice(src, pos, endPos)
  val span = makeSpan(pos, endPos, line, col);
  (makeTok(TkLineComment, text, span), endPos, line, col + (endPos - pos))
}

fun makeBlockCmtTok(src: String, pos: Int, line: Int, col: Int): (Token.Token, Int, Int, Int) = {
  val endPos = lexBlockEnd(src, pos + 2)
  val text = lexSlice(src, pos, endPos)
  val span = makeSpan(pos, endPos, line, col)
  val lc = advanceLc(src, pos, endPos, line, col);
  (makeTok(TkBlockComment, text, span), endPos, lc.0, lc.1)
}

fun makeIdentTok(src: String, pos: Int, line: Int, col: Int): (Token.Token, Int, Int, Int) = {
  val endPos = lexIdentEnd(src, pos)
  val text = lexSlice(src, pos, endPos)
  val span = makeSpan(pos, endPos, line, col)
  val kind =
    if (Dict.member(KEYWORD_SET, text)) TkKw
    else if (isUpper(cpOf(text, 0))) TkUpper
    else TkIdent;
  (makeTok(kind, text, span), endPos, line, col + (endPos - pos))
}

fun makeDotFloatTok(src: String, pos: Int, line: Int, col: Int): (Token.Token, Int, Int, Int) = {
  val afterDot = lexDecEnd(src, pos + 1)
  val endPos = lexExpEnd(src, afterDot)
  val text = lexSlice(src, pos, endPos)
  val span = makeSpan(pos, endPos, line, col);
  (makeTok(TkFloat, text, span), endPos, line, col + (endPos - pos))
}

fun makeZeroNumTok(src: String, pos: Int, line: Int, col: Int): (Token.Token, Int, Int, Int) = {
  val len = lexLen(src)
  val nextCp = if (pos + 1 < len) cpOf(src, pos + 1) else -1
  if (nextCp == 120 | nextCp == 88) {
    val endPos = lexHexEnd(src, pos + 2)
    val text = lexSlice(src, pos, endPos)
    val span = makeSpan(pos, endPos, line, col);
    (makeTok(TkInt, text, span), endPos, line, col + (endPos - pos))
  } else if (nextCp == 98 | nextCp == 66) {
    val endPos = lexBinEnd(src, pos + 2)
    val text = lexSlice(src, pos, endPos)
    val span = makeSpan(pos, endPos, line, col);
    (makeTok(TkInt, text, span), endPos, line, col + (endPos - pos))
  } else if (nextCp == 111 | nextCp == 79) {
    val endPos = lexOctEnd(src, pos + 2)
    val text = lexSlice(src, pos, endPos)
    val span = makeSpan(pos, endPos, line, col);
    (makeTok(TkInt, text, span), endPos, line, col + (endPos - pos))
  } else {
    val r = lexNumEnd(src, pos)
    val endPos = r.0
    val text = lexSlice(src, pos, endPos)
    val span = makeSpan(pos, endPos, line, col)
    val kind = if (r.1) TkFloat else TkInt;
    (makeTok(kind, text, span), endPos, line, col + (endPos - pos))
  }
}

fun makeNumTok(src: String, pos: Int, cp: Int, line: Int, col: Int): (Token.Token, Int, Int, Int) = {
  val len = lexLen(src)
  if (cp == 48 & pos + 1 < len) {
    makeZeroNumTok(src, pos, line, col)
  } else {
    val r = lexNumEnd(src, pos)
    val endPos = r.0
    val text = lexSlice(src, pos, endPos)
    val span = makeSpan(pos, endPos, line, col)
    val kind = if (r.1) TkFloat else TkInt;
    (makeTok(kind, text, span), endPos, line, col + (endPos - pos))
  }
}

fun makeStrTok(src: String, pos: Int, line: Int, col: Int): (Token.Token, Int, Int, Int) = {
  val strResult = lexStringFrom(src, pos + 1)
  match (strResult) {
    SROk(strEnd, strKind) => {
      val text = lexSlice(src, pos, strEnd)
      val span = makeSpan(pos, strEnd, line, col);
      (makeTok(strKind, text, span), strEnd, line, col + (strEnd - pos))
    },
    SRError => {
      val errText = lexSlice(src, pos, pos + 1)
      val span = makeSpan(pos, pos + 1, line, col);
      (makeTok(TkStr, errText, span), pos + 1, line, col + 1)
    }
  }
}

fun charEscEnd(src: String, pos: Int): Int = {
  val len = lexLen(src)
  val escEnd = lexEscEnd(src, pos + 1)
  val afterEsc = if (escEnd < 0) pos + 1 else escEnd
  if (afterEsc < len) {
    if (cpOf(src, afterEsc) == 39) afterEsc + 1 else afterEsc
  } else {
    afterEsc
  }
}

fun charPlainEnd(src: String, pos: Int): Int = {
  val len = lexLen(src)
  val p2 = pos + 1
  if (p2 < len) {
    if (cpOf(src, p2) == 39) p2 + 1 else p2
  } else {
    p2
  }
}

fun charLiteralEndHelper(src: String, len: Int, chrPos: Int): Int =
  if (chrPos >= len) chrPos
  else if (cpOf(src, chrPos) == 92) charEscEnd(src, chrPos)
  else charPlainEnd(src, chrPos)

fun charLiteralEnd(src: String, pos: Int): Int = {
  val len = lexLen(src)
  val chrPos = pos + 1
  if (chrPos >= len) chrPos
  else if (cpOf(src, chrPos) == 92) charEscEnd(src, chrPos)
  else charPlainEnd(src, chrPos)
}

fun makeCharTok(src: String, pos: Int, line: Int, col: Int): (Token.Token, Int, Int, Int) = {
  val endPos = charLiteralEnd(src, pos)
  val text = lexSlice(src, pos, endPos)
  val span = makeSpan(pos, endPos, line, col);
  (makeTok(TkChar, text, span), endPos, line, col + (endPos - pos))
}

fun makeOpOrPunctTok(src: String, pos: Int, line: Int, col: Int): (Token.Token, Int, Int, Int) = {
  val cp = cpOf(src, pos)
  if (canBeMultiOp(cp)) {
    val mop = matchMultiOp(src, pos)
    val mlen = lexLen(mop)
    if (mlen > 0) {
      val endPos = pos + mlen
      val span = makeSpan(pos, endPos, line, col);
      (makeTok(TkOp, mop, span), endPos, line, col + mlen)
    } else {
      val ch = lexSlice(src, pos, pos + 1)
      val span = makeSpan(pos, pos + 1, line, col)
      val kind = if (isSingleOp(cp)) TkOp else TkPunct;
      (makeTok(kind, ch, span), pos + 1, line, col + 1)
    }
  } else if (isSingleOp(cp)) {
    val ch = lexSlice(src, pos, pos + 1)
    val span = makeSpan(pos, pos + 1, line, col);
    (makeTok(TkOp, ch, span), pos + 1, line, col + 1)
  } else if (isPunct(cp)) {
    val ch = lexSlice(src, pos, pos + 1)
    val span = makeSpan(pos, pos + 1, line, col);
    (makeTok(TkPunct, ch, span), pos + 1, line, col + 1)
  } else {
    val ch = lexSlice(src, pos, pos + 1)
    val span = makeSpan(pos, pos + 1, line, col);
    (makeTok(TkPunct, ch, span), pos + 1, line, col + 1)
  }
}

export type LexState = {
  src: String, len: Int, pos: mut Int, line: mut Int, col: mut Int,
  // Inline accumulators for buildDeclInfo — populated by nextToken so callers
  // (e.g. the formatter) can obtain comment/position data in a single pass.
  commentsBuf: Array<(Int, List<String>)>, posBuf: Array<Int>, pending: mut List<String>
}

// Create a LexState positioned at the start of src (skipping any shebang line).
export fun create(src: String): LexState = {
  val ls = {
    src = src, len = lexLen(src), mut pos = 0, mut line = 1, mut col = 1,
    commentsBuf = Arr.new(), posBuf = Arr.new(), mut pending = []
  }
  if (ls.pos + 1 < ls.len & cpOf(ls.src, ls.pos) == 35 & cpOf(ls.src, ls.pos + 1) == 33) {
    while (ls.pos < ls.len & cpOf(ls.src, ls.pos) != 10) { ls.pos := ls.pos + 1 }
    if (ls.pos < ls.len) { ls.pos := ls.pos + 1; () }
  }
  ls
}

// Return the next token from ls, advancing ls.pos/line/col.
// Returns TkEof (idempotently) once the source is exhausted.
// Also accumulates comment and declaration-start data into ls.commentsBuf /
// ls.posBuf / ls.pending so that getDeclInfo() can be called after parsing
// without a second scan of the source.
export fun nextToken(ls: LexState): Token.Token = {
  val tok =
    if (ls.pos >= ls.len)
      makeTok(TkEof, "", makeSpan(ls.len, ls.len, ls.line, ls.col))
    else {
      val cp = cpOf(ls.src, ls.pos)
      val r =
        if (isWs(cp))
          makeWsTok(ls.src, ls.pos, ls.line, ls.col)
        else if (cp == 47 & ls.pos + 1 < ls.len & cpOf(ls.src, ls.pos + 1) == 47)
          makeLineCmtTok(ls.src, ls.pos, ls.line, ls.col)
        else if (cp == 47 & ls.pos + 1 < ls.len & cpOf(ls.src, ls.pos + 1) == 42)
          makeBlockCmtTok(ls.src, ls.pos, ls.line, ls.col)
        else if (isAlpha(cp) | cp == 95)
          makeIdentTok(ls.src, ls.pos, ls.line, ls.col)
        else if (cp == 46 & ls.pos + 1 < ls.len & isDigit(cpOf(ls.src, ls.pos + 1)))
          makeDotFloatTok(ls.src, ls.pos, ls.line, ls.col)
        else if (isDigit(cp))
          makeNumTok(ls.src, ls.pos, cp, ls.line, ls.col)
        else if (cp == 34)
          makeStrTok(ls.src, ls.pos, ls.line, ls.col)
        else if (cp == 39)
          makeCharTok(ls.src, ls.pos, ls.line, ls.col)
        else
          makeOpOrPunctTok(ls.src, ls.pos, ls.line, ls.col)
      ls.pos := r.1
      ls.line := r.2
      ls.col := r.3
      r.0
    }
  val k = tok.kind
  if (k == TkLineComment | k == TkBlockComment) {
    ls.pending := tok.text :: ls.pending;
    ()
  } else if (k == TkWs | k == TkPunct | k == TkOp) {
    ()
  } else {
    if (tok.span.col == 1) {
      if (!Lst.isEmpty(ls.pending)) {
        Arr.push(ls.commentsBuf, (tok.span.start, Lst.reverse(ls.pending)))
      }
      Arr.push(ls.posBuf, tok.span.start)
    }
    ls.pending := [];
    ()
  }
  tok
}

// Return the (commentsBuf, posBuf) accumulated during a parse/lex pass.
// Call after parse(ls) completes to obtain comment-association data without
// a second scan.  The List form of commentsBuf is returned so callers can
// use Lst.foldl / Dict directly.
export fun getDeclInfo(ls: LexState): (List<(Int, List<String>)>, Array<Int>) =
  (Arr.toList(ls.commentsBuf), ls.posBuf)

export fun lex(src: String): List<Token.Token> = {
  val ls = create(src)
  val tokens: Array<Token.Token> = Arr.new()

  while (True) {
    val tok = nextToken(ls)
    Arr.push(tokens, tok)
    if (tok.kind == TkEof) {
      break
    }
  }

  Arr.toList(tokens)
}
