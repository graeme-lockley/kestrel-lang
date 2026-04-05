import { Suite, group, eq, isTrue } from "kestrel:tools/test"
import * as PP from "kestrel:dev/text/prettyprinter"
import * as Str from "kestrel:data/string"

export async fun run(s: Suite): Task<Unit> =
  group(s, "prettyprinter", (s1: Suite) => {
    group(s1, "empty", (sg: Suite) => {
      eq(sg, "empty doc", PP.pretty(80, PP.empty), "")
    });

    group(s1, "text", (sg: Suite) => {
      eq(sg, "text doc", PP.pretty(80, PP.text("hello")), "hello")
    });

    group(s1, "concat", (sg: Suite) => {
      val d = PP.concat(PP.text("hello"), PP.text(" world"))
      eq(sg, "concat", PP.pretty(80, d), "hello world")
    });

    group(s1, "line flat", (sg: Suite) => {
      val d = PP.group(PP.concat(PP.text("hello"), PP.concat(PP.line, PP.text("world"))))
      eq(sg, "fits → space", PP.pretty(80, d), "hello world")
    });

    group(s1, "line broken", (sg: Suite) => {
      val d = PP.group(PP.concat(PP.text("hello"), PP.concat(PP.line, PP.text("world"))))
      eq(sg, "too wide → newline", PP.pretty(5, d), "hello\nworld")
    });

    group(s1, "lineBreak flat", (sg: Suite) => {
      val d = PP.group(PP.concat(PP.text("hello"), PP.concat(PP.lineBreak, PP.text("world"))))
      eq(sg, "flat lineBreak is empty", PP.pretty(80, d), "helloworld")
    });

    group(s1, "lineBreak broken", (sg: Suite) => {
      val d = PP.group(PP.concat(PP.text("hello"), PP.concat(PP.lineBreak, PP.text("world"))))
      eq(sg, "broken lineBreak is newline", PP.pretty(5, d), "hello\nworld")
    });

    group(s1, "nest", (sg: Suite) => {
      val d = PP.group(PP.concat(PP.text("fun f ="), PP.nest(2, PP.concat(PP.line, PP.text("42")))))
      eq(sg, "nest 2 broken", PP.pretty(5, d), "fun f =\n  42")
    });

    group(s1, "hsep", (sg: Suite) => {
      val d = PP.hsep([PP.text("a"), PP.text("b"), PP.text("c")])
      eq(sg, "hsep", PP.pretty(80, d), "a b c")
    });

    group(s1, "vsep broken", (sg: Suite) => {
      val d = PP.vsep([PP.text("a"), PP.text("b"), PP.text("c")])
      eq(sg, "vsep broken", PP.pretty(5, d), "a\nb\nc")
    });

    group(s1, "sep flat", (sg: Suite) => {
      val d = PP.sep([PP.text("a"), PP.text("b"), PP.text("c")])
      eq(sg, "sep fits → spaces", PP.pretty(80, d), "a b c")
    });

    group(s1, "sep broken", (sg: Suite) => {
      val d = PP.sep([PP.text("abcde"), PP.text("fghij"), PP.text("klmno")])
      eq(sg, "sep too wide → newlines", PP.pretty(10, d), "abcde\nfghij\nklmno")
    });

    group(s1, "hcat", (sg: Suite) => {
      val d = PP.hcat([PP.text("a"), PP.text("b"), PP.text("c")])
      eq(sg, "hcat no sep", PP.pretty(80, d), "abc")
    });

    group(s1, "beside", (sg: Suite) => {
      val d = PP.beside(PP.text("x"), PP.text("y"))
      eq(sg, "beside", PP.pretty(80, d), "x y")
    });

    group(s1, "enclose", (sg: Suite) => {
      val d = PP.enclose(PP.text("("), PP.text(")"), PP.text("hello"))
      eq(sg, "enclose", PP.pretty(80, d), "(hello)")
    });

    group(s1, "punctuate", (sg: Suite) => {
      val items = PP.punctuate(PP.text(","), [PP.text("a"), PP.text("b"), PP.text("c")])
      val d = PP.hcat(items)
      eq(sg, "punctuate commas", PP.pretty(80, d), "a,b,c")
    });

    group(s1, "indent", (sg: Suite) => {
      val d = PP.concat(PP.text("x"), PP.concat(PP.line, PP.indent(2, PP.text("y"))))
      eq(sg, "indent adds spaces", PP.pretty(5, d), "x\n  y")
    });

    group(s1, "flatAlt", (sg: Suite) => {
      val d = PP.flatAlt(PP.text("broken"), PP.text("flat"))
      val dg = PP.group(d)
      eq(sg, "flatAlt flat mode", PP.pretty(80, dg), "flat");
      eq(sg, "flatAlt broken mode", PP.pretty(80, d), "broken")
    })
  })
