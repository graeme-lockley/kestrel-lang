import { Suite, group, eq } from "kestrel:test"
import { isDigit } from "kestrel:char"
import * as List from "kestrel:list"
import {
  length,
  slice,
  sliceRel,
  left,
  right,
  dropLeft,
  dropRight,
  indexOf,
  equals,
  toUpperCase,
  toUpper,
  toLowerCase,
  toLower,
  trim,
  trimLeft,
  trimRight,
  isEmpty,
  codePointAt,
  parseInt,
  toInt,
  fromInt,
  split,
  splitWithDelimiters,
  join,
  append,
  concat,
  reverse,
  replace,
  repeat,
  lines,
  words,
  contains,
  startsWith,
  endsWith,
  indexes,
  indices,
  mapChars,
  filterChars,
  padLeft,
  padRight,
  pad,
  fromChar,
  cons,
  fromList,
  toList,
  anyChar,
  allChars
} from "kestrel:string"

export fun run(s: Suite): Unit =
  group(s, "string", (s1: Suite) => {
    group(s1, "length", (sg: Suite) => {
      eq(sg, "empty", length(""), 0)
      eq(sg, "short", length("hi"), 2)
      eq(sg, "multi-word", length("hello world"), 11)
      eq(sg, "single e-acute", length("\u{00E9}"), 1)
      eq(sg, "emoji", length("\u{1F600}"), 1)
      eq(sg, "cafe combining", length("cafe\u{0301}"), 5)
    })

    group(s1, "slice", (sg: Suite) => {
      eq(sg, "beginning", slice("hello", 0, 2), "he")
      eq(sg, "middle", slice("hello", 1, 4), "ell")
      eq(sg, "full", slice("ab", 0, 2), "ab")
      eq(sg, "empty slice", slice("x", 1, 1), "")
      eq(sg, "empty string", slice("", 0, 0), "")
      eq(sg, "start past end empty", slice("ab", 2, 2), "")
      eq(sg, "emoji at start", slice("\u{1F600}ab", 0, 1), "\u{1F600}")
      eq(sg, "after e-acute", slice("\u{00E9}bc", 1, 3), "bc")
    })

    group(s1, "left", (sg: Suite) => {
      eq(sg, "prefix", left("hello", 2), "he")
      eq(sg, "whole when n large", left("ab", 5), "ab")
      eq(sg, "zero n", left("ab", 0), "")
      eq(sg, "negative n", left("ab", 0 - 1), "")
      eq(sg, "emoji", left("\u{1F600}yz", 2), "\u{1F600}y")
    })

    group(s1, "right", (sg: Suite) => {
      eq(sg, "suffix", right("hello", 2), "lo")
      eq(sg, "whole when n large", right("ab", 5), "ab")
      eq(sg, "zero n", right("ab", 0), "")
      eq(sg, "emoji", right("a\u{1F600}", 1), "\u{1F600}")
    })

    group(s1, "dropLeft", (sg: Suite) => {
      eq(sg, "one", dropLeft("hello", 1), "ello")
      eq(sg, "zero", dropLeft("ab", 0), "ab")
      eq(sg, "negative", dropLeft("ab", 0 - 1), "ab")
      eq(sg, "all", dropLeft("ab", 2), "")
      eq(sg, "more than length", dropLeft("ab", 9), "")
      eq(sg, "emoji", dropLeft("\u{1F600}bc", 1), "bc")
    })

    group(s1, "dropRight", (sg: Suite) => {
      eq(sg, "one", dropRight("hello", 1), "hell")
      eq(sg, "zero", dropRight("ab", 0), "ab")
      eq(sg, "all", dropRight("ab", 2), "")
      eq(sg, "emoji", dropRight("a\u{1F600}", 1), "a")
    })

    group(s1, "dropLeft dropRight pipeline", (sg: Suite) => {
      eq(sg, "peel brackets", "[*][%]" |> dropLeft(1) |> dropRight(1) |> split("]["), ["*", "%"])
    })

    group(s1, "indexOf", (sg: Suite) => {
      eq(sg, "found", indexOf("hello", "ll"), 2)
      eq(sg, "not found", indexOf("hello", "z"), 0 - 1)
      eq(sg, "at start", indexOf("hello", "he"), 0)
      eq(sg, "emoji char index", indexOf("a\u{1F600}b", "\u{1F600}"), 1)
    })

    group(s1, "equals", (sg: Suite) => {
      eq(sg, "same", equals("a", "a"), True)
      eq(sg, "different", equals("a", "b"), False)
      eq(sg, "empty", equals("", ""), True)
    })
    
    group(s1, "toUpperCase", (sg: Suite) => {
      eq(sg, "lowercase", toUpperCase("hello"), "HELLO")
      eq(sg, "mixed", toUpperCase("HeLLo"), "HELLO")
      eq(sg, "empty", toUpperCase(""), "")
      eq(sg, "e-acute", toUpperCase("\u{00E9}"), "\u{00C9}")
    })

    group(s1, "trim", (sg: Suite) => {
      eq(sg, "spaces", trim("  ab  "), "ab")
      eq(sg, "already tight", trim("x"), "x")
      eq(sg, "empty", trim(""), "")
      eq(sg, "only ws", trim(" \t\n"), "")
    })

    group(s1, "isEmpty", (sg: Suite) => {
      eq(sg, "empty", isEmpty(""), True)
      eq(sg, "non-empty", isEmpty("x"), False)
    })

    group(s1, "codePointAt", (sg: Suite) => {
      eq(sg, "a", codePointAt("a", 0), 97)
      eq(sg, "oob", codePointAt("a", 1), 0 - 1)
      eq(sg, "emoji", codePointAt("\u{1F600}", 0), 128512)
    })

    group(s1, "parseInt", (sg: Suite) => {
      eq(sg, "zero", parseInt("0"), 0)
      eq(sg, "positive", parseInt("42"), 42)
      eq(sg, "negative", parseInt("-7"), 0 - 7)
      eq(sg, "trimmed", parseInt("  9  "), 9)
      eq(sg, "invalid", parseInt("12a3"), 0)
      eq(sg, "empty after trim", parseInt("   "), 0)
      eq(sg, "lone minus", parseInt("-"), 0)
    })

    group(s1, "split", (sg: Suite) => {
      eq(sg, "csv", split("a,b,c", ","), ["a", "b", "c"])
      eq(sg, "empty delim", split("abc", ""), ["abc"])
      eq(sg, "empty string join", join(",", split("", ",")), "")
      eq(sg, "no delim", split("abc", ","), ["abc"])
      eq(sg, "consecutive delim", split("a,,b", ","), ["a", "", "b"])
      eq(sg, "trailing delim", split("a,b,", ","), ["a", "b", ""])
      eq(sg, "leading delim", split(",a", ","), ["", "a"])
    })

    group(s1, "splitWithDelimiters", (sg: Suite) => {
      eq(sg, "two singles", splitWithDelimiters("1*2%3", ["*", "%"]), ["1", "2", "3"])
      eq(sg, "multi-char", splitWithDelimiters("x##y", ["##"]), ["x", "y"])
      eq(sg, "empty string join", join("|", splitWithDelimiters("", ["*"])), "")
      eq(sg, "no match", splitWithDelimiters("abc", ["*"]), ["abc"])
    })

    group(s1, "join", (sg: Suite) => {
      eq(sg, "csv", join(",", ["a", "b", "c"]), "a,b,c")
      eq(sg, "empty parts", join(",", []), "")
      eq(sg, "single", join(",", ["only"]), "only")
    })

    group(s1, "sliceRel", (sg: Suite) => {
      eq(sg, "negative end", sliceRel(0, 0 - 1, "ab"), "a")
      eq(sg, "clamp", sliceRel(0, 99, "x"), "x")
      eq(sg, "negative end three", sliceRel(0, 0 - 1, "abc"), "ab")
      eq(sg, "inverted empty", sliceRel(2, 0, "ab"), "")
      eq(sg, "empty string", sliceRel(0, 0, ""), "")
    })

    group(s1, "toLowerCase", (sg: Suite) => {
      eq(sg, "upper", toLowerCase("HELLO"), "hello")
      eq(sg, "mixed", toLowerCase("HeLLo"), "hello")
      eq(sg, "empty", toLowerCase(""), "")
      eq(sg, "alias toLower", toLower("Ab"), toLowerCase("Ab"))
    })

    group(s1, "toUpper alias", (sg: Suite) => {
      eq(sg, "toUpper", toUpper("aBc"), toUpperCase("aBc"))
    })

    group(s1, "trim sides", (sg: Suite) => {
      eq(sg, "left", trimLeft("  ab"), "ab")
      eq(sg, "right", trimRight("ab  "), "ab")
    })

    group(s1, "toInt fromInt", (sg: Suite) => {
      eq(sg, "ok", toInt("42"), Some(42))
      eq(sg, "none bad", toInt("12a"), None)
      eq(sg, "fromInt", fromInt(7), "7")
      eq(sg, "zero", toInt("0"), Some(0))
      eq(sg, "negative", toInt("-3"), Some(0 - 3))
      eq(sg, "empty", toInt(""), None)
      eq(sg, "lone minus", toInt("-"), None)
      eq(sg, "fromInt negative", fromInt(0 - 1), "-1")
    })

    group(s1, "append concat reverse replace", (sg: Suite) => {
      eq(sg, "append", append("a", "b"), "ab")
      eq(sg, "concat", concat(["a", "b", "c"]), "abc")
      eq(sg, "concat empty", concat([]), "")
      eq(sg, "reverse", reverse("ab"), "ba")
      eq(sg, "reverse empty", reverse(""), "")
      eq(sg, "replace", replace(",", ".", "a,b"), "a.b")
      eq(sg, "replace all", replace("x", "yy", "axb"), "ayyb")
      eq(sg, "replace no match", replace("z", "q", "ab"), "ab")
      eq(sg, "replace empty before", replace("", "z", "ab"), "ab")
    })

    group(s1, "repeat", (sg: Suite) => {
      eq(sg, "zero", repeat(0, "a"), "")
      eq(sg, "three", repeat(3, "*"), "***")
      eq(sg, "empty chunk", repeat(2, ""), "")
    })

    group(s1, "words", (sg: Suite) => {
      eq(sg, "trimmed runs", words("  hi  world  "), ["hi", "world"])
      eq(sg, "empty", words(""), [])
      eq(sg, "single", words("x"), ["x"])
      eq(sg, "tabs newlines", words("a\tb\nc"), ["a", "b", "c"])
    })

    group(s1, "lines words edge", (sg: Suite) => {
      eq(sg, "lines empty join", join("|", lines("")), "")
      eq(sg, "lines trailing nl", lines("a\n"), ["a", ""])
    })

    group(s1, "indexes indices", (sg: Suite) => {
      eq(sg, "none length", List.length(indexes("z", "abc")), 0)
      eq(sg, "single", indexes("b", "abc"), [1])
      eq(sg, "empty needle length", List.length(indexes("", "abc")), 0)
      eq(sg, "indices alias", indices("a", "aba"), indexes("a", "aba"))
    })

    group(s1, "lines contains starts ends", (sg: Suite) => {
      eq(sg, "lines", lines("a\nb"), ["a", "b"])
      eq(sg, "contains", contains("ll", "hello"), True)
      eq(sg, "not contains", contains("z", "hello"), False)
      eq(sg, "startsWith", startsWith("he", "hello"), True)
      eq(sg, "starts too long", startsWith("hello!", "hi"), False)
      eq(sg, "endsWith", endsWith("lo", "hello"), True)
      eq(sg, "ends mismatch", endsWith("x", "hello"), False)
    })

    group(s1, "indexes", (sg: Suite) => {
      eq(sg, "overlap", indexes("aa", "aaa"), [0, 1])
    })

    group(s1, "fromList toList roundtrip", (sg: Suite) => {
      eq(sg, "roundtrip", fromList(toList("hi")), "hi")
      eq(sg, "empty", fromList(toList("")), "")
      eq(sg, "emoji", fromList(toList("\u{1F600}")), "\u{1F600}")
    })

    group(s1, "mapChars filterChars", (sg: Suite) => {
      eq(sg, "map identity", mapChars("ab", (c: Char) => c), "ab")
      eq(sg, "map empty", mapChars("", (c: Char) => c), "")
      eq(sg, "filter digits", filterChars("a1b2c", isDigit), "12")
      eq(sg, "filter none", filterChars("abc", isDigit), "")
    })

    group(s1, "pad", (sg: Suite) => {
      eq(sg, "padLeft", padLeft(5, "-", "ab"), "---ab")
      eq(sg, "padRight", padRight(5, "-", "ab"), "ab---")
      eq(sg, "padLeft empty unit uses space", padLeft(3, "", "x"), "  x")
      eq(sg, "pad center even", pad(6, "-", "ab"), "--ab--")
      eq(sg, "pad already long", pad(2, ".", "hello"), "hello")
    })

    group(s1, "fromChar cons", (sg: Suite) => {
      eq(sg, "fromChar", fromChar('z'), "z")
      eq(sg, "cons", cons('x', "yz"), "xyz")
    })

    group(s1, "anyChar allChars", (sg: Suite) => {
      eq(sg, "any false", anyChar("abc", isDigit), False)
      eq(sg, "any true", anyChar("a1", isDigit), True)
      eq(sg, "any empty", anyChar("", isDigit), False)
      eq(sg, "all true", allChars("12", isDigit), True)
      eq(sg, "all false", allChars("1a", isDigit), False)
      eq(sg, "all empty", allChars("", isDigit), True)
    })
  })
