// kestrel:char — helpers for Char (single Unicode scalar).

export fun codePoint(c: Char): Int = __char_code_point(c)

/** Alias for `codePoint`. */
export fun toCode(c: Char): Int = codePoint(c)

export fun fromCode(n: Int): Char = __char_from_code(n)

export fun isDigit(c: Char): Bool = {
  val cp = codePoint(c)
  cp >= 48 & cp <= 57
}

export fun isUpper(c: Char): Bool = {
  val cp = codePoint(c)
  cp >= 65 & cp <= 90
}

export fun isLower(c: Char): Bool = {
  val cp = codePoint(c)
  cp >= 97 & cp <= 122
}

export fun isAlpha(c: Char): Bool = isUpper(c) | isLower(c)

export fun isAlphaNum(c: Char): Bool = isAlpha(c) | isDigit(c)

export fun isOctDigit(c: Char): Bool = {
  val cp = codePoint(c)
  cp >= 48 & cp <= 55
}

export fun isHexDigit(c: Char): Bool = {
  val cp = codePoint(c)
  isDigit(c) | (cp >= 65 & cp <= 70) | (cp >= 97 & cp <= 102)
}

export fun toUpper(c: Char): Char =
  if (isLower(c)) fromCode(codePoint(c) - 32) else c

export fun toLower(c: Char): Char =
  if (isUpper(c)) fromCode(codePoint(c) + 32) else c
