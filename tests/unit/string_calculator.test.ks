import { Suite, group, eq } from "kestrel:test"
import { slice, left, right, dropLeft, dropRight, indexOf, split, splitWithDelimiters, parseInt } from "kestrel:string"
import { isEmpty, map, filter, sum } from "kestrel:list"

/** Spec after `//`: either one literal (e.g. `;`) or `[a][b]...` — peel outer `[`/`]`, split inners on `][`. */
fun parseDelimitersFromHeader(spec: String): List<String> =
  if (left(spec, 1) == "[" & right(spec, 1) == "]")
    spec |> dropLeft(1) |> dropRight(1) |> split("][")
  else 
    [spec]

fun addCore(numbersPart: String, delims: List<String>): Result<Int, List<Int>> = {
  val numbers = splitWithDelimiters(numbersPart, delims) |> map(parseInt)
  val negatives = numbers |> filter((n) => n < 0)

  if (isEmpty(negatives)) 
    Ok(sum(numbers))
  else 
    Err(negatives)
}

export fun add(input: String): Result<Int, List<Int>> =
  if (input == "") 
    Ok(0)
  else {
    val newlineIdx = indexOf(input, "\n")
    val hasHeader = newlineIdx > 1 & left(input, 2) == "//"

    if (hasHeader) {
      val delims = input |> slice(2, newlineIdx) |> parseDelimitersFromHeader
      val numbersPart = input|> dropLeft(newlineIdx + 1)

      addCore(numbersPart, delims)
    } else 
      addCore(input, [",", "\n"])
  }

export async fun run(s: Suite): Task<Unit> =
  group(s, "string calculator", (s1: Suite) => {
    eq(s1, "empty string", add(""), Ok(0))
    eq(s1, "single number", add("5"), Ok(5))
    eq(s1, "comma delimited", add("1,2,3"), Ok(6))
    eq(s1, "newline delimited", add("1\n2\n3"), Ok(6))
    eq(s1, "comma + newline mixed", add("1\n2,3"), Ok(6))

    group(s1, "custom delimiters", (cd: Suite) => {
      eq(cd, "single char delimiter", add("//;\n1;2"), Ok(3))
      eq(cd, "multi-char delimiter", add("//[***]\n1***2***3"), Ok(6))
      eq(cd, "multiple bracket groups", add("//[*][%]\n1*2%3"), Ok(6))
    })

    group(s1, "negative numbers", (nn: Suite) => {
      eq(nn, "negatives listed in order", add("-1,2,-3"), Err([-1, -3]))
      eq(nn, "negatives with custom delimiter", add("//;\n-5;-1"), Err([-5, -1]))
    })
  })
