// kestrel:string — spec 02 primitives plus additional string helpers.
export extern fun length(s: String): Int =
  jvm("kestrel.runtime.KRuntime#stringLength(java.lang.Object)")

export extern fun slice(s: String, start: Int, end: Int): String =
  jvm("kestrel.runtime.KRuntime#stringSlice(java.lang.Object,java.lang.Object,java.lang.Object)")

export fun left(s: String, n: Int): String =
  if (n <= 0) "" else {
    val len = length(s)
    val take = if (n < len) n else len
    slice(s, 0, take)
  }

export fun right(s: String, n: Int): String =
  if (n <= 0) "" else {
    val len = length(s)
    val start = if (n >= len) 0 else len - n
    slice(s, start, len)
  }

export fun dropLeft(s: String, n: Int): String =
  if (n <= 0) s else {
    val len = length(s)
    if (n >= len) "" else slice(s, n, len)
  }

export fun dropRight(s: String, n: Int): String =
  if (n <= 0) s else {
    val len = length(s)
    if (n >= len) "" else slice(s, 0, len - n)
  }

extern fun charAt(s: String, i: Int): Char =
  jvm("kestrel.runtime.KRuntime#stringCharAt(java.lang.Object,java.lang.Object)")

extern fun charStr(c: Char): String =
  jvm("kestrel.runtime.KRuntime#charToString(java.lang.Object)")

export extern fun indexOf(s: String, sub: String): Int =
  jvm("kestrel.runtime.KRuntime#stringIndexOf(java.lang.Object,java.lang.Object)")

export extern fun indexOfFrom(s: String, sub: String, start: Int): Int =
  jvm("kestrel.runtime.KRuntime#stringIndexOfFrom(java.lang.Object,java.lang.Object,java.lang.Object)")

export extern fun equals(a: String, b: String): Bool =
  jvm("kestrel.runtime.KRuntime#stringEquals(java.lang.Object,java.lang.Object)")

export extern fun toUpperCase(s: String): String =
  jvm("kestrel.runtime.KRuntime#stringUpper(java.lang.Object)")

export fun toUpper(s: String): String =
  toUpperCase(s)

export extern fun trim(s: String): String =
  jvm("kestrel.runtime.KRuntime#stringTrim(java.lang.Object)")

export fun isEmpty(s: String): Bool =
  length(s) == 0

export extern fun codePointAt(s: String, i: Int): Int =
  jvm("kestrel.runtime.KRuntime#stringCodePointAt(java.lang.Object,java.lang.Object)")

fun normIdx(i: Int, len: Int): Int =
  if (i < 0) len + i else i

fun clampIdx(a: Int, lo: Int, hi: Int): Int =
  if (a < lo) lo else if (a > hi) hi else a

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

export fun toInt(s: String): Option<Int> =
  {
    val t = trim(s)
    if (length(t) == 0) None else if (equals(slice(t, 0, 1), "-")) {
      if (length(t) == 1) None else if (isAllDigitsUnsigned(t, 1)) Some(parseInt(t)) else None
    } else if (isAllDigitsUnsigned(t, 0)) Some(parseInt(t)) else None
  }

export fun fromInt(n: Int): String =
  "${n}"

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

export fun splitWithDelimiters(s: String, delims: List<String>): List<String> =
  splitWithDelimsLoop(s, delims, 0, 0)

export extern fun join(sep: String, parts: List<String>): String =
  jvm("kestrel.runtime.KRuntime#stringJoin(java.lang.Object,java.lang.Object)")

export extern fun append(a: String, b: String): String =
  jvm("kestrel.runtime.KRuntime#concat(java.lang.Object,java.lang.Object)")

export fun concat(parts: List<String>): String =
  join("", parts)

export fun reverse(s: String): String =
  revStr(s, length(s), "")

fun revStr(s: String, i: Int, acc: String): String =
  if (i <= 0) acc else revStr(s, i - 1, append(acc, slice(s, i - 1, i)))

export fun repeat(n: Int, s: String): String =
  repStr(n, s, "")

fun repStr(n: Int, s: String, acc: String): String =
  if (n <= 0) acc else repStr(n - 1, s, append(acc, s))

