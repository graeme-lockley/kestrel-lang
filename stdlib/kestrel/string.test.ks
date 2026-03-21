import { Suite, group, eq } from "kestrel:test"
import {
  length,
  slice,
  indexOf,
  equals,
  toUpperCase,
  trim,
  isEmpty,
  codePointAt,
  parseInt,
  split,
  splitWithDelimiters,
  join
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
      eq(sg, "emoji at start", slice("\u{1F600}ab", 0, 1), "\u{1F600}")
      eq(sg, "after e-acute", slice("\u{00E9}bc", 1, 3), "bc")
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
    })

    group(s1, "split", (sg: Suite) => {
      eq(sg, "csv", split("a,b,c", ","), ["a", "b", "c"])
      eq(sg, "empty delim", split("abc", ""), ["abc"])
    })

    group(s1, "splitWithDelimiters", (sg: Suite) => {
      eq(sg, "two singles", splitWithDelimiters("1*2%3", ["*", "%"]), ["1", "2", "3"])
      eq(sg, "multi-char", splitWithDelimiters("x##y", ["##"]), ["x", "y"])
    })

    group(s1, "join", (sg: Suite) => {
      eq(sg, "csv", join(",", ["a", "b", "c"]), "a,b,c")
      eq(sg, "empty parts", join(",", []), "")
      eq(sg, "single", join(",", ["only"]), "only")
    })
  })
