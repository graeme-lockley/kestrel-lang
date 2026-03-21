// kestrel:string — spec 02 primitives plus trim, codePointAt, parseInt, split, join, splitWithDelimiters.

export fun length(s: String): Int = __string_length(s)
export fun slice(s: String, start: Int, end: Int): String = __string_slice(s, start, end)
export fun indexOf(s: String, sub: String): Int = __string_index_of(s, sub)
export fun equals(a: String, b: String): Bool = __string_equals(a, b)
export fun toUpperCase(s: String): String = __string_upper(s)

export fun trim(s: String): String = __string_trim(s)

/** True if `s` has no characters (after UTF-8 decoding, i.e. code point count is zero). */
export fun isEmpty(s: String): Bool = length(s) == 0

/** Unicode code point at code-point index `i`, or `-1` if `i` is out of range. */
export fun codePointAt(s: String, i: Int): Int = __string_code_point_at(s, i)

fun parseUnsignedAll(t: String, i: Int, acc: Int): Int =
  if (i >= length(t)) acc
  else {
    val cp = codePointAt(t, i)
    if (cp >= 48 & cp <= 57) parseUnsignedAll(t, i + 1, acc * 10 + (cp - 48))
    else 0
  }

/**
 * Parse a signed decimal integer from `s`. Leading/trailing ASCII whitespace is ignored.
 * Optional leading `-` for negative values. Non-conforming content yields `0`.
 */
export fun parseInt(s: String): Int = {
  val t = trim(s)
  if (length(t) == 0) 0
  else if (equals(slice(t, 0, 1), "-") & length(t) > 1) 0 - parseUnsignedAll(t, 1, 0)
  else parseUnsignedAll(t, 0, 0)
}

/** Split `s` into segments separated by `delim`. Empty `delim` returns `[s]`. */
export fun split(s: String, delim: String): List<String> =
  if (length(delim) == 0) [s]
  else splitAcc(s, delim, 0, 0)

fun splitAcc(s: String, delim: String, start: Int, fromIdx: Int): List<String> = {
  val tailStr = slice(s, fromIdx, length(s))
  val rel = indexOf(tailStr, delim)
  if (rel < 0) [slice(s, start, length(s))]
  else {
    val pos = fromIdx + rel
    slice(s, start, pos) :: splitAcc(s, delim, pos + length(delim), pos + length(delim))
  }
}

fun matchDelimiterAt(s: String, delims: List<String>, i: Int): Int = match (delims) {
  [] => 0
  d :: rest => {
    val dLen = length(d)
    if (equals(slice(s, i, i + dLen), d)) dLen else matchDelimiterAt(s, rest, i)
  }
}

fun splitWithDelimsLoop(s: String, delims: List<String>, idx: Int, tokenStart: Int): List<String> =
  if (idx >= length(s)) [slice(s, tokenStart, length(s))]
  else {
    val dLen = matchDelimiterAt(s, delims, idx)
    if (dLen > 0)
      slice(s, tokenStart, idx) :: splitWithDelimsLoop(s, delims, idx + dLen, idx + dLen)
    else splitWithDelimsLoop(s, delims, idx + 1, tokenStart)
  }

/**
 * Split `s` at the first matching delimiter in `delims` at each boundary (longest match among
 * candidates at each position). Delimiters are tried in list order.
 */
export fun splitWithDelimiters(s: String, delims: List<String>): List<String> =
  splitWithDelimsLoop(s, delims, 0, 0)

/** Concatenate `parts` with `sep` between elements. */
export fun join(sep: String, parts: List<String>): String = match (parts) {
  [] => ""
  h :: t =>
    match (t) {
      [] => h
      _ => "${h}${sep}${join(sep, t)}"
    }
}
