import { Suite, group, eq, isTrue } from "kestrel:dev/test"
import * as Str from "kestrel:data/string"
import * as Console from "kestrel:io/console"
import * as Helper from "../fixtures/export_var_helper.ks"
import * as Lib from "../fixtures/opaque_pkg/lib.ks"

export async fun run(s: Suite): Task<Unit> =
  group(s, "namespace import", (s1: Suite) => {
    group(s1, "functions", (s2: Suite) => {
      eq(s2, "Str.length", Str.length("hello"), 5)
      eq(s2, "Str.slice", Str.slice("hello", 0, 2), "he")
      eq(s2, "Str.indexOf", Str.indexOf("hello", "ll"), 2)
      isTrue(s2, "Str.equals", Str.equals("a", "a"))
      eq(s2, "Str.toUpperCase", Str.toUpperCase("hello"), "HELLO")
      eq(s2, "namespace function as value", ((f: (String) -> Int) => f("hello"))(Str.length), 5)
    })
    group(s1, "value bindings", (s2: Suite) => {
      eq(s2, "Console.ESC", Console.ESC, "\u{1b}")
      eq(s2, "Console.CHECK", Console.CHECK, "\u{2713}")
      eq(s2, "Console.CROSS", Console.CROSS, "\u{2717}")
    })
    group(s1, "var binding", (s2: Suite) => {
      Helper.counter := 0
      val c0 = Helper.counter
      eq(s2, "initial", c0, 0)
      Helper.counter := 42
      val c1 = Helper.counter
      eq(s2, "after assign", c1, 42)
    })
    group(s1, "opaque type via namespace", (s2: Suite) => {
      eq(s2, "Lib.secretTokenToInt(makeSecretToken(100))", Lib.secretTokenToInt(Lib.makeSecretToken(100)), 100)
      eq(s2, "Lib.userIdToInt(makeUserId(999))", Lib.userIdToInt(Lib.makeUserId(999)), 999)
    })
    group(s1, "namespace ADT constructors", (s2: Suite) => {
      eq(s2, "Lib.PubNum unary", Lib.publicTokenToInt(Lib.PubNum(42)), 42)
      eq(s2, "Lib.PubOp unary", Lib.publicTokenToInt(Lib.PubOp("x")), 0)
      eq(s2, "Lib.PubEof nullary", Lib.publicTokenToInt(Lib.PubEof), -1)
      eq(s2, "Lib.PubPair multi-arg", Lib.publicTokenToInt(Lib.PubPair(1, 2)), 3)
      eq(s2, "makePubNum still matches Lib.PubNum", Lib.publicTokenToInt(Lib.makePubNum(7)), Lib.publicTokenToInt(Lib.PubNum(7)))
    })
    group(s1, "qualified type annotation", (s2: Suite) => {
      val x: Lib.PublicToken = Lib.makePubNum(42)
      eq(s2, "Lib.PublicToken annotation and makePubNum", Lib.publicTokenToInt(x), 42)
    })
  })
