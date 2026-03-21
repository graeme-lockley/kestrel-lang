import { Suite, group, eq } from "kestrel:test"
import { length, slice, indexOf, equals } from "kestrel:string"
import { isEmpty } from "kestrel:list"

// Convert a single ASCII digit character to an Int (assumes valid input).
fun digitCharToInt(ch: String): Int =
  if (equals(ch, "0")) 0
  else if (equals(ch, "1")) 1
  else if (equals(ch, "2")) 2
  else if (equals(ch, "3")) 3
  else if (equals(ch, "4")) 4
  else if (equals(ch, "5")) 5
  else if (equals(ch, "6")) 6
  else if (equals(ch, "7")) 7
  else if (equals(ch, "8")) 8
  else if (equals(ch, "9")) 9
  else 0

fun parseDigits(s: String, idx: Int, acc: Int): Int =
  if (idx >= length(s)) acc
  else {
    val digitStr = slice(s, idx, idx + 1)
    parseDigits(s, idx + 1, acc * 10 + digitCharToInt(digitStr))
  }

fun parseIntToken(tok: String): Int =
  if (length(tok) == 0) 0
  else if (equals(slice(tok, 0, 1), "-")) 0 - parseDigits(tok, 1, 0)
  else parseDigits(tok, 0, 0)

fun reverseInts(xs: List<Int>, acc: List<Int>): List<Int> = match (xs) {
  [] => acc
  h :: t => reverseInts(t, h :: acc)
}

fun joinInts(xs: List<Int>): String = match (xs) {
  [] => ""
  h :: t => if (isEmpty(t)) "${h}" else "${h},${joinInts(t)}"
}

fun parseBracketDelims(spec: String, idx: Int): List<String> =
  if (idx >= length(spec)) []
  else if (equals(slice(spec, idx, idx + 1), "[")) {
    val rest = slice(spec, idx, length(spec))
    val closeRel = indexOf(rest, "]")
    if (closeRel < 0) [spec]
    else {
      val closeAbs = idx + closeRel
      val delim = slice(spec, idx + 1, closeAbs)
      delim :: parseBracketDelims(spec, closeAbs + 1)
    }
  } else parseBracketDelims(spec, idx + 1)

fun parseDelimitersFromHeader(spec: String): List<String> =
  if (length(spec) > 0 & equals(slice(spec, 0, 1), "[")) parseBracketDelims(spec, 0)
  else [spec]

fun matchDelimiterAt(s: String, delims: List<String>, i: Int): Int = match (delims) {
  [] => 0
  d :: rest => {
    val dLen = length(d)
    if (equals(slice(s, i, i + dLen), d)) dLen else matchDelimiterAt(s, rest, i)
  }
}

fun finalizeToken(tok: String, sum: Int, negativesRev: List<Int>): (Int * List<Int>) =
  if (length(tok) == 0) (sum, negativesRev)
  else {
    val n = parseIntToken(tok)
    if (n < 0) (sum, n :: negativesRev) else (sum + n, negativesRev)
  }

fun scanAndAccumulate(
  s: String,
  delims: List<String>,
  idx: Int,
  tokenStart: Int,
  sum: Int,
  negativesRev: List<Int>
): (Int * List<Int>) =
  if (idx >= length(s)) {
    val tok = slice(s, tokenStart, length(s))
    finalizeToken(tok, sum, negativesRev)
  } else {
    val dLen = matchDelimiterAt(s, delims, idx)
    if (dLen > 0) {
      val tok = slice(s, tokenStart, idx)
      val done = finalizeToken(tok, sum, negativesRev)
      scanAndAccumulate(s, delims, idx + dLen, idx + dLen, done.0, done.1)
    } else scanAndAccumulate(s, delims, idx + 1, tokenStart, sum, negativesRev)
  }

fun addCore(numbersPart: String, delims: List<String>): Int = {
  val scanned = scanAndAccumulate(numbersPart, delims, 0, 0, 0, [])
  val sum = scanned.0
  val negativesRev = scanned.1
  if (isEmpty(negativesRev)) sum
  else {
    val negatives = reverseInts(negativesRev, [])
    val msg = "negatives not allowed: ${joinInts(negatives)}"
    // Throwing the message payload is type-checked as a bottom value, while
    // callers can catch and map it into a richer result type if needed.
    throw msg
  }
}

export fun add(input: String): Int = {
  if (length(input) == 0) 0
  else {
    val newlineIdx = indexOf(input, "\n")
    val hasHeader = newlineIdx > 1 & slice(input, 0, 2) == "//"

    if (!hasHeader) addCore(input, [",", "\n"])
    else {
      val spec = slice(input, 2, newlineIdx)
      val delims = parseDelimitersFromHeader(spec)
      val numbersPart = slice(input, newlineIdx + 1, length(input))
      addCore(numbersPart, delims)
    }
  }
}

fun addChecked(input: String): Result<Int, String> =
  try { Ok(add(input)) } catch { e => Err(e) }

fun errMessage(r: Result<Int, String>): String = match (r) {
  Err{ value = m } => m
  Ok{ value = _ } => "unexpected: expected Err"
}

export fun run(s: Suite): Unit =
  group(s, "string calculator", (s1: Suite) => {
    eq(s1, "empty string", add(""), 0)
    eq(s1, "single number", add("5"), 5)
    eq(s1, "comma delimited", add("1,2,3"), 6)
    eq(s1, "newline delimited", add("1\n2\n3"), 6)
    eq(s1, "comma + newline mixed", add("1\n2,3"), 6)

    group(s1, "custom delimiters", (cd: Suite) => {
      eq(cd, "single char delimiter", add("//;\n1;2"), 3)
      eq(cd, "multi-char delimiter", add("//[***]\n1***2***3"), 6)
      eq(cd, "multiple bracket groups", add("//[*][%]\n1*2%3"), 6)
    })

    group(s1, "negative numbers", (nn: Suite) => {
      val msg1 = errMessage(addChecked("-1,2,-3"))
      eq(nn, "negatives not allowed message", msg1, "negatives not allowed: -1,-3")

      val msg2 = errMessage(addChecked("//;\n-5;-1"))
      eq(nn, "negatives with custom delimiter", msg2, "negatives not allowed: -5,-1")
    })
  })

