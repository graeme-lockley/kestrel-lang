import { Suite, group, eq, isTrue } from "kestrel:test"
import { parse, stringify } from "kestrel:json"
import { isNull, isBool, isInt, isFloat, isString, isArray, isObject } from "kestrel:value"
import * as List from "kestrel:list"

// Reference VM: failed JSON parse yields the same Value tag as JSON null (`Null`), so invalid input
// cannot be distinguished from the literal JSON `null` without a separate error channel.

fun intVal(v: Value, n: Int): Bool = match (v) {
  Int(x) => x == n
  _ => False
}

fun boolVal(v: Value, b: Bool): Bool = match (v) {
  Bool(x) => x == b
  _ => False
}

fun strVal(v: Value, s: String): Bool = match (v) {
  String(x) => __string_equals(x, s)
  _ => False
}

fun objectEntryCount(v: Value): Int = match (v) {
  Object(pairs) => List.length(pairs)
  _ => -1
}

export fun run(s: Suite): Unit =
  group(s, "json", (s1: Suite) => {
    group(s1, "parse literals", (sg: Suite) => {
      isTrue(sg, "null", isNull(parse("null")));
      isTrue(sg, "true", boolVal(parse("true"), True));
      isTrue(sg, "false", boolVal(parse("false"), False));
      isTrue(sg, "int", intVal(parse("42"), 42));
      isTrue(sg, "negative int", intVal(parse("-3"), -3));
      isTrue(sg, "float", isFloat(parse("2.5")));
      isTrue(sg, "string", strVal(parse("\"ab\""), "ab"));
    })

    group(s1, "parse arrays", (sg: Suite) => {
      isTrue(sg, "empty", isArray(parse("[]")));
      val flat = parse("[1,2,3]");
      isTrue(sg, "is array", isArray(flat));
      eq(sg, "stringify flat", stringify(flat), "[1,2,3]");
      val nested = parse("[[1],[2,3]]");
      isTrue(sg, "nested is array", isArray(nested));
      eq(sg, "stringify nested", stringify(nested), "[[1],[2,3]]");
    })

    group(s1, "parse object stub", (sg: Suite) => {
      val o = parse("{\"a\":1,\"b\":2}");
      isTrue(sg, "is object", isObject(o));
      eq(sg, "entries not preserved yet", objectEntryCount(o), 0);
      eq(sg, "stringify object stub", stringify(o), "{}");
    })

    group(s1, "stringify round-trip kinds", (sg: Suite) => {
      val n = parse("null");
      eq(sg, "null rt", stringify(n), "null");
      val t = parse("true");
      eq(sg, "bool rt", stringify(t), "true");
      val num = parse("-7");
      eq(sg, "int rt", stringify(num), "-7");
      val st = parse("\"z\"");
      eq(sg, "string rt", stringify(st), "\"z\"");
      val arr = parse("[1,2]");
      eq(sg, "array rt", stringify(parse(stringify(arr))), "[1,2]");
    })

    group(s1, "parse invalid", (sg: Suite) => {
      isTrue(sg, "garbage is Null", isNull(parse("{")));
      isTrue(sg, "literal null still Null", isNull(parse("null")));
      // Both cases above are `Null`; callers cannot tell parse failure from JSON null.
    })

    group(s1, "string escapes and unicode", (sg: Suite) => {
      isTrue(sg, "newline escape", strVal(parse("\"a\\nb\""), "a\nb"));
      isTrue(sg, "unicode escape", strVal(parse("\"\\u00e9\""), "\u{00E9}"));
    })

    group(s1, "object stringify parse documented path", (sg: Suite) => {
      val o = parse("{\"x\":1}");
      eq(sg, "parse then stringify", stringify(o), "{}");
      val o2 = parse(stringify(o));
      isTrue(sg, "still object", isObject(o2));
      eq(sg, "still empty payload", objectEntryCount(o2), 0);
    })
  })
