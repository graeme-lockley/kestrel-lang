// kestrel:json — JSON Value ADT, parse (Result), stringify (spec 02). Pure Kestrel; no host JSON hooks.

import * as Str from "kestrel:data/string"
import * as List from "kestrel:data/list"
import * as Res from "kestrel:data/result"
import * as Char from "kestrel:data/char"
import * as Basics from "kestrel:data/basics"
import * as Stk from "kestrel:dev/stack"

export type Value = Null | Bool(Bool) | Int(Int) | Float(Float) | StrVal(String) | Array(List<Value>) | Object(List<(String, Value)>)

export type JsonParseError = EmptyInput | UnclosedString(Int) | InvalidEscape(Int) | InvalidUnicodeEscape(Int) | InvalidNumber(Int) | UnclosedArray(Int) | UnclosedObject(Int) | ExpectedColon(Int) | ExpectedCommaOrBracket(Int) | TrailingGarbage(Int) | UnexpectedToken(Int)

export fun errorAsString(e: JsonParseError): String = match (e) {
  EmptyInput => "empty JSON input"
  UnclosedString(i) => Str.append("unclosed string at ", Str.fromInt(i))
  InvalidEscape(i) => Str.append("invalid escape at ", Str.fromInt(i))
  InvalidUnicodeEscape(i) => Str.append("invalid unicode escape at ", Str.fromInt(i))
  InvalidNumber(i) => Str.append("invalid number at ", Str.fromInt(i))
  UnclosedArray(i) => Str.append("unclosed array at ", Str.fromInt(i))
  UnclosedObject(i) => Str.append("unclosed object at ", Str.fromInt(i))
  ExpectedColon(i) => Str.append("expected colon at ", Str.fromInt(i))
  ExpectedCommaOrBracket(i) => Str.append("expected comma or closing bracket at ", Str.fromInt(i))
  TrailingGarbage(i) => Str.append("trailing garbage at ", Str.fromInt(i))
  UnexpectedToken(i) => Str.append("unexpected token at ", Str.fromInt(i))
}

export fun isNull(v: Value): Bool = match (v) {
  Null => True
  _ => False
}
export fun isBool(v: Value): Bool = match (v) {
  Bool(_) => True
  _ => False
}
export fun isInt(v: Value): Bool = match (v) {
  Int(_) => True
  _ => False
}
export fun isFloat(v: Value): Bool = match (v) {
  Float(_) => True
  _ => False
}
export fun isString(v: Value): Bool = match (v) {
  StrVal(_) => True
  _ => False
}
export fun isArray(v: Value): Bool = match (v) {
  Array(_) => True
  _ => False
}
export fun isObject(v: Value): Bool = match (v) {
  Object(_) => True
  _ => False
}

export fun jsonNull(): Value = Null

export fun asInt(v: Value): Option<Int> = match (v) {
  Int(n) => Some(n)
  _ => None
}

export fun asBool(v: Value): Option<Bool> = match (v) {
  Bool(b) => Some(b)
  _ => None
}

export fun asStrVal(v: Value): Option<String> = match (v) {
  StrVal(t) => Some(t)
  _ => None
}

export fun objectPairCount(v: Value): Int = match (v) {
  Object(pairs) => List.length(pairs)
  _ => -1
}

export fun describeParse(s: String): String =
  match (Res.mapError(parse(s), errorAsString)) {
    Ok(_) => "ok"
    Err(smsg) => smsg
  }

export fun regressionErrorMessagesNonEmpty(): Bool =
  Str.length(errorAsString(EmptyInput)) > 0
    & Str.length(errorAsString(UnclosedString(0))) > 0
    & Str.length(errorAsString(InvalidEscape(0))) > 0
    & Str.length(errorAsString(InvalidUnicodeEscape(0))) > 0
    & Str.length(errorAsString(InvalidNumber(0))) > 0
    & Str.length(errorAsString(UnclosedArray(0))) > 0
    & Str.length(errorAsString(UnclosedObject(0))) > 0
    & Str.length(errorAsString(ExpectedColon(0))) > 0
    & Str.length(errorAsString(ExpectedCommaOrBracket(0))) > 0
    & Str.length(errorAsString(TrailingGarbage(0))) > 0
    & Str.length(errorAsString(UnexpectedToken(0))) > 0

fun cpAt(s: String, i: Int): Int =
  if (i >= Str.length(s)) -1 else Str.codePointAt(s, i)

