//! String manipulation helpers for the built-in `String` type.
//!
//! Covers slicing, searching, splitting, joining, trimming, padding, case
//! conversion, character-level access, numeric conversions, and base-N formatting.
//!
//! Indexing is code-unit-based (0-origin, exclusive end), consistent with Kestrel's
//! lexer internals. For most ASCII and BMP source code the index equals the
//! code-point index. Negative indices are supported in `sliceRel`.
//!
//! Argument order: most functions that read naturally as "get something FROM a
//! string" place the string first (`length`, `trim`, `toUpper`). Functions that
//! describe a relationship — `contains`, `startsWith`, `endsWith`, `indexes`,
//! `replace` — place the needle/pattern first and the haystack/subject last for
//! partial application.
//!
//! String interpolation (`"${expr}"`) is the idiomatic way to build strings;
//! prefer it over `append` for readability.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as Str from "kestrel:data/string"
//!
//! val raw = "  hello, kestrel  "
//! val clean = raw |> Str.trim |> Str.toUpper
//! val parts = Str.split(clean, ",")
//! val joined = Str.join(" | ", parts)
//! val hasKel = Str.contains("KEL", joined)
//! val n = Str.toInt("42")
//! ```
//!

/// Number of code units (not Unicode scalar values) in `s`. O(1) because
/// Java strings store their length.
export extern fun length(s: String): Int =
  jvm("kestrel.runtime.KRuntime#stringLength(java.lang.Object)")

/// Extract characters at code-unit positions `[start, end)`. Both bounds are clamped
/// to `[0, length(s)]`; an empty string is returned when `start >= end`.
export extern fun slice(s: String, start: Int, end: Int): String =
  jvm("kestrel.runtime.KRuntime#stringSlice(java.lang.Object,java.lang.Object,java.lang.Object)")

/// First `n` characters. Equivalent to `slice(s, 0, n)`. Returns `""` when `n <= 0`,
/// the full string when `n >= length(s)`.
export fun left(s: String, n: Int): String =
  if (n <= 0) "" else {
    val len = length(s)
    val take = if (n < len) n else len
    slice(s, 0, take)
  }

/// Last `n` characters. Returns `""` when `n <= 0`, the full string when `n >= length(s)`.
export fun right(s: String, n: Int): String =
  if (n <= 0) "" else {
    val len = length(s)
    val start = if (n >= len) 0 else len - n
    slice(s, start, len)
  }

/// Remove the first `n` code units. Returns `""` when `n >= length(s)`.
export fun dropLeft(s: String, n: Int): String =
  if (n <= 0) s else {
    val len = length(s)
    if (n >= len) "" else slice(s, n, len)
  }

/// Remove the last `n` code units. Returns `""` when `n >= length(s)`.
export fun dropRight(s: String, n: Int): String =
  if (n <= 0) s else {
    val len = length(s)
    if (n >= len) "" else slice(s, 0, len - n)
  }

extern fun charAt(s: String, i: Int): Char =
  jvm("kestrel.runtime.KRuntime#stringCharAt(java.lang.Object,java.lang.Object)")

extern fun charStr(c: Char): String =
  jvm("kestrel.runtime.KRuntime#charToString(java.lang.Object)")

/// Code-unit index of the first occurrence of `sub` in `s`, or `-1` if absent.
export extern fun indexOf(s: String, sub: String): Int =
  jvm("kestrel.runtime.KRuntime#stringIndexOf(java.lang.Object,java.lang.Object)")

/// Like `indexOf` but starts scanning at code-unit position `start`.
export extern fun indexOfFrom(s: String, sub: String, start: Int): Int =
  jvm("kestrel.runtime.KRuntime#stringIndexOfFrom(java.lang.Object,java.lang.Object,java.lang.Object)")

/// `True` if `a` and `b` have identical content. Prefer the built-in `==` operator;
/// this function exists for use in higher-order contexts.
export extern fun equals(a: String, b: String): Bool =
  jvm("kestrel.runtime.KRuntime#stringEquals(java.lang.Object,java.lang.Object)")

/// Convert every character to its Unicode uppercase form.
export extern fun toUpperCase(s: String): String =
  jvm("kestrel.runtime.KRuntime#stringUpper(java.lang.Object)")

