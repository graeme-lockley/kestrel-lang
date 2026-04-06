import * as Str from "kestrel:data/string"
import * as Lst from "kestrel:data/list"
import * as Arr from "kestrel:array"
import * as Token from "kestrel:dev/parser/token"
import { TPLiteral, TPInterp, TkInt, TkFloat, TkStr, TkTemplate, TkChar,
         TkIdent, TkUpper, TkKw, TkOp, TkPunct, TkWs,
         TkLineComment, TkBlockComment, TkEof } from "kestrel:dev/parser/token"

val KEYWORDS = [
  "exception", "continue", "opaque", "extern", "export", "import",
  "async", "await", "break", "catch", "match", "throw", "while",
  "else", "from", "type", "fun", "mut", "try", "val", "var", "as", "if", "is"
]

val MULTI_OPS = [
  "=>", ":=", "==", "!=", ">=", "<=", "**", "<|", "::", "|>", "->", "..."
]

val SINGLE_OPS = "+-*/%|&<>=!"

val PUNCT_CHARS = "(){}[],:.;"

fun cpOf(src: String, pos: Int): Int =
  if (pos >= Str.length(src)) -1 else Str.codePointAt(src, pos)

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

fun chrAt(src: String, pos: Int): String =
  if (pos >= Str.length(src)) "" else Str.slice(src, pos, pos + 1)

fun makeSpan(start: Int, end: Int, line: Int, col: Int): Token.Span =
  { start = start, end = end, line = line, col = col }

fun makeTok(kind: Token.TokenKind, text: String, span: Token.Span): Token.Token =
  { kind = kind, text = text, span = span }

fun lexWsEnd(src: String, pos: Int): Int = {
  var p = pos
  val len = Str.length(src)
  while (p < len & isWs(cpOf(src, p))) {
    p := p + 1
  }
  p
}

fun lexLineEnd(src: String, pos: Int): Int = {
  var p = pos
  val len = Str.length(src)
  while (p < len & cpOf(src, p) != 10) {
    p := p + 1
  }
  p
}

fun lexBlockEnd(src: String, pos: Int): Int = {
  var p = pos
  val len = Str.length(src)
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
  val len = Str.length(src)
  while (p < len & isAlNum(cpOf(src, p))) {
    p := p + 1
  }
  p
}

fun lexHexEnd(src: String, pos: Int): Int = {
  var p = pos
  val len = Str.length(src)
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
  val len = Str.length(src)
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
  val len = Str.length(src)
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
  val len = Str.length(src)
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
  val len = Str.length(src)
  if (pos >= len) pos
  else {
    val cp = cpOf(src, pos)
    if (cp == 69 | cp == 101) {
      var p = pos + 1
      val hasSign = p < len & (cpOf(src, p) == 43 | cpOf(src, p) == 45)
      val p2 = if (hasSign) p + 1 else p
      if (p2 < len & isDigit(cpOf(src, p2))) {
        var ep = p2
        val elen = Str.length(src)
        while (ep < elen & isDigit(cpOf(src, ep))) {
          ep := ep + 1
        }
        ep
      } else pos
    } else pos
  }
}

fun lexEscEnd(src: String, pos: Int): Int = {
  val len = Str.length(src)
  if (pos >= len) -1
  else {
    val esc = cpOf(src, pos)
    if (esc == 110 | esc == 114 | esc == 116 | esc == 34 | esc == 92 | esc == 39) {
      pos + 1
    } else if (esc == 117 & pos + 1 < len & cpOf(src, pos + 1) == 123) {
      var p = pos + 2
      val hlen = Str.length(src)
      while (p < hlen & isHexDigit(cpOf(src, p))) {
        p := p + 1
      }
      if (p < hlen & cpOf(src, p) == 125) p + 1 else -1
    } else -1
  }
}

type StringResult = SROk(Int, Token.TokenKind) | SRError

