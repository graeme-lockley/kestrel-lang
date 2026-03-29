import { Suite, group, eq, isTrue, isFalse } from "kestrel:test"
import { equals as stringEquals } from "kestrel:string"
import {
  codePoint,
  toCode,
  fromCode,
  charToInt,
  intToChar,
  charToString,
  isDigit,
  isUpper,
  isLower,
  isAlpha,
  isAlphaNum,
  isOctDigit,
  isHexDigit,
  toUpper,
  toLower
} from "kestrel:char"

export fun run(s: Suite): Unit =
  group(s, "char", (s1: Suite) => {
    group(s1, "codePoint toCode", (sg: Suite) => {
      eq(sg, "A", codePoint('A'), 65)
      eq(sg, "toCode Z", toCode('Z'), 90)
    })

    group(s1, "fromCode intToChar charToInt", (sg: Suite) => {
      eq(sg, "65 is A", codePoint(fromCode(65)), 65)
      eq(sg, "intToChar alias", codePoint(intToChar(66)), 66)
      eq(sg, "charToInt alias", charToInt('C'), 67)
      eq(sg, "surrogate 0", codePoint(fromCode(0xD800)), 0)
      eq(sg, "negative 0", codePoint(fromCode(-1)), 0)
    })

    group(s1, "charToString", (sg: Suite) => {
      isTrue(sg, "A one char", stringEquals(charToString('A'), "A"))
      isTrue(sg, "emoji one char", stringEquals(charToString('\u{1F600}'), "\u{1F600}"))
    })

    group(s1, "isDigit", (sg: Suite) => {
      isTrue(sg, "zero", isDigit('0'))
      isTrue(sg, "nine", isDigit('9'))
      isFalse(sg, "letter", isDigit('a'))
      isFalse(sg, "space", isDigit(' '))
    })

    group(s1, "isUpper isLower", (sg: Suite) => {
      isTrue(sg, "A upper", isUpper('A'))
      isTrue(sg, "Z upper", isUpper('Z'))
      isFalse(sg, "a not upper", isUpper('a'))
      isTrue(sg, "a lower", isLower('a'))
      isTrue(sg, "z lower", isLower('z'))
      isFalse(sg, "A not lower", isLower('A'))
    })

    group(s1, "isAlpha isAlphaNum", (sg: Suite) => {
      isFalse(sg, "space not alpha", isAlpha(' '))
      isFalse(sg, "digit not alpha", isAlpha('5'))
      isTrue(sg, "A alpha", isAlpha('A'))
      isTrue(sg, "5 alnum", isAlphaNum('5'))
      isTrue(sg, "b alnum", isAlphaNum('b'))
    })

    group(s1, "isOctDigit", (sg: Suite) => {
      isTrue(sg, "7", isOctDigit('7'))
      isFalse(sg, "8", isOctDigit('8'))
    })

    group(s1, "isHexDigit", (sg: Suite) => {
      isTrue(sg, "f", isHexDigit('f'))
      isTrue(sg, "F", isHexDigit('F'))
      isFalse(sg, "g", isHexDigit('g'))
    })

    group(s1, "toUpper toLower", (sg: Suite) => {
      eq(sg, "lower a", codePoint(toUpper('a')), 65)
      eq(sg, "upper A lower", codePoint(toLower('A')), 97)
      eq(sg, "non-alpha unchanged", codePoint(toUpper('5')), 53)
    })
  })