fun skipWs(s: String, i: Int): Int =
  if (i >= Str.length(s)) i
  else {
    val c = Str.codePointAt(s, i)
    if (c == 32 | c == 9 | c == 10 | c == 13) skipWs(s, i + 1) else i
  }

fun hexVal(c: Int): Int =
  if (c >= 48 & c <= 57) c - 48
  else if (c >= 65 & c <= 70) c - 55
  else if (c >= 97 & c <= 102) c - 87
  else -1

fun parseHexDigit(s: String, i: Int): Result<(Int, Int), JsonParseError> =
  if (i >= Str.length(s)) Err(InvalidUnicodeEscape(i))
  else {
    val v = hexVal(Str.codePointAt(s, i))
    if (v < 0) Err(InvalidUnicodeEscape(i)) else Ok((v, i + 1))
  }

fun mergeHex4(a: Int, b: Int, c: Int, d: Int): Int =
  ((a * 16 + b) * 16 + c) * 16 + d

fun parseHex4After1(s: String, i: Int, d0: Int): Result<(Int, Int), JsonParseError> = {
  val r1 = parseHexDigit(s, i)
  match (r1) {
    Err(_) => r1
    Ok(p1) => parseHex4After2(s, p1.1, d0, p1.0)
  }
}

fun parseHex4After2(s: String, i: Int, d0: Int, d1: Int): Result<(Int, Int), JsonParseError> = {
  val r2 = parseHexDigit(s, i)
  match (r2) {
    Err(_) => r2
    Ok(p2) => parseHex4After3(s, p2.1, d0, d1, p2.0)
  }
}

fun parseHex4After3(s: String, i: Int, d0: Int, d1: Int, d2: Int): Result<(Int, Int), JsonParseError> = {
  val r3 = parseHexDigit(s, i)
  match (r3) {
    Err(_) => r3
    Ok(p3) => Ok((mergeHex4(d0, d1, d2, p3.0), p3.1))
  }
}

fun parseHex4(s: String, i: Int): Result<(Int, Int), JsonParseError> = {
  val r0 = parseHexDigit(s, i)
  match (r0) {
    Err(_) => r0
    Ok(p0) => parseHex4After1(s, p0.1, p0.0)
  }
}

fun isHighSurrogate(u: Int): Bool = u >= 55296 & u <= 56319
fun isLowSurrogate(u: Int): Bool = u >= 56320 & u <= 57343

fun combineSurrogate(hi: Int, lo: Int): Int =
  (hi - 55296) * 1024 + (lo - 56320) + 65536

fun appendCodePoint(acc: String, u: Int): String =
  Str.append(acc, Char.charToString(Char.fromCode(u)))

/** After a high surrogate `\uHHHH`, parse optional `\uLLLL` and combine (JSON UTF-16 pair → one scalar). */
fun parseLowSurrogateAfterHigh(s: String, j: Int, hi: Int): Result<(String, Int), JsonParseError> =
  if (j + 1 < Str.length(s) & Str.codePointAt(s, j) == 92 & Str.codePointAt(s, j + 1) == 117) {
    val rl = parseHex4(s, j + 2)
    match (rl) {
      Err(_) => Err(InvalidUnicodeEscape(j))
      Ok(pl) => {
        val loVal = pl.0
        val afterLow = pl.1
        if (isLowSurrogate(loVal)) {
          val cp = combineSurrogate(hi, loVal)
          if (cp > 1114111) Err(InvalidUnicodeEscape(j)) else Ok((appendCodePoint("", cp), afterLow))
        } else Err(InvalidUnicodeEscape(j))
      }
    }
  } else Err(InvalidUnicodeEscape(j))

fun parseUnicodeEscape(s: String, i: Int): Result<(String, Int), JsonParseError> =
  if (i >= Str.length(s) | Str.codePointAt(s, i) != 117) Err(InvalidUnicodeEscape(i))
  else {
    val rh = parseHex4(s, i + 1)
    match (rh) {
      Err(_) => Err(InvalidUnicodeEscape(i + 1))
      Ok(pu) => {
        val u = pu.0
        val j = pu.1
        if (isHighSurrogate(u)) parseLowSurrogateAfterHigh(s, j, u)
        else {
          if (isLowSurrogate(u)) Err(InvalidUnicodeEscape(i + 1))
          else Ok((appendCodePoint("", u), j))
        }
      }
    }
  }