/// Alias for `toUpperCase`. Prefer `toUpperCase` for new code.
export fun toUpper(s: String): String =
  toUpperCase(s)

/// Remove leading and trailing ASCII whitespace (space, tab, CR, LF).
export extern fun trim(s: String): String =
  jvm("kestrel.runtime.KRuntime#stringTrim(java.lang.Object)")

/// `True` if `length(s) == 0`.
export fun isEmpty(s: String): Bool =
  length(s) == 0

/// Unicode code point (integer scalar value) at code-unit index `i`. Undefined behaviour
/// for out-of-bounds indices; always check against `length(s)` first.
export extern fun codePointAt(s: String, i: Int): Int =
  jvm("kestrel.runtime.KRuntime#stringCodePointAt(java.lang.Object,java.lang.Object)")

fun normIdx(i: Int, len: Int): Int =
  if (i < 0) len + i else i

fun clampIdx(a: Int, lo: Int, hi: Int): Int =
  if (a < lo) lo else if (a > hi) hi else a

/// Slice with string-last argument order (for `|>` piping) and negative-index support.
/// Negative indices are resolved relative to `length(s)`: `-1` is the last code unit.
export fun sliceRel(start: Int, end: Int, s: String): String =
  {
    val len = length(s)
    val a = clampIdx(normIdx(start, len), 0, len)
    val b = clampIdx(normIdx(end, len), 0, len)
    if (a <= b) slice(s, a, b) else ""
  }

fun parseUnsignedAll(t: String, i: Int, acc: Int): Int =
  if (i >= length(t)) acc else {
    val cp = codePointAt(t, i)
    if (cp >= 48 & cp <= 57) parseUnsignedAll(t, i + 1, acc * 10 + (cp - 48)) else 0
  }

/// Parse `s` as a decimal integer. Accepts a leading `-`. Returns `0` on any failure;
/// for error-distinguishing behaviour use `toInt`.
export fun parseInt(s: String): Int =
  {
    val t = trim(s)
    if (length(t) == 0)
      0 else if (equals(slice(t, 0, 1), "-") & length(t) > 1)
      0 - parseUnsignedAll(t, 1, 0) else parseUnsignedAll(t, 0, 0)
  }

fun isAllDigitsUnsigned(t: String, i: Int): Bool =
  if (i >= length(t)) True else {
    val cp = codePointAt(t, i)
    if (cp >= 48 & cp <= 57) isAllDigitsUnsigned(t, i + 1) else False
  }

/// Parse `s` as a decimal integer, returning `None` instead of a fallback on failure.
export fun toInt(s: String): Option<Int> =
  {
    val t = trim(s)
    if (length(t) == 0) None else if (equals(slice(t, 0, 1), "-")) {
      if (length(t) == 1) None else if (isAllDigitsUnsigned(t, 1)) Some(parseInt(t)) else None
    } else if (isAllDigitsUnsigned(t, 0)) Some(parseInt(t)) else None
  }

/// Decimal string representation of the integer `n`.
export fun fromInt(n: Int): String =
  "${n}"

extern fun parseFloatImpl(s: String): Option<Float> =
  jvm("kestrel.runtime.KRuntime#parseFloat(java.lang.Object)")

extern fun toFloatImpl(s: String): Float =
  jvm("kestrel.runtime.KRuntime#toFloat(java.lang.Object)")

/// Parse `s` as a floating-point number. Returns `None` on failure.
export fun parseFloat(s: String): Option<Float> = parseFloatImpl(s)
/// Parse `s` as a floating-point number. Returns `0.0` on failure. Use `parseFloat` for error-distinguishing behaviour.
export fun toFloat(s: String): Float = toFloatImpl(s)

/// Split `s` on every occurrence of `delim`. Returns `[""]` for an empty string.
/// Use `splitWithDelimiters` when you need to split on multiple alternative delimiters.
export extern fun split(s: String, delim: String): List<String> =
  jvm("kestrel.runtime.KRuntime#stringSplit(java.lang.Object,java.lang.Object)")

fun matchDelimiterAt(s: String, delims: List<String>, i: Int): Int =
  match (delims) {
    [] =>
      0,
    d :: rest =>
      {
        val dLen = length(d)
        if (equals(slice(s, i, i + dLen), d)) dLen else matchDelimiterAt(s, rest, i)
      }
  }

