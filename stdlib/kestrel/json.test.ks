import { Suite, group, eq, isTrue, isFalse } from "kestrel:test"
import { parse, parseOrNull, stringify, errorAsString, describeParse, isNull, isBool, isInt, isFloat, isString, isArray, isObject, jsonNull, regressionErrorMessagesNonEmpty, asInt, asBool, asStrVal, objectPairCount } from "kestrel:json"
import * as Opt from "kestrel:option"
import * as Res from "kestrel:result"
import * as Str from "kestrel:string"

fun intVal(v: Value, n: Int): Bool = Opt.getOrElse(asInt(v), n + 90210) == n

fun boolVal(v: Value, b: Bool): Bool = Opt.getOrElse(asBool(v), !b) == b

fun strVal(v: Value, s: String): Bool = Str.equals(Opt.getOrElse(asStrVal(v), "__missing__"), s)

fun unwrapOk(r): Value = Res.getOrElse(r, jsonNull())

export fun run(s: Suite): Unit =
  group(s, "json", (s1: Suite) => {
    group(s1, "parse literals and Result", (sg: Suite) => {
      isTrue(sg, "null Ok", isNull(unwrapOk(parse("null"))));
      isTrue(sg, "true Ok", boolVal(unwrapOk(parse("true")), True));
      isTrue(sg, "false Ok", boolVal(unwrapOk(parse("false")), False));
      isTrue(sg, "int Ok", intVal(unwrapOk(parse("42")), 42));
      isTrue(sg, "negative int", intVal(unwrapOk(parse("-3")), -3));
      isTrue(sg, "float", isFloat(unwrapOk(parse("2.5"))));
      isTrue(sg, "string", strVal(unwrapOk(parse("\"ab\"")), "ab"));
      isTrue(sg, "invalid is error", Res.isErr(parse("{")));
      eq(sg, "empty input message", describeParse(""), "empty JSON input");
      eq(sg, "whitespace only", describeParse("   "), "empty JSON input");
    })

    group(s1, "parseOrNull", (sg: Suite) => {
      isTrue(sg, "Some on null", Opt.isSome(parseOrNull("null")) & isNull(Res.getOrElse(parse("null"), jsonNull())));
      isTrue(sg, "None on bad", Opt.isNone(parseOrNull("{")));
    })

    group(s1, "errorAsString regression", (sg: Suite) => {
      isTrue(sg, "all variants non-empty", regressionErrorMessagesNonEmpty());
    })

    group(s1, "parse arrays", (sg: Suite) => {
      isTrue(sg, "empty", isArray(unwrapOk(parse("[]"))));
      val flat = unwrapOk(parse("[1,2,3]"));
      isTrue(sg, "is array", isArray(flat));
      eq(sg, "stringify flat", stringify(flat), "[1,2,3]");
      val nested = unwrapOk(parse("[[1],[2,3]]"));
      isTrue(sg, "nested is array", isArray(nested));
      eq(sg, "stringify nested", stringify(nested), "[[1],[2,3]]");
    })

    group(s1, "parse object", (sg: Suite) => {
      val o = unwrapOk(parse("{\"a\":1,\"b\":2}"));
      isTrue(sg, "is object", isObject(o));
      eq(sg, "two entries", objectPairCount(o), 2);
      val st = stringify(o);
      isTrue(sg, "stringify contains keys", Str.indexOf(st, "\"a\"") >= 0 & Str.indexOf(st, "\"b\"") >= 0);
    })

    group(s1, "duplicate keys last wins", (sg: Suite) => {
      val o = unwrapOk(parse("{\"x\":1,\"x\":2}"));
      isTrue(sg, "one key", objectPairCount(o) == 1);
      val st = stringify(o);
      isTrue(sg, "value 2", Str.indexOf(st, ":2") >= 0);
    })

    group(s1, "trailing garbage", (sg: Suite) => {
      isTrue(sg, "describeParse notes garbage", Str.indexOf(describeParse("null "), "trailing") >= 0);
    })

    group(s1, "round-trip", (sg: Suite) => {
      val n = unwrapOk(parse("null"));
      eq(sg, "null rt", stringify(n), "null");
      val arr = unwrapOk(parse("[1,2]"));
      isTrue(sg, "array rt", Res.isOk(parse(stringify(arr))));
    })

    group(s1, "invalid json", (sg: Suite) => {
      isTrue(sg, "truncated object", Res.isErr(parse("{")));
      isTrue(sg, "bad keyword", Res.isErr(parse("tru")));
      isTrue(sg, "trailing comma array", Res.isErr(parse("[1,]")));
    })

    group(s1, "escapes and unicode", (sg: Suite) => {
      isTrue(sg, "newline escape", strVal(unwrapOk(parse("\"a\\nb\"")), "a\nb"));
      isTrue(sg, "unicode escape", strVal(unwrapOk(parse("\"\\u00e9\"")), "\u{00E9}"));
    })
  })
