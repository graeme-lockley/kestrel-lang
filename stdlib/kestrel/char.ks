// kestrel:char — helpers for Char (single Unicode scalar).

/** Unicode scalar value as `Int` (only primitive call Char → Int in this module). */
export fun codePoint(c: Char): Int = __char_code_point(c)

/** Synonym for `codePoint` (common in FP stdlibs). */
export fun toCode(c: Char): Int = codePoint(c)

/** Synonym for `codePoint` (pairs with `intToChar`). */
export fun charToInt(c: Char): Int = toCode(c)

export fun fromCode(n: Int): Char = __char_from_code(n)

/** Synonym for `fromCode` (pairs with `charToInt`). */
export fun intToChar(n: Int): Char = fromCode(n)

/** Single-code-point UTF-8 string. */
export fun charToString(c: Char): String = __char_to_string(c)

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
  // `;` required: the lexer drops newlines, so without it `codePoint(c)(` is parsed as currying.
  val cp = codePoint(c);
  (cp >= 48 & cp <= 57) | (cp >= 65 & cp <= 70) | (cp >= 97 & cp <= 102)
}

export fun toUpper(c: Char): Char =
  if (isLower(c)) intToChar(charToInt(c) - 32) else c

export fun toLower(c: Char): Char =
  if (isUpper(c)) intToChar(charToInt(c) + 32) else c
