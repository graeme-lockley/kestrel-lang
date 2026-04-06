import * as Lst from "kestrel:data/list"
import * as Arr from "kestrel:array"
import * as Token from "kestrel:dev/parser/token"
import {
  TkInt, TkFloat, TkStr, TkChar, TkTemplate, TkIdent, TkUpper, TkKw, TkOp, TkPunct, TkEof
} from "kestrel:dev/parser/token"

export type TokenStream = { tokens: Array<Token.Token>, len: Int }

export fun fromTokenList(tokenList: List<Token.Token>): TokenStream = {
  val filtered = Lst.filter(tokenList, (t: Token.Token) => !Token.isTrivia(t))
  val arr = Arr.fromList(filtered)
  val n = Lst.length(filtered)
  { tokens = arr, len = n }
}

export fun get(ts: TokenStream, idx: Int): Token.Token = {
  val safeIdx = if (idx < ts.len) idx else ts.len - 1
  Arr.get(ts.tokens, safeIdx)
}

export fun length(ts: TokenStream): Int = ts.len

export fun text(ts: TokenStream, idx: Int): String = get(ts, idx).text

export fun spanStart(ts: TokenStream, idx: Int): Int = get(ts, idx).span.start
export fun spanLine(ts: TokenStream, idx: Int): Int = get(ts, idx).span.line
export fun spanCol(ts: TokenStream, idx: Int): Int = get(ts, idx).span.col

export fun isKw(ts: TokenStream, idx: Int): Bool = get(ts, idx).kind == TkKw
export fun isOp(ts: TokenStream, idx: Int): Bool = get(ts, idx).kind == TkOp
export fun isPunct(ts: TokenStream, idx: Int): Bool = get(ts, idx).kind == TkPunct
export fun isIdent(ts: TokenStream, idx: Int): Bool = get(ts, idx).kind == TkIdent
export fun isUpper(ts: TokenStream, idx: Int): Bool = get(ts, idx).kind == TkUpper
export fun isEof(ts: TokenStream, idx: Int): Bool = get(ts, idx).kind == TkEof
export fun isInt(ts: TokenStream, idx: Int): Bool = get(ts, idx).kind == TkInt
export fun isFloat(ts: TokenStream, idx: Int): Bool = get(ts, idx).kind == TkFloat
export fun isStr(ts: TokenStream, idx: Int): Bool = get(ts, idx).kind == TkStr
export fun isChar(ts: TokenStream, idx: Int): Bool = get(ts, idx).kind == TkChar
export fun isTemplate(ts: TokenStream, idx: Int): Bool = get(ts, idx).kind == TkTemplate([])

export fun templateParts(ts: TokenStream, idx: Int): List<Token.TemplatePart> =
  match (get(ts, idx).kind) {
    TkTemplate(parts) => parts,
    _ => []
  }