fun splitWithDelimsLoop(s: String, delims: List<String>, idx: Int, tokenStart: Int): List<String> =
  if (idx >= length(s)) [slice(s, tokenStart, length(s))] else {
    val dLen = matchDelimiterAt(s, delims, idx)
    if (dLen > 0)
      slice(s,
        tokenStart,
        idx) :: splitWithDelimsLoop(s,
        delims,
        idx + dLen,
        idx + dLen) else splitWithDelimsLoop(s, delims, idx + 1, tokenStart)
  }

/// Split `s` on the first matching delimiter from `delims` at each position.
/// Useful for splitting on any one of several alternative strings.
export fun splitWithDelimiters(s: String, delims: List<String>): List<String> =
  splitWithDelimsLoop(s, delims, 0, 0)

/// Concatenate `parts`, inserting `sep` between consecutive elements.
export extern fun join(sep: String, parts: List<String>): String =
  jvm("kestrel.runtime.KRuntime#stringJoin(java.lang.Object,java.lang.Object)")

/// Concatenate two strings. Prefer string interpolation `"${a}${b}"` for readability.
export extern fun append(a: String, b: String): String =
  jvm("kestrel.runtime.KRuntime#concat(java.lang.Object,java.lang.Object)")

/// Concatenate a list of strings with no separator. Equivalent to `join("", parts)`.
export fun concat(parts: List<String>): String =
  join("", parts)

/// Return `s` with its characters in reverse order.
export fun reverse(s: String): String =
  revStr(s, length(s), "")

fun revStr(s: String, i: Int, acc: String): String =
  if (i <= 0) acc else revStr(s, i - 1, append(acc, slice(s, i - 1, i)))

/// Return `s` repeated `n` times. Returns `""` when `n <= 0`.
export fun repeat(n: Int, s: String): String =
  repStr(n, s, "")

fun repStr(n: Int, s: String, acc: String): String =
  if (n <= 0) acc else repStr(n - 1, s, append(acc, s))

/// Replace every non-overlapping occurrence of `before` with `after` in `haystack`.
/// When `before` is `""` the original string is returned unchanged.
export fun replace(before: String, after: String, haystack: String): String =
  if (length(before) == 0) haystack else join(after, split(haystack, before))

/// Split on newline characters (`\n`), returning one string per line.
export fun lines(s: String): List<String> =
  split(s, "\n")

fun isAsciiWsCp(cp: Int): Bool =
  cp == 32 | cp == 9 | cp == 10 | cp == 13 | cp == 11 | cp == 12

fun wordsSkip(s: String, i: Int): List<String> =
  if (i >= length(s)) [] else if (isAsciiWsCp(codePointAt(s, i))) wordsSkip(s, i + 1) else wordsTok(s, i, i)

fun wordsTok(s: String, start: Int, i: Int): List<String> =
  if (i >= length(s))
    [slice(s,
        start,
        i)] else if (isAsciiWsCp(codePointAt(s, i)))
    slice(s, start, i) :: wordsSkip(s, i + 1) else wordsTok(s, start, i + 1)

/// Split on runs of ASCII whitespace, discarding all whitespace tokens.
/// Leading/trailing whitespace produces no empty strings in the result.
export fun words(s: String): List<String> =
  wordsSkip(s, 0)

/// `True` if `needle` appears anywhere in `haystack`.
export fun contains(needle: String, haystack: String): Bool =
  indexOf(haystack, needle) >= 0

/// `True` if `s` begins with `prefix`.
export fun startsWith(prefix: String, s: String): Bool =
  length(prefix) <= length(s) & left(s, length(prefix)) == prefix

/// `True` if `s` ends with `suffix`.
export fun endsWith(suffix: String, s: String): Bool =
  length(suffix) <= length(s) & right(s, length(suffix)) == suffix

fun revInts(xs: List<Int>, acc: List<Int>): List<Int> =
  match (xs) {
    [] =>
      acc,
    h :: t =>
      revInts(t, h :: acc)
  }

