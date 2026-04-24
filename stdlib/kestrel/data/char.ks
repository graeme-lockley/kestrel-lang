//! Helpers for the `Char` type — a single Unicode scalar value (code point).
//!
//! `Char` represents one Unicode scalar carried as an opaque JVM value. This module
//! provides the bridge between `Char`, `Int` (code point), and single-character
//! `String`, plus ASCII classification predicates and case-conversion.
//!
//! All predicates (`isDigit`, `isUpper`, etc.) cover only the Basic Latin block
//! (ASCII, U+0000–U+007F). For broader Unicode classification obtain the code point
//! via `codePoint` and compare against explicit ranges.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as Ch from "kestrel:data/char"
//!
//! val c = Ch.intToChar(97)      // 'a'
//! val n = Ch.charToInt(c)       // 97
//! val upper = Ch.toUpper(c)     // 'A'
//! val alpha = Ch.isAlpha(c)     // True
//! val hex = Ch.isHexDigit('f')  // True
//! val s = Ch.charToString(upper)
//! ```
//!

/// The Unicode code point of `c` as an `Int` (0–1114111).
export extern fun codePoint(c: Char): Int = 
  jvm("kestrel.runtime.KRuntime#charCodePoint(java.lang.Object)")

/// Synonym for `codePoint`; common in functional-style code.
export fun toCode(c: Char): Int = 
  codePoint(c)

/// Synonym for `codePoint`; pairs symmetrically with `intToChar`.
export fun charToInt(c: Char): Int = toCode(c)

/// Construct a `Char` from a Unicode code-point integer.
/// Behaviour is undefined for values outside 0–1114111 or surrogate halves.
export extern fun fromCode(n: Int): Char = 
  jvm("kestrel.runtime.KRuntime#charFromCode(java.lang.Object)")

/// Synonym for `fromCode`; pairs symmetrically with `charToInt`.
export fun intToChar(n: Int): Char = 
  fromCode(n)

/// A one-character `String` containing `c`.
export extern fun charToString(c: Char): String = 
  jvm("kestrel.runtime.KRuntime#charToString(java.lang.Object)")

/// `True` for ASCII decimal digits `'0'`–`'9'` (U+0030–U+0039).
export fun isDigit(c: Char): Bool = {
  val cp = codePoint(c)
  cp >= 48 & cp <= 57
}

/// `True` for ASCII uppercase letters `'A'`–`'Z'` (U+0041–U+005A).
export fun isUpper(c: Char): Bool = {
  val cp = codePoint(c)
  cp >= 65 & cp <= 90
}

/// `True` for ASCII lowercase letters `'a'`–`'z'` (U+0061–U+007A).
export fun isLower(c: Char): Bool = {
  val cp = codePoint(c)
  cp >= 97 & cp <= 122
}

/// `True` for ASCII letters (upper- or lower-case).
export fun isAlpha(c: Char): Bool = 
  isUpper(c) | isLower(c)

/// `True` for ASCII letters or decimal digits.
export fun isAlphaNum(c: Char): Bool = 
  isAlpha(c) | isDigit(c)

/// `True` for octal digits `'0'`–`'7'` (U+0030–U+0037).
export fun isOctDigit(c: Char): Bool = {
  val cp = codePoint(c)
  cp >= 48 & cp <= 55
}

/// `True` for hexadecimal digits: `'0'`–`'9'`, `'A'`–`'F'`, or `'a'`–`'f'`.
export fun isHexDigit(c: Char): Bool = {
  // `;` required: the lexer drops newlines, so without it `codePoint(c)(` is parsed as currying.
  val cp = codePoint(c);
  (cp >= 48 & cp <= 57) | (cp >= 65 & cp <= 70) | (cp >= 97 & cp <= 102)
}

/// Convert an ASCII lowercase letter to its uppercase equivalent.
/// All other characters are returned unchanged.
export fun toUpper(c: Char): Char =
  if (isLower(c)) intToChar(charToInt(c) - 32) else c

/// Convert an ASCII uppercase letter to its lowercase equivalent.
/// All other characters are returned unchanged.
export fun toLower(c: Char): Char =
  if (isUpper(c)) intToChar(charToInt(c) + 32) else c