export fun replace(before: String, after: String, haystack: String): String =
  if (length(before) == 0) haystack else join(after, split(haystack, before))

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

export fun words(s: String): List<String> =
  wordsSkip(s, 0)

export fun contains(needle: String, haystack: String): Bool =
  indexOf(haystack, needle) >= 0

export fun startsWith(prefix: String, s: String): Bool =
  length(prefix) <= length(s) & left(s, length(prefix)) == prefix

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

export fun indexes(needle: String, haystack: String): List<Int> =
  indexesLoop(haystack, needle, 0, [])

export fun indices(needle: String, haystack: String): List<Int> =
  indexes(needle, haystack)

export fun mapChars(s: String, f: Char -> Char): String =
  mapCharLoop(s, 0, length(s), "", f)

fun mapCharLoop(s: String, i: Int, n: Int, acc: String, f: Char -> Char): String =
  if (i >= n) acc else mapCharLoop(s, i + 1, n, append(acc, charStr(f(charAt(s, i)))), f)

export fun filterChars(s: String, pred: Char -> Bool): String =
  filterCharLoop(s, 0, length(s), "", pred)

fun filterCharLoop(s: String, i: Int, n: Int, acc: String, pred: Char -> Bool): String =
  if (i >= n) acc else {
    val c = charAt(s, i)
    filterCharLoop(s, i + 1, n, if (pred(c)) append(acc, charStr(c)) else acc, pred)
  }

export extern fun toLowerCase(s: String): String =
  jvm("kestrel.runtime.KRuntime#stringLower(java.lang.Object)")

export fun toLower(s: String): String =
  toLowerCase(s)

export fun padLeft(targetLen: Int, unit: String, s: String): String =
  {
    val u = if (isEmpty(unit)) " " else unit
    padLeftLoop(targetLen, u, s)
  }

fun padLeftLoop(targetLen: Int, unit: String, cur: String): String =
  if (length(cur) >= targetLen) cur else padLeftLoop(targetLen, unit, "${unit}${cur}")

export fun padRight(targetLen: Int, unit: String, s: String): String =
  {
    val u = if (isEmpty(unit)) " " else unit
    padRightLoop(targetLen, u, s)
  }

fun padRightLoop(targetLen: Int, unit: String, cur: String): String =
  if (length(cur) >= targetLen) cur else padRightLoop(targetLen, unit, "${cur}${unit}")

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

export fun trimLeft(s: String): String =
  slice(s, trimLeftIdx(s, 0), length(s))

export fun trimRight(s: String): String =
  slice(s, 0, trimRightIdx(s, length(s)))

export fun fromChar(c: Char): String =
  charStr(c)

export fun cons(c: Char, s: String): String =
  append(fromChar(c), s)

fun revChars(xs: List<Char>, acc: List<Char>): List<Char> =
  match (xs) {
    [] =>
      acc,
    h :: t =>
      revChars(t, h :: acc)
  }

export fun toList(s: String): List<Char> =
  toListLoop(s, 0, length(s), [])

fun toListLoop(s: String, i: Int, n: Int, acc: List<Char>): List<Char> =
  if (i >= n) revChars(acc, []) else toListLoop(s, i + 1, n, charAt(s, i) :: acc)

export fun fromList(cs: List<Char>): String =
  match (cs) {
    [] =>
      "",
    h :: t =>
      append(fromChar(h), fromList(t))
  }

export fun anyChar(s: String, pred: Char -> Bool): Bool =
  anyCharLoop(s, 0, length(s), pred)

fun anyCharLoop(s: String, i: Int, n: Int, pred: Char -> Bool): Bool =
  if (i >= n) False else if (pred(charAt(s, i))) True else anyCharLoop(s, i + 1, n, pred)

export fun allChars(s: String, pred: Char -> Bool): Bool =
  allCharLoop(s, 0, length(s), pred)

fun allCharLoop(s: String, i: Int, n: Int, pred: Char -> Bool): Bool =
  if (i >= n) True else if (!pred(charAt(s, i))) False else allCharLoop(s, i + 1, n, pred)
