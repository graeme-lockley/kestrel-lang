// kestrel:char — helpers for Char / Rune (single Unicode code point; same type per language spec).

export fun codePoint(c: Char): Int = __char_code_point(c)

/** True if `c` is an ASCII decimal digit (U+0030–U+0039). */
export fun isDigit(c: Char): Bool = {
  val cp = codePoint(c)
  cp >= 48 & cp <= 57
}