fun indexesLoop(haystack: String, needle: String, offset: Int, acc: List<Int>): List<Int> =
  if (length(needle) == 0) [] else {
    val tail = slice(haystack, offset, length(haystack))
    val rel = indexOf(tail, needle)
    if (rel < 0) revInts(acc, []) else {
      val abs = offset + rel
      indexesLoop(haystack, needle, abs + 1, abs :: acc)
    }
  }

/// All code-unit indices at which `needle` starts in `haystack`. Returns `[]` for an empty needle.
export fun indexes(needle: String, haystack: String): List<Int> =
  indexesLoop(haystack, needle, 0, [])

/// Alias for `indexes`. Prefer `indexes` for new code.
export fun indices(needle: String, haystack: String): List<Int> =
  indexes(needle, haystack)

/// Apply `f` to every `Char` in `s` and reassemble into a string.
export fun mapChars(s: String, f: Char -> Char): String =
  mapCharLoop(s, 0, length(s), "", f)

fun mapCharLoop(s: String, i: Int, n: Int, acc: String, f: Char -> Char): String =
  if (i >= n) acc else mapCharLoop(s, i + 1, n, append(acc, charStr(f(charAt(s, i)))), f)

/// Keep only the characters in `s` for which `pred` returns `True`.
export fun filterChars(s: String, pred: Char -> Bool): String =
  filterCharLoop(s, 0, length(s), "", pred)

fun filterCharLoop(s: String, i: Int, n: Int, acc: String, pred: Char -> Bool): String =
  if (i >= n) acc else {
    val c = charAt(s, i)
    filterCharLoop(s, i + 1, n, if (pred(c)) append(acc, charStr(c)) else acc, pred)
  }

/// Convert every character to its Unicode lowercase form.
export extern fun toLowerCase(s: String): String =
  jvm("kestrel.runtime.KRuntime#stringLower(java.lang.Object)")

/// Alias for `toLowerCase`. Prefer `toLowerCase` for new code.
export fun toLower(s: String): String =
  toLowerCase(s)

/// Prepend `unit` to `s` until `length(s) >= targetLen`. Falls back to one space when `unit` is `""`.
export fun padLeft(targetLen: Int, unit: String, s: String): String =
  {
    val u = if (isEmpty(unit)) " " else unit
    padLeftLoop(targetLen, u, s)
  }

fun padLeftLoop(targetLen: Int, unit: String, cur: String): String =
  if (length(cur) >= targetLen) cur else padLeftLoop(targetLen, unit, "${unit}${cur}")

/// Append `unit` to `s` until `length(s) >= targetLen`. Falls back to one space when `unit` is `""`.
export fun padRight(targetLen: Int, unit: String, s: String): String =
  {
    val u = if (isEmpty(unit)) " " else unit
    padRightLoop(targetLen, u, s)
  }

fun padRightLoop(targetLen: Int, unit: String, cur: String): String =
  if (length(cur) >= targetLen) cur else padRightLoop(targetLen, unit, "${cur}${unit}")

/// Centre `s` within `targetLen` columns by padding with `unit` on both sides.
/// When the required padding is odd, the extra unit is added on the right.
export fun pad(targetLen: Int, unit: String, s: String): String =
  {
    val need = targetLen - length(s)
    if (need <= 0) s else {
      val l = need / 2
      padRight(targetLen, unit, padLeft(length(s) + l, unit, s))
    }
  }

fun trimLeftIdx(s: String, i: Int): Int =
  if (i >= length(s)) i else if (isAsciiWsCp(codePointAt(s, i))) trimLeftIdx(s, i + 1) else i

fun trimRightIdx(s: String, i: Int): Int =
  if (i <= 0) 0 else if (isAsciiWsCp(codePointAt(s, i - 1))) trimRightIdx(s, i - 1) else i

/// Remove leading ASCII whitespace (space, tab, CR, LF, VT, FF).
export fun trimLeft(s: String): String =
  slice(s, trimLeftIdx(s, 0), length(s))

/// Remove trailing ASCII whitespace (space, tab, CR, LF, VT, FF).
export fun trimRight(s: String): String =
  slice(s, 0, trimRightIdx(s, length(s)))

/// Wrap a single `Char` in a one-character `String`.
export fun fromChar(c: Char): String =
  charStr(c)

