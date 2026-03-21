import { Suite, group, eq } from "kestrel:test"
import { length, slice, indexOf, equals, splitWithDelimiters, parseInt, join } from "kestrel:string"
import { isEmpty, map, filter, foldl } from "kestrel:list"

fun isNegative(n: Int): Bool = n < 0
fun intToString(n: Int): String = "${n}"
fun sumAcc(acc: Int, x: Int): Int = acc + x

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

fun addCore(numbersPart: String, delims: List<String>): Int = {
  val tokens = splitWithDelimiters(numbersPart, delims)
  val numbers = map(tokens, parseInt)
  val negatives = filter(numbers, isNegative)

  if (isEmpty(negatives)) foldl(numbers, 0, sumAcc)
  else {
    val negStrings = map(negatives, intToString)
    val msg = "negatives not allowed: ${join(",", negStrings)}"
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