fun parseStrChar(s: String, i: Int, acc: String): Result<(String, Int), JsonParseError> =
  if (i >= Str.length(s)) Err(UnclosedString(i))
  else {
    val c = Str.codePointAt(s, i)
    if (c == 34) Ok((acc, i + 1))
    else if (c == 92) {
      if (i + 1 >= Str.length(s)) Err(UnclosedString(i))
      else {
        val e = Str.codePointAt(s, i + 1)
        if (e == 34) parseStrChar(s, i + 2, Str.append(acc, "\""))
        else if (e == 92) parseStrChar(s, i + 2, Str.append(acc, "\\"))
        else if (e == 47) parseStrChar(s, i + 2, Str.append(acc, "/"))
        else if (e == 98) parseStrChar(s, i + 2, Str.append(acc, Char.charToString(Char.fromCode(8))))
        else if (e == 102) parseStrChar(s, i + 2, Str.append(acc, Char.charToString(Char.fromCode(12))))
        else if (e == 110) parseStrChar(s, i + 2, Str.append(acc, Char.charToString(Char.fromCode(10))))
        else if (e == 114) parseStrChar(s, i + 2, Str.append(acc, Char.charToString(Char.fromCode(13))))
        else if (e == 116) parseStrChar(s, i + 2, Str.append(acc, Char.charToString(Char.fromCode(9))))
        else if (e == 117) {
          val ru = parseUnicodeEscape(s, i + 1)
          match (ru) {
            Err(_) => ru
            Ok(pr) => parseStrChar(s, pr.1, Str.append(acc, pr.0))
          }
        }
        else Err(InvalidEscape(i + 1))
      }
    } else parseStrChar(s, i + 1, Str.append(acc, Char.charToString(Char.fromCode(c))))
  }

fun mkStrVal(s: String): Value = StrVal(s)

fun pairStr(t: (String, Int)): String = t.0

fun pairIdx(t: (String, Int)): Int = t.1

fun strToValResult(t: (String, Int)): Result<(Value, Int), JsonParseError> =
  Ok((mkStrVal(pairStr(t)), pairIdx(t)))

fun parseStringValue(s: String, i: Int): Result<(Value, Int), JsonParseError> =
  if (i >= Str.length(s) | Str.codePointAt(s, i) != 34) Err(UnexpectedToken(i))
  else Res.andThen(parseStrChar(s, i + 1, ""), strToValResult)

fun readDigits(s: String, i: Int, acc: Int): (Int, Int) =
  if (i >= Str.length(s)) (acc, i)
  else {
    val c = Str.codePointAt(s, i)
    if (c >= 48 & c <= 57) readDigits(s, i + 1, acc * 10 + (c - 48))
    else (acc, i)
  }

fun readExpSign(s: String, i: Int): (Int, Int) =
  if (i < Str.length(s) & Str.codePointAt(s, i) == 45) (-1, i + 1)
  else if (i < Str.length(s) & Str.codePointAt(s, i) == 43) (1, i + 1)
  else (1, i)

fun pow10f(n: Int): Float =
  if (n <= 0) 1.0 else 10.0 * pow10f(n - 1)

fun pow10fSigned(exp: Int): Float =
  if (exp >= 0) pow10f(exp) else 1.0 / pow10f(0 - exp)

fun scaleFrac(frac: Int, places: Int): Float =
  if (places <= 0) Basics.toFloat(frac)
  else Basics.toFloat(frac) / pow10f(places)