fun lexStringFrom(src: String, pos: Int): StringResult = {
  val len = Str.length(src)
  val parts: Array<Token.TemplatePart> = Arr.new()
  var p = pos
  var litStart = pos
  var running = True
  var success = False

  while (p < len & running) {
    val cp = cpOf(src, p)
    if (cp == 34) {
      val litText = Str.slice(src, litStart, p)
      if (Str.length(litText) > 0) {
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
      val litText = Str.slice(src, litStart, p)
      if (Str.length(litText) > 0) {
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
          val interpSrc = Str.slice(src, interpStart, p)
          Arr.push(parts, TPInterp(interpSrc))
          p := p + 1
          litStart := p
        }
      } else if (p < len & (isAlpha(cpOf(src, p)) | cpOf(src, p) == 95)) {
        val identEnd = lexIdentEnd(src, p)
        val identSrc = Str.slice(src, p, identEnd)
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
  val len = Str.length(src)
  val rest = Str.slice(src, pos, len)
  fun tryOps(ops: List<String>): String =
    match (ops) {
      [] => "",
      op :: tail =>
        if (Str.startsWith(op, rest)) op
        else tryOps(tail)
    }
  tryOps(MULTI_OPS)
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
  val len = Str.length(src)
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

fun pushWsTok(tokens: Array<Token.Token>, src: String, pos: Int, line: Int, col: Int): (Int, Int, Int) = {
  val endPos = lexWsEnd(src, pos)
  val text = Str.slice(src, pos, endPos)
  val span = makeSpan(pos, endPos, line, col)
  Arr.push(tokens, makeTok(TkWs, text, span));
  val lc = advanceLc(src, pos, endPos, line, col);
  (endPos, lc.0, lc.1)
}

fun pushLineCmtTok(tokens: Array<Token.Token>, src: String, pos: Int, line: Int, col: Int): (Int, Int, Int) = {
  val endPos = lexLineEnd(src, pos + 2)
  val text = Str.slice(src, pos, endPos)
  val span = makeSpan(pos, endPos, line, col)
  Arr.push(tokens, makeTok(TkLineComment, text, span));
  (endPos, line, col + (endPos - pos))
}

fun pushBlockCmtTok(tokens: Array<Token.Token>, src: String, pos: Int, line: Int, col: Int): (Int, Int, Int) = {
  val endPos = lexBlockEnd(src, pos + 2)
  val text = Str.slice(src, pos, endPos)
  val span = makeSpan(pos, endPos, line, col)
  Arr.push(tokens, makeTok(TkBlockComment, text, span));
  val lc = advanceLc(src, pos, endPos, line, col);
  (endPos, lc.0, lc.1)
}

fun pushIdentTok(tokens: Array<Token.Token>, src: String, pos: Int, line: Int, col: Int): (Int, Int, Int) = {
  val endPos = lexIdentEnd(src, pos)
  val text = Str.slice(src, pos, endPos)
  val span = makeSpan(pos, endPos, line, col)
  val kind =
    if (Lst.member(KEYWORDS, text)) TkKw
    else if (isUpper(cpOf(text, 0))) TkUpper
    else TkIdent
  Arr.push(tokens, makeTok(kind, text, span));
  (endPos, line, col + (endPos - pos))
}

fun pushDotFloatTok(tokens: Array<Token.Token>, src: String, pos: Int, line: Int, col: Int): (Int, Int, Int) = {
  val afterDot = lexDecEnd(src, pos + 1)
  val endPos = lexExpEnd(src, afterDot)
  val text = Str.slice(src, pos, endPos)
  val span = makeSpan(pos, endPos, line, col)
  Arr.push(tokens, makeTok(TkFloat, text, span));
  (endPos, line, col + (endPos - pos))
}

fun pushZeroNumTok(tokens: Array<Token.Token>, src: String, pos: Int, line: Int, col: Int): (Int, Int, Int) = {
  val len = Str.length(src)
  val nextCp = if (pos + 1 < len) cpOf(src, pos + 1) else -1
  if (nextCp == 120 | nextCp == 88) {
    val endPos = lexHexEnd(src, pos + 2)
    val text = Str.slice(src, pos, endPos)
    val span = makeSpan(pos, endPos, line, col)
    Arr.push(tokens, makeTok(TkInt, text, span));
    (endPos, line, col + (endPos - pos))
  } else if (nextCp == 98 | nextCp == 66) {
    val endPos = lexBinEnd(src, pos + 2)
    val text = Str.slice(src, pos, endPos)
    val span = makeSpan(pos, endPos, line, col)
    Arr.push(tokens, makeTok(TkInt, text, span));
    (endPos, line, col + (endPos - pos))
  } else if (nextCp == 111 | nextCp == 79) {
    val endPos = lexOctEnd(src, pos + 2)
    val text = Str.slice(src, pos, endPos)
    val span = makeSpan(pos, endPos, line, col)
    Arr.push(tokens, makeTok(TkInt, text, span));
    (endPos, line, col + (endPos - pos))
  } else {
    val r = lexNumEnd(src, pos)
    val endPos = r.0
    val text = Str.slice(src, pos, endPos)
    val span = makeSpan(pos, endPos, line, col)
    val kind = if (r.1) TkFloat else TkInt
    Arr.push(tokens, makeTok(kind, text, span));
    (endPos, line, col + (endPos - pos))
  }
}

fun pushNumTok(tokens: Array<Token.Token>, src: String, pos: Int, cp: Int, line: Int, col: Int): (Int, Int, Int) = {
  val len = Str.length(src)
  if (cp == 48 & pos + 1 < len) {
    pushZeroNumTok(tokens, src, pos, line, col)
  } else {
    val r = lexNumEnd(src, pos)
    val endPos = r.0
    val text = Str.slice(src, pos, endPos)
    val span = makeSpan(pos, endPos, line, col)
    val kind = if (r.1) TkFloat else TkInt
    Arr.push(tokens, makeTok(kind, text, span));
    (endPos, line, col + (endPos - pos))
  }
}

fun pushStrTok(tokens: Array<Token.Token>, src: String, pos: Int, line: Int, col: Int): (Int, Int, Int) = {
  val strResult = lexStringFrom(src, pos + 1)
  match (strResult) {
    SROk(strEnd, strKind) => {
      val text = Str.slice(src, pos, strEnd)
      val span = makeSpan(pos, strEnd, line, col)
      Arr.push(tokens, makeTok(strKind, text, span));
      (strEnd, line, col + (strEnd - pos))
    },
    SRError => {
      val errText = Str.slice(src, pos, pos + 1)
      val span = makeSpan(pos, pos + 1, line, col)
      Arr.push(tokens, makeTok(TkStr, errText, span));
      (pos + 1, line, col + 1)
    }
  }
}

fun charEscEnd(src: String, pos: Int): Int = {
  val len = Str.length(src)
  val escEnd = lexEscEnd(src, pos + 1)
  val afterEsc = if (escEnd < 0) pos + 1 else escEnd
  if (afterEsc < len) {
    if (cpOf(src, afterEsc) == 39) afterEsc + 1 else afterEsc
  } else {
    afterEsc
  }
}

fun charPlainEnd(src: String, pos: Int): Int = {
  val len = Str.length(src)
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
  val len = Str.length(src)
  val chrPos = pos + 1
  if (chrPos >= len) chrPos
  else if (cpOf(src, chrPos) == 92) charEscEnd(src, chrPos)
  else charPlainEnd(src, chrPos)
}

fun pushCharTok(tokens: Array<Token.Token>, src: String, pos: Int, line: Int, col: Int): (Int, Int, Int) = {
  val endPos = charLiteralEnd(src, pos)
  val text = Str.slice(src, pos, endPos)
  val span = makeSpan(pos, endPos, line, col)
  Arr.push(tokens, makeTok(TkChar, text, span));
  (endPos, line, col + (endPos - pos))
}

fun pushOpOrPunctTok(tokens: Array<Token.Token>, src: String, pos: Int, line: Int, col: Int): (Int, Int, Int) = {
  val mop = matchMultiOp(src, pos)
  if (Str.length(mop) > 0) {
    val endPos = pos + Str.length(mop)
    val span = makeSpan(pos, endPos, line, col)
    Arr.push(tokens, makeTok(TkOp, mop, span));
    (endPos, line, col + Str.length(mop))
  } else {
    val ch = Str.slice(src, pos, pos + 1)
    if (Str.contains(ch, SINGLE_OPS)) {
      val span = makeSpan(pos, pos + 1, line, col)
      Arr.push(tokens, makeTok(TkOp, ch, span));
      (pos + 1, line, col + 1)
    } else if (Str.contains(ch, PUNCT_CHARS)) {
      val span = makeSpan(pos, pos + 1, line, col)
      Arr.push(tokens, makeTok(TkPunct, ch, span));
      (pos + 1, line, col + 1)
    } else {
      (pos + 1, line, col + 1)
    }
  }
}

export fun lex(src: String): List<Token.Token> = {
  val tokens: Array<Token.Token> = Arr.new()
  val len = Str.length(src)
  var pos = 0
  var line = 1
  var col = 1

  while (pos < len) {
    val cp = cpOf(src, pos)
    if (isWs(cp)) {
      val r = pushWsTok(tokens, src, pos, line, col)
      pos := r.0
      line := r.1
      col := r.2
    } else if (cp == 47 & pos + 1 < len & cpOf(src, pos + 1) == 47) {
      val r = pushLineCmtTok(tokens, src, pos, line, col)
      pos := r.0
      line := r.1
      col := r.2
    } else if (cp == 47 & pos + 1 < len & cpOf(src, pos + 1) == 42) {
      val r = pushBlockCmtTok(tokens, src, pos, line, col)
      pos := r.0
      line := r.1
      col := r.2
    } else if (isAlpha(cp) | cp == 95) {
      val r = pushIdentTok(tokens, src, pos, line, col)
      pos := r.0
      line := r.1
      col := r.2
    } else if (cp == 46 & pos + 1 < len & isDigit(cpOf(src, pos + 1))) {
      val r = pushDotFloatTok(tokens, src, pos, line, col)
      pos := r.0
      line := r.1
      col := r.2
    } else if (isDigit(cp)) {
      val r = pushNumTok(tokens, src, pos, cp, line, col)
      pos := r.0
      line := r.1
      col := r.2
    } else if (cp == 34) {
      val r = pushStrTok(tokens, src, pos, line, col)
      pos := r.0
      line := r.1
      col := r.2
    } else if (cp == 39) {
      val r = pushCharTok(tokens, src, pos, line, col)
      pos := r.0
      line := r.1
      col := r.2
    } else {
      val r = pushOpOrPunctTok(tokens, src, pos, line, col)
      pos := r.0
      line := r.1
      col := r.2
    }
  }

  val eofSpan = makeSpan(len, len, line, col)
  Arr.push(tokens, makeTok(TkEof, "", eofSpan))
  Arr.toList(tokens)
}
