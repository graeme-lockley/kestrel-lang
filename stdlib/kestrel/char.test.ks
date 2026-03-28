import { Suite, group, eq } from "kestrel:test"
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
      eq(sg, "A one char", stringEquals(charToString('A'), "A"), True)
      eq(sg, "emoji one char", stringEquals(charToString('\u{1F600}'), "\u{1F600}"), True)
    })

    group(s1, "isDigit", (sg: Suite) => {
      eq(sg, "zero", isDigit('0'), True)
      eq(sg, "nine", isDigit('9'), True)
      eq(sg, "letter", isDigit('a'), False)
      eq(sg, "space", isDigit(' '), False)
    })

    group(s1, "isUpper isLower", (sg: Suite) => {
      eq(sg, "A upper", isUpper('A'), True)
      eq(sg, "Z upper", isUpper('Z'), True)
      eq(sg, "a not upper", isUpper('a'), False)
      eq(sg, "a lower", isLower('a'), True)
      eq(sg, "z lower", isLower('z'), True)
      eq(sg, "A not lower", isLower('A'), False)
    })

    group(s1, "isAlpha isAlphaNum", (sg: Suite) => {
      eq(sg, "space not alpha", isAlpha(' '), False)
      eq(sg, "digit not alpha", isAlpha('5'), False)
      eq(sg, "A alpha", isAlpha('A'), True)
      eq(sg, "5 alnum", isAlphaNum('5'), True)
      eq(sg, "b alnum", isAlphaNum('b'), True)
    })

    group(s1, "isOctDigit", (sg: Suite) => {
      eq(sg, "7", isOctDigit('7'), True)
      eq(sg, "8", isOctDigit('8'), False)
    })

    group(s1, "isHexDigit", (sg: Suite) => {
      eq(sg, "f", isHexDigit('f'), True)
      eq(sg, "F", isHexDigit('F'), True)
      eq(sg, "g", isHexDigit('g'), False)
    })

    group(s1, "toUpper toLower", (sg: Suite) => {
      eq(sg, "lower a", codePoint(toUpper('a')), 65)
      eq(sg, "upper A lower", codePoint(toLower('A')), 97)
      eq(sg, "non-alpha unchanged", codePoint(toUpper('5')), 53)
    })
  })
