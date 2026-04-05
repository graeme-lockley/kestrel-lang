import { Suite, group, eq, isTrue, isFalse } from "kestrel:tools/test"
import {
  parse,
  parseOrNull,
  stringify,
  describeParse,
  isNull,
  isBool,
  isInt,
  isFloat,
  isString,
  isArray,
  isObject,
  jsonNull,
  regressionErrorMessagesNonEmpty,
  asInt,
  asBool,
  asStrVal,
  objectPairCount
} from "kestrel:data/json"
import * as Opt from "kestrel:data/option"
import * as Res from "kestrel:data/result"
import * as Str from "kestrel:data/string"

fun intVal(v: Value, n: Int): Bool = Opt.getOrElse(asInt(v), n + 90210) == n

fun boolVal(v: Value, b: Bool): Bool = Opt.getOrElse(asBool(v), !b) == b

fun strVal(v: Value, s: String): Bool = Str.equals(Opt.getOrElse(asStrVal(v), "__missing__"), s)

fun unwrapOk(r): Value = Res.getOrElse(r, jsonNull())

/** True if `describeParse(s)` contains `needle` (error-path smoke). */
fun parseErrContains(s: String, needle: String): Bool = Str.indexOf(describeParse(s), needle) >= 0

export async fun run(s: Suite): Task<Unit> =
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
      isTrue(sg, "Some on null", Opt.isSome(parseOrNull("null")) & isNull(unwrapOk(parse("null"))));
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
      eq(sg, "whitespace tolerant", stringify(unwrapOk(parse("[ 1 , 2 ]"))), "[1,2]");
      eq(sg, "negative in array", stringify(unwrapOk(parse("[-7]"))), "[-7]");
    })

    group(s1, "parse object", (sg: Suite) => {
      val o = unwrapOk(parse("{\"a\":1,\"b\":2}"));
      isTrue(sg, "is object", isObject(o));
      eq(sg, "two entries", objectPairCount(o), 2);
      val st = stringify(o);
      isTrue(sg, "stringify contains keys", Str.indexOf(st, "\"a\"") >= 0 & Str.indexOf(st, "\"b\"") >= 0);
      val emptyObj = unwrapOk(parse("{}"));
      isTrue(sg, "empty object", isObject(emptyObj) & objectPairCount(emptyObj) == 0);
      eq(sg, "stringify empty object", stringify(emptyObj), "{}");
    })

    group(s1, "duplicate keys last wins", (sg: Suite) => {
      val o = unwrapOk(parse("{\"x\":1,\"x\":2}"));
      isTrue(sg, "one key", objectPairCount(o) == 1);
      val st = stringify(o);
      isTrue(sg, "value 2", Str.indexOf(st, ":2") >= 0);
    })

    group(s1, "trailing garbage", (sg: Suite) => {
      isTrue(sg, "describeParse notes garbage", parseErrContains("null ", "trailing"));
      isTrue(sg, "garbage after object", parseErrContains("{\"a\":1} ", "trailing"));
    })

    group(s1, "round-trip", (sg: Suite) => {
      val n = unwrapOk(parse("null"));
      eq(sg, "null rt", stringify(n), "null");
      val arr = unwrapOk(parse("[1,2]"));
      isTrue(sg, "array rt", Res.isOk(parse(stringify(arr))));
      val t = unwrapOk(parse("true"));
      eq(sg, "bool true stringify", stringify(t), "true");
      isTrue(sg, "bool rt", boolVal(unwrapOk(parse(stringify(t))), True));
      val f = unwrapOk(parse("false"));
      eq(sg, "bool false stringify", stringify(f), "false");
      val obj = unwrapOk(parse("{\"k\":1}"));
      isTrue(sg, "object rt", Res.isOk(parse(stringify(obj))));
      val esc = unwrapOk(parse("\"a\\nb\""));
      isTrue(sg, "string escape rt", strVal(unwrapOk(parse(stringify(esc))), "a\nb"));
      val fl = unwrapOk(parse("2.5"));
      isTrue(sg, "float rt", isFloat(unwrapOk(parse(stringify(fl)))));
    })

    group(s1, "invalid json", (sg: Suite) => {
      isTrue(sg, "truncated object", Res.isErr(parse("{")));
      isTrue(sg, "bad keyword", Res.isErr(parse("tru")));
      isTrue(sg, "trailing comma array", Res.isErr(parse("[1,]")));
      isTrue(sg, "leading zero", Res.isErr(parse("01")));
      isTrue(sg, "trailing comma object parses (lenient)", Res.isOk(parse("{\"a\":1,}")));
      isTrue(sg, "missing value after colon", Res.isErr(parse("{\"a\":}")));
      isTrue(sg, "plus sign number", Res.isErr(parse("+1")));
      isTrue(sg, "bare dot", Res.isErr(parse(".5")));
    })

    group(s1, "parse error kinds (describeParse)", (sg: Suite) => {
      isTrue(sg, "leading zero message", parseErrContains("01", "invalid number"));
      isTrue(sg, "missing colon", parseErrContains("{\"a\" 1}", "expected colon"));
      isTrue(sg, "missing comma between props", parseErrContains("{\"a\":1 \"b\":2}", "expected comma"));
      isTrue(sg, "unclosed array", parseErrContains("[1", "unclosed array"));
      isTrue(sg, "unclosed string", parseErrContains("\"ab", "unclosed string"));
      isTrue(sg, "invalid escape", parseErrContains("\"\\q\"", "invalid escape"));
      isTrue(sg, "bad unicode", parseErrContains("\"\\u00G0\"", "invalid unicode"));
      isTrue(sg, "low surrogate alone", parseErrContains("\"\\uDD1E\"", "invalid unicode"));
    })

    group(s1, "numbers extended", (sg: Suite) => {
      isTrue(sg, "zero int", intVal(unwrapOk(parse("0")), 0));
      isTrue(sg, "sci e upper", isFloat(unwrapOk(parse("1E2"))));
      isTrue(sg, "sci e value", intVal(unwrapOk(parse("100")), 100));
      val sci = unwrapOk(parse("12e3"));
      isTrue(sg, "12e3 is float", isFloat(sci));
      isTrue(sg, "sci round-trip", Res.isOk(parse(stringify(sci))));
      isTrue(sg, "decimal exp", isFloat(unwrapOk(parse("2.5e-1"))));
      isTrue(sg, "zero dot fraction", isFloat(unwrapOk(parse("0.25"))));
      isTrue(sg, "zero exp", isFloat(unwrapOk(parse("0e0"))));
    })

    group(s1, "escapes and unicode", (sg: Suite) => {
      isTrue(sg, "newline escape", strVal(unwrapOk(parse("\"a\\nb\"")), "a\nb"));
      isTrue(sg, "unicode escape", strVal(unwrapOk(parse("\"\\u00e9\"")), "\u{00E9}"));
      isTrue(sg, "backspace", strVal(unwrapOk(parse("\"\\b\"")), "\u{0008}"));
      isTrue(sg, "form feed", strVal(unwrapOk(parse("\"\\f\"")), "\u{000C}"));
      isTrue(sg, "carriage return", strVal(unwrapOk(parse("\"\\r\"")), "\u{000D}"));
      isTrue(sg, "tab", strVal(unwrapOk(parse("\"\\t\"")), "\u{0009}"));
      isTrue(sg, "quote", strVal(unwrapOk(parse("\"\\\"x\"")), "\"x"));
      isTrue(sg, "backslash", strVal(unwrapOk(parse("\"\\\\\"")), "\\"));
      isTrue(sg, "solidus", strVal(unwrapOk(parse("\"\\/\"")), "/"));
      isTrue(sg, "surrogate pair", strVal(unwrapOk(parse("\"\\uD834\\uDD1E\"")), "\u{1D11E}"));
    })

    group(s1, "stringify escapes control chars", (sg: Suite) => {
      val v = unwrapOk(parse("\"\\u0008\\u000C\\n\\r\\t\""));
      val out = stringify(v);
      isTrue(sg, "has b", Str.indexOf(out, "\\b") >= 0);
      isTrue(sg, "has f", Str.indexOf(out, "\\f") >= 0);
      isTrue(sg, "has n", Str.indexOf(out, "\\n") >= 0);
      isTrue(sg, "has r", Str.indexOf(out, "\\r") >= 0);
      isTrue(sg, "has t", Str.indexOf(out, "\\t") >= 0);
    })

    group(s1, "API edge cases", (sg: Suite) => {
      eq(sg, "objectPairCount non-object", objectPairCount(unwrapOk(parse("[]"))), -1);
      isTrue(sg, "asInt wrong tag", Opt.isNone(asInt(unwrapOk(parse("true")))));
      isTrue(sg, "asBool wrong tag", Opt.isNone(asBool(unwrapOk(parse("1")))));
      isTrue(sg, "asStrVal wrong tag", Opt.isNone(asStrVal(unwrapOk(parse("null")))));
      isTrue(sg, "isString", isString(unwrapOk(parse("\"x\""))));
      isFalse(sg, "isString on int", isString(unwrapOk(parse("1"))));
    })
  })