fun parseNumberValue(s: String, i: Int): Result<(Value, Int), JsonParseError> = {
  val len = Str.length(s)
  fun go(j: Int, neg: Int): Result<(Value, Int), JsonParseError> =
    if (j >= len) Err(InvalidNumber(j))
    else {
      val c0 = Str.codePointAt(s, j)
      if (c0 == 45) {
        if (j + 1 >= len) Err(InvalidNumber(j))
        else go(j + 1, -1)
      } else {
        val n0 = j
        val c = Str.codePointAt(s, j)
        if (c == 48) {
          val after0 = j + 1
          if (after0 < len) {
            val c1 = Str.codePointAt(s, after0)
            if (c1 >= 48 & c1 <= 57) Err(InvalidNumber(after0))
            else if (c1 == 46) {
              val fr = readDigits(s, after0 + 1, 0)
              val fd = fr.0
              val k = fr.1
              val fval = Basics.toFloat(neg) * scaleFrac(fd, k - (after0 + 1))
              if (k < len & (Str.codePointAt(s, k) == 101 | Str.codePointAt(s, k) == 69)) {
                val es = readExpSign(s, k + 1)
                val esg = es.0
                val ek = es.1
                val er = readDigits(s, ek, 0)
                if (er.1 == ek) Err(InvalidNumber(ek))
                else {
                  val expv = esg * er.0
                  Ok((Float(fval * pow10fSigned(expv)), er.1))
                }
              } else Ok((Float(fval), k))
            } else if (c1 == 101 | c1 == 69) {
              val es = readExpSign(s, after0 + 1)
              val er = readDigits(s, es.1, 0)
              if (er.1 == es.1) Err(InvalidNumber(es.1))
              else Ok((Float(0.0 * pow10fSigned(es.0 * er.0)), er.1))
            } else Ok((Int(0), after0))
          } else Ok((Int(0), after0))
        } else if (c >= 48 & c <= 57) {
          val ir = readDigits(s, j, 0)
          val intv = ir.0
          val k = ir.1
          if (k < len & Str.codePointAt(s, k) == 46) {
            val fr = readDigits(s, k + 1, 0)
            val fd = fr.0
            val m = fr.1
            val fbase = Basics.toFloat(neg * intv) + scaleFrac(fd, m - (k + 1))
            if (m < len & (Str.codePointAt(s, m) == 101 | Str.codePointAt(s, m) == 69)) {
              val es = readExpSign(s, m + 1)
              val er = readDigits(s, es.1, 0)
              if (er.1 == es.1) Err(InvalidNumber(es.1))
              else Ok((Float(fbase * pow10fSigned(es.0 * er.0)), er.1))
            } else Ok((Float(fbase), m))
          } else if (k < len & (Str.codePointAt(s, k) == 101 | Str.codePointAt(s, k) == 69)) {
            val es = readExpSign(s, k + 1)
            val er = readDigits(s, es.1, 0)
            if (er.1 == es.1) Err(InvalidNumber(es.1))
            else Ok((Float(Basics.toFloat(neg * intv) * pow10fSigned(es.0 * er.0)), er.1))
          } else Ok((Int(neg * intv), k))
        } else Err(InvalidNumber(j))
      }
    }
  go(i, 1)
}

fun withoutKey(pairs: List<(String, Value)>, k: String): List<(String, Value)> =
  match (pairs) {
    [] => []
    h :: t => if (Str.equals(h.0, k)) withoutKey(t, k) else h :: withoutKey(t, k)
  }

fun addKey(pairs: List<(String, Value)>, k: String, v: Value): List<(String, Value)> =
  List.append(withoutKey(pairs, k), [(k, v)])

fun objectKeyString(keyVal: Value): String = match (keyVal) {
  StrVal(skey) => skey
  _ => ""
}

fun objectAfterValue(s: String, jv: Int, pairs: List<(String, Value)>, kstr: String, v: Value): Result<(Value, Int), JsonParseError> = {
  val j2 = skipWs(s, jv)
  if (j2 >= Str.length(s)) Err(UnclosedObject(j2))
  else {
    val ch = Str.codePointAt(s, j2)
    val nextPairs = addKey(pairs, kstr, v)
    if (ch == 44) parseObjectEntries(s, skipWs(s, j2 + 1), nextPairs)
    else if (ch == 125) Ok((Object(nextPairs), j2 + 1))
    else Err(ExpectedCommaOrBracket(j2))
  }
}

fun bindObjectValue(s: String, pos: Int, pairs: List<(String, Value)>, kstr: String): Result<(Value, Int), JsonParseError> =
  Res.andThen(parseValue(s, pos), (pvb: (Value, Int)) => objectAfterValue(s, pvb.1, pairs, kstr, pvb.0))

fun parseObjectEntries(s: String, i: Int, pairs: List<(String, Value)>): Result<(Value, Int), JsonParseError> = {
  val j = skipWs(s, i)
  if (j >= Str.length(s)) Err(UnclosedObject(j))
  else if (Str.codePointAt(s, j) == 125) Ok((Object(pairs), j + 1))
  else {
    val ms = parseStringValue(s, j)
    match (ms) {
      Err(_) => ms
      Ok(pk) => {
        // Read pk.1 before keyVal/kstr: codegen may reuse pk's local when projecting StrVal for
        // objectKeyString, which would clobber pk before pk.1 is loaded.
        val jk = pk.1
        val keyVal = pk.0
        val kstr = objectKeyString(keyVal)
        val jc = skipWs(s, jk)
        if (jc >= Str.length(s) | Str.codePointAt(s, jc) != 58) Err(ExpectedColon(jc))
        else bindObjectValue(s, skipWs(s, jc + 1), pairs, kstr)
      }
    }
  }
}