/// Prepend character `c` to string `s`. Equivalent to `append(fromChar(c), s)`.
export fun cons(c: Char, s: String): String =
  append(fromChar(c), s)

fun revChars(xs: List<Char>, acc: List<Char>): List<Char> =
  match (xs) {
    [] =>
      acc,
    h :: t =>
      revChars(t, h :: acc)
  }

/// Decompose `s` into a `List<Char>` preserving code-unit order.
export fun toList(s: String): List<Char> =
  toListLoop(s, 0, length(s), [])

fun toListLoop(s: String, i: Int, n: Int, acc: List<Char>): List<Char> =
  if (i >= n) revChars(acc, []) else toListLoop(s, i + 1, n, charAt(s, i) :: acc)

/// Build a `String` from a `List<Char>`, the inverse of `toList`.
export fun fromList(cs: List<Char>): String =
  match (cs) {
    [] =>
      "",
    h :: t =>
      append(fromChar(h), fromList(t))
  }

/// `True` if `pred` returns `True` for at least one character in `s`.
export fun anyChar(s: String, pred: Char -> Bool): Bool =
  anyCharLoop(s, 0, length(s), pred)

fun anyCharLoop(s: String, i: Int, n: Int, pred: Char -> Bool): Bool =
  if (i >= n) False else if (pred(charAt(s, i))) True else anyCharLoop(s, i + 1, n, pred)

/// `True` if `pred` returns `True` for every character in `s`. `True` for an empty string.
export fun allChars(s: String, pred: Char -> Bool): Bool =
  allCharLoop(s, 0, length(s), pred)

fun allCharLoop(s: String, i: Int, n: Int, pred: Char -> Bool): Bool =
  if (i >= n) True else if (!pred(charAt(s, i))) False else allCharLoop(s, i + 1, n, pred)

fun digitValue(cp: Int, radix: Int): Int =
  if (cp >= 48 & cp <= 57 & (cp - 48) < radix) cp - 48
  else if (cp >= 97 & cp <= 122 & (cp - 87) < radix) cp - 87
  else if (cp >= 65 & cp <= 90 & (cp - 55) < radix) cp - 55
  else -1

fun parseRadixLoop(s: String, i: Int, radix: Int, acc: Int): Option<Int> =
  if (i >= length(s)) Some(acc) else {
    val dv = digitValue(codePointAt(s, i), radix)
    if (dv < 0) None else parseRadixLoop(s, i + 1, radix, acc * radix + dv)
  }

/// Parse `s` as an integer in the given `radix` (2–36). Accepts digits 0–9 and
/// letters a–z / A–Z. Returns `None` on empty input or an unrecognised digit.
export fun parseIntRadix(radix: Int, s: String): Option<Int> =
  if (length(s) == 0) None else parseRadixLoop(s, 0, radix, 0)

/// Format `n` as a decimal string left-padded with `'0'` to at least `width` digits.
export fun formatInt(width: Int, n: Int): String =
  padLeft(width, "0", fromInt(n))

/// `Some(i)` where `i` is the first code-unit index of character `c` in `s`, or `None`.
export fun indexOfChar(c: Char, s: String): Option<Int> =
  {
    val i = indexOf(s, charStr(c))
    if (i < 0) None else Some(i)
  }

val baseDigits = "0123456789abcdef"

fun toBaseLoop(base: Int, n: Int, acc: String): String =
  if (n == 0) acc
  else toBaseLoop(base, n / base, append(slice(baseDigits, n % base, n % base + 1), acc))

fun toBaseString(base: Int, n: Int): String =
  if (n == 0) "0" else toBaseLoop(base, n, "")

/// Lowercase hexadecimal representation of `n` (no `0x` prefix).
export fun toHexString(n: Int): String = toBaseString(16, n)
/// Binary representation of `n` (no `0b` prefix).
export fun toBinaryString(n: Int): String = toBaseString(2, n)
/// Octal representation of `n` (no `0o` prefix).
export fun toOctalString(n: Int): String = toBaseString(8, n)
/// Lowercase hexadecimal representation of `n`, zero-padded to at least `width` digits.
export fun toHexStringPadded(width: Int, n: Int): String = padLeft(width, "0", toHexString(n))