fun parseObjectValue(s: String, i: Int): Result<(Value, Int), JsonParseError> =
  if (i >= Str.length(s) | Str.codePointAt(s, i) != 123) Err(UnexpectedToken(i))
  else parseObjectEntries(s, skipWs(s, i + 1), [])

fun parseArrayElems(s: String, i: Int, acc: List<Value>): Result<(Value, Int), JsonParseError> = {
  val ra = parseValue(s, i)
  match (ra) {
    Err(_) => ra
    Ok(pair) => {
      val j = pair.1
      val v = pair.0
      val j2 = skipWs(s, j)
      if (j2 >= Str.length(s)) Err(UnclosedArray(j2))
      else {
        val ch = Str.codePointAt(s, j2)
        if (ch == 44) parseArrayElems(s, skipWs(s, j2 + 1), v :: acc)
        else if (ch == 93) Ok((Array(List.reverse(v :: acc)), j2 + 1))
        else Err(ExpectedCommaOrBracket(j2))
      }
    }
  }
}

fun parseArrayValue(s: String, i: Int): Result<(Value, Int), JsonParseError> =
  if (i >= Str.length(s) | Str.codePointAt(s, i) != 91) Err(UnexpectedToken(i))
  else {
    val j = skipWs(s, i + 1)
    if (j < Str.length(s) & Str.codePointAt(s, j) == 93) Ok((Array([]), j + 1))
    else parseArrayElems(s, j, [])
  }

fun parseValue(s: String, i: Int): Result<(Value, Int), JsonParseError> = {
  val j = skipWs(s, i)
  if (j >= Str.length(s)) Err(UnexpectedToken(j))
  else {
    val c = Str.codePointAt(s, j)
    if (c == 123) parseObjectValue(s, j)
    else if (c == 91) parseArrayValue(s, j)
    else if (c == 34) parseStringValue(s, j)
    else if (c == 116 & Str.startsWith("true", Str.slice(s, j, Str.length(s)))) Ok((Bool(True), j + 4))
    else if (c == 102 & Str.startsWith("false", Str.slice(s, j, Str.length(s)))) Ok((Bool(False), j + 5))
    else if (c == 110 & Str.startsWith("null", Str.slice(s, j, Str.length(s)))) Ok((Null, j + 4))
    else if (c == 45 | (c >= 48 & c <= 57)) parseNumberValue(s, j)
    else Err(UnexpectedToken(j))
  }
}

export fun parse(s: String): Result<Value, JsonParseError> = {
  val j0 = skipWs(s, 0)
  if (j0 >= Str.length(s)) Err(EmptyInput)
  else
    Res.andThen(parseValue(s, j0), (pair: (Value, Int)) => {
      val j1 = pair.1
      if (j1 < Str.length(s)) Err(TrailingGarbage(j1)) else Ok(pair.0)
    })
}

export fun parseOrNull(s: String): Option<Value> = 
  Res.toOption(parse(s))

fun escapeStringBody(s: String, i: Int, acc: String): String =
  if (i >= Str.length(s)) acc
  else {
    val c = Str.codePointAt(s, i)
    val next =
      if (c == 34) Str.append(acc, "\\\"")
      else if (c == 92) Str.append(acc, "\\\\")
      else if (c == 8) Str.append(acc, "\\b")
      else if (c == 12) Str.append(acc, "\\f")
      else if (c == 10) Str.append(acc, "\\n")
      else if (c == 13) Str.append(acc, "\\r")
      else if (c == 9) Str.append(acc, "\\t")
      else Str.append(acc, Char.charToString(Char.fromCode(c)))
    escapeStringBody(s, i + 1, next)
  }

fun jsonString(s: String): String =
  Str.append(Str.append("\"", escapeStringBody(s, 0, "")), "\"")

export fun stringify(v: Value): String = match (v) {
  Null => "null"
  Bool(b) => if (b) "true" else "false"
  Int(n) => Str.fromInt(n)
  Float(f) => Stk.format(f)
  StrVal(s) => jsonString(s)
  Array(xs) => Str.append(Str.append("[", Str.join(",", List.map(xs, stringify))), "]")
  Object(pairs) =>
    "{${Str.join(",", List.map(pairs, (p: (String, Value)) => "${jsonString(p.0)}:${stringify(p.1)}"))}}"
}
