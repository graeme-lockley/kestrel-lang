import { Suite, group, eq, isTrue, isFalse } from "kestrel:tools/test"
import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"
import * as Str from "kestrel:data/string"
import * as Lex from "kestrel:dev/parser/lexer"
import { parseFromList, parseExprFromList } from "kestrel:dev/parser/parser"
import * as Ast from "kestrel:dev/parser/ast"
import {
  ELit, EIdent, ECall, EField, EAwait, EUnary, EBinary, ECons, EPipe,
  EIf, EWhile, ELambda, ETemplate, EList, ERecord, ETuple,
  EMatch, EBlock, EThrow, ETry, EIs, ENever,
  TmplLit, TmplExpr, LElem, LSpread,
  SVal, SVar, SAssign, SExpr, SFun, SBreak, SContinue,
  TDFun, TDSVal, TDSVar, TDSExpr, TDSAssign, TDType, TDException, TDExport, TDVal, TDVar,
  IDNamed, IDNamespace, IDSideEffect, EIStar, EINamed,
  ATPrim, ATIdent, ATApp, ATArrow, ATRecord, ATTuple, ATUnion, ATInter, ATRowVar, ATQualified,
  PWild, PVar, PLit, PCon, PList, PCons, PTuple,
  TBAdt, TBAlias
} from "kestrel:dev/parser/ast"

// ─── Test helpers ─────────────────────────────────────────────────────────────

fun pl(src: String): Ast.Program =
  match (parseFromList(Lex.lex(src))) {
    Ok(prog) => prog,
    Err(e) => throw e
  }

fun pe(src: String): Ast.Expr =
  match (parseExprFromList(Lex.lex(src))) {
    Ok(expr) => expr,
    Err(e) => throw e
  }

fun firstImport(src: String): Ast.ImportDecl =
  match (Lst.head(pl(src).imports)) {
    Some(d) => d,
    None => IDSideEffect("__missing__")
  }

fun firstDecl(src: String): Ast.TopDecl =
  match (Lst.head(pl(src).body)) {
    Some(d) => d,
    None => TDSExpr(ELit("unit","()"))
  }

// ─── Test suite ───────────────────────────────────────────────────────────────

export async fun run(s: Suite): Task<Unit> =
  group(s, "parser", (s1: Suite) => {

    // ── Imports ───────────────────────────────────────────────────────────────

    group(s1, "imports", (sg: Suite) => {
      match (firstImport("import { foo } from \"m\"")) {
        IDNamed(spec, specs) => {
          eq(sg, "named spec", spec, "m");
          match (Lst.head(specs)) {
            Some(importSpec) => {
              eq(sg, "external", importSpec.external, "foo");
              eq(sg, "local", importSpec.local, "foo")
            },
            None => isTrue(sg, "expected spec", False)
          }
        },
        _ => isTrue(sg, "expected IDNamed", False)
      };
      match (firstImport("import { foo as bar } from \"m\"")) {
        IDNamed(spec, specs) => {
          match (Lst.head(specs)) {
            Some(importSpec) => {
              eq(sg, "renamed external", importSpec.external, "foo");
              eq(sg, "renamed local", importSpec.local, "bar")
            },
            None => isTrue(sg, "expected renamed spec", False)
          }
        },
        _ => isTrue(sg, "expected IDNamed renamed", False)
      };
      match (firstImport("import { a, b } from \"m\"")) {
        IDNamed(spec, specs) => eq(sg, "two specs", Lst.length(specs), 2),
        _ => isTrue(sg, "expected IDNamed two", False)
      };
      match (firstImport("import * as M from \"m\"")) {
        IDNamespace(spec, alias) => {
          eq(sg, "namespace spec", spec, "m");
          eq(sg, "namespace alias", alias, "M")
        },
        _ => isTrue(sg, "expected IDNamespace", False)
      };
      match (firstImport("import \"m\"")) {
        IDSideEffect(spec) => eq(sg, "side-effect spec", spec, "m"),
        _ => isTrue(sg, "expected IDSideEffect", False)
      };
      val twoImports = pl("import { a } from \"m1\"\nimport { b } from \"m2\"")
      eq(sg, "two imports len", Lst.length(twoImports.imports), 2)
    });

    // ── Function declarations ─────────────────────────────────────────────────

    group(s1, "fun declarations", (sg: Suite) => {
      match (firstDecl("fun f(x: Int): Int = x")) {
        TDFun(fd) => {
          eq(sg, "name", fd.name, "f");
          eq(sg, "not exported", fd.exported, False);
          eq(sg, "not async", fd.async_, False);
          eq(sg, "params len", Lst.length(fd.params), 1);
          match (Lst.head(fd.params)) {
            Some(pm) => eq(sg, "param name", pm.name, "x"),
            None => isTrue(sg, "expected param", False)
          }
        },
        _ => isTrue(sg, "expected TDFun", False)
      };
      match (firstDecl("async fun f(): Int = 1")) {
        TDFun(fd) => eq(sg, "async flag", fd.async_, True),
        _ => isTrue(sg, "expected async TDFun", False)
      };
      match (firstDecl("export fun f(): Unit = ()")) {
        TDFun(fd) => eq(sg, "exported flag", fd.exported, True),
        _ => isTrue(sg, "expected exported TDFun", False)
      };
      match (firstDecl("fun f<A>(x: A): A = x")) {
        TDFun(fd) => eq(sg, "type params", fd.typeParams, ["A"]),
        _ => isTrue(sg, "expected generic TDFun", False)
      };
      match (firstDecl("fun f(x: Int, y: Bool): String = \"z\"")) {
        TDFun(fd) => eq(sg, "two params", Lst.length(fd.params), 2),
        _ => isTrue(sg, "expected two-param TDFun", False)
      }
    });

    // ── Value and variable declarations ───────────────────────────────────────

    group(s1, "val/var declarations", (sg: Suite) => {
      match (firstDecl("val x = 42")) {
        TDSVal(name, expr) => {
          eq(sg, "val name", name, "x");
          eq(sg, "val expr", expr, ELit("int","42"))
        },
        _ => isTrue(sg, "expected TDSVal", False)
      };
      match (firstDecl("var x = 42")) {
        TDSVar(name, expr) => {
          eq(sg, "var name", name, "x");
          eq(sg, "var expr", expr, ELit("int","42"))
        },
        _ => isTrue(sg, "expected TDSVar", False)
      };
      match (firstDecl("export val x: Int = 42")) {
        TDVal(name, typ, expr) => {
          eq(sg, "export val name", name, "x");
          eq(sg, "export val type", typ, Some(ATPrim("Int")));
          eq(sg, "export val expr", expr, ELit("int","42"))
        },
        _ => isTrue(sg, "expected TDVal", False)
      };
      match (firstDecl("export var x: Int = 0")) {
        TDVar(name, typ, expr) => {
          eq(sg, "export var name", name, "x");
          eq(sg, "export var type", typ, Some(ATPrim("Int")))
        },
        _ => isTrue(sg, "expected TDVar", False)
      }
    });

    // ── Type declarations ─────────────────────────────────────────────────────

    group(s1, "type declarations", (sg: Suite) => {
      match (firstDecl("type Alias = Int")) {
        TDType(td) => {
          eq(sg, "alias visibility", td.visibility, "local");
          match (td.body) {
            TBAlias(aliasType) => eq(sg, "alias body", aliasType, ATPrim("Int")),
            _ => isTrue(sg, "expected TBAlias", False)
          }
        },
        _ => isTrue(sg, "expected TDType alias", False)
      };
      match (firstDecl("type Color = Red | Green | Blue")) {
        TDType(td) => {
          match (td.body) {
            TBAdt(ctors) => eq(sg, "3 ctors", Lst.length(ctors), 3),
            _ => isTrue(sg, "expected TBAdt", False)
          }
        },
        _ => isTrue(sg, "expected TDType adt", False)
      };
      match (firstDecl("type Box<A> = Box(A)")) {
        TDType(td) => eq(sg, "type params", td.typeParams, ["A"]),
        _ => isTrue(sg, "expected generic TDType", False)
      };
      match (firstDecl("opaque type T = Int")) {
        TDType(td) => eq(sg, "opaque visibility", td.visibility, "opaque"),
        _ => isTrue(sg, "expected opaque TDType", False)
      };
      match (firstDecl("exception MyError")) {
        TDException(ed) => {
          eq(sg, "exception name", ed.name, "MyError");
          eq(sg, "exception not exported", ed.exported, False);
          eq(sg, "exception fields none", ed.fields, None)
        },
        _ => isTrue(sg, "expected TDException", False)
      };
      match (firstDecl("exception E { msg: String }")) {
        TDException(ed) => {
          match (ed.fields) {
            Some(fs) => eq(sg, "exception fields len", Lst.length(fs), 1),
            None => isTrue(sg, "expected fields", False)
          }
        },
        _ => isTrue(sg, "expected TDException with fields", False)
      };
      match (firstDecl("export exception E")) {
        TDException(ed) => eq(sg, "exported exception", ed.exported, True),
        _ => isTrue(sg, "expected exported exception", False)
      };
      match (firstDecl("export * from \"m\"")) {
        TDExport(inner) => {
          match (inner) {
            EIStar(spec) => eq(sg, "export star spec", spec, "m"),
            _ => isTrue(sg, "expected EIStar", False)
          }
        },
        _ => isTrue(sg, "expected TDExport star", False)
      };
      match (firstDecl("export { foo, bar } from \"m\"")) {
        TDExport(inner) => {
          match (inner) {
            EINamed(spec, specs) => {
              eq(sg, "export named spec", spec, "m");
              eq(sg, "export named len", Lst.length(specs), 2)
            },
            _ => isTrue(sg, "expected EINamed", False)
          }
        },
        _ => isTrue(sg, "expected TDExport named", False)
      }
    });

    // ── Literal expressions ───────────────────────────────────────────────────

    group(s1, "literals", (sg: Suite) => {
      eq(sg, "int lit", pe("42"), ELit("int","42"));
      eq(sg, "hex int", pe("0xff"), ELit("int","0xff"));
      eq(sg, "float lit", pe("3.14"), ELit("float","3.14"));
      eq(sg, "string lit", pe("\"hello\""), ELit("string","hello"));
      eq(sg, "char lit", pe("'a'"), ELit("char","a"));
      eq(sg, "unit lit", pe("()"), ELit("unit","()"));
      eq(sg, "true lit", pe("True"), ELit("true","True"));
      eq(sg, "false lit", pe("False"), ELit("false","False"))
    });

    // ── Identifiers, field access, calls ──────────────────────────────────────

    group(s1, "ident/field/call", (sg: Suite) => {
      eq(sg, "ident", pe("x"), EIdent("x"));
      eq(sg, "upper ident", pe("Foo"), EIdent("Foo"));
      eq(sg, "call no args", pe("f()"), ECall(EIdent("f"), []));
      eq(sg, "call one arg", pe("f(1)"), ECall(EIdent("f"), [ELit("int","1")]));
      eq(sg, "call two args", pe("f(1, 2)"), ECall(EIdent("f"), [ELit("int","1"), ELit("int","2")]));
      eq(sg, "field access", pe("a.b"), EField(EIdent("a"), "b"));
      eq(sg, "nested field", pe("a.b.c"), EField(EField(EIdent("a"),"b"), "c"));
      eq(sg, "tuple index", pe("a.0"), EField(EIdent("a"), "0"));
      match (pe("f(1)(2)")) {
        ECall(outerCallee, _) =>
          match (outerCallee) {
            ECall(innerCallee, _) => eq(sg, "chained call", innerCallee, EIdent("f")),
            _ => isTrue(sg, "expected inner ECall", False)
          },
        _ => isTrue(sg, "expected outer ECall", False)
      }
    });

    // ── Operator precedence ───────────────────────────────────────────────────

    group(s1, "operator precedence", (sg: Suite) => {
      eq(sg, "add", pe("1 + 2"), EBinary("+", ELit("int","1"), ELit("int","2")));
      eq(sg, "mul before add", pe("1 + 2 * 3"),
        EBinary("+", ELit("int","1"), EBinary("*", ELit("int","2"), ELit("int","3"))));
      eq(sg, "mul before add left", pe("1 * 2 + 3"),
        EBinary("+", EBinary("*", ELit("int","1"), ELit("int","2")), ELit("int","3")));
      eq(sg, "pow right assoc", pe("2 ** 3 ** 4"),
        EBinary("**", ELit("int","2"), EBinary("**", ELit("int","3"), ELit("int","4"))));
      eq(sg, "sub left assoc", pe("1 - 2 - 3"),
        EBinary("-", EBinary("-", ELit("int","1"), ELit("int","2")), ELit("int","3")));
      eq(sg, "eq op", pe("1 == 2"), EBinary("==", ELit("int","1"), ELit("int","2")));
      eq(sg, "neq op", pe("1 != 2"), EBinary("!=", ELit("int","1"), ELit("int","2")));
      eq(sg, "lt op", pe("a < b"), EBinary("<", EIdent("a"), EIdent("b")));
      eq(sg, "gte op", pe("a >= b"), EBinary(">=", EIdent("a"), EIdent("b")));
      eq(sg, "or op", pe("a | b"), EBinary("|", EIdent("a"), EIdent("b")));
      eq(sg, "and op", pe("a & b"), EBinary("&", EIdent("a"), EIdent("b")));
      eq(sg, "pipe right", pe("x |> f"), EPipe("|>", EIdent("x"), EIdent("f")));
      eq(sg, "pipe left", pe("f <| x"), EPipe("<|", EIdent("f"), EIdent("x")));
      eq(sg, "cons", pe("x :: xs"), ECons(EIdent("x"), EIdent("xs")));
      eq(sg, "cons right assoc", pe("1 :: 2 :: []"),
        ECons(ELit("int","1"), ECons(ELit("int","2"), EList([]))));
      eq(sg, "unary minus", pe("-1"), EUnary("-", ELit("int","1")));
      eq(sg, "unary not", pe("!x"), EUnary("!", EIdent("x")));
      eq(sg, "is expr", pe("x is Int"), EIs(EIdent("x"), ATPrim("Int")))
    });

    // ── Control flow ──────────────────────────────────────────────────────────

    group(s1, "control flow", (sg: Suite) => {
      eq(sg, "if with else", pe("if (x) y else z"),
        EIf(EIdent("x"), EIdent("y"), Some(EIdent("z"))));
      eq(sg, "if no else", pe("if (x) y"),
        EIf(EIdent("x"), EIdent("y"), None));
      eq(sg, "while", pe("while (x) { y }"),
        EWhile(EIdent("x"), {stmts=[], result=EIdent("y")}));
      eq(sg, "await", pe("await x"), EAwait(EIdent("x")));
      eq(sg, "throw", pe("throw e"), EThrow(EIdent("e")));
      match (pe("try { x } catch { E => 0 }")) {
        ETry(body, catchVar, cases) => {
          eq(sg, "try body result", body.result, EIdent("x"));
          eq(sg, "try catch var none", catchVar, None);
          eq(sg, "try cases len", Lst.length(cases), 1)
        },
        _ => isTrue(sg, "expected ETry", False)
      }
    });

    // ── Lambdas ───────────────────────────────────────────────────────────────

    group(s1, "lambdas", (sg: Suite) => {
      eq(sg, "typed param lambda", pe("(x: Int) => x"),
        ELambda(False, [], [{name="x", type_=Some(ATPrim("Int"))}], EIdent("x")));
      eq(sg, "untyped param lambda", pe("(x) => x"),
        ELambda(False, [], [{name="x", type_=None}], EIdent("x")));
      match (pe("(x, y) => x")) {
        ELambda(asyncFlag, typeParams, params, body) =>
          eq(sg, "two param lambda", Lst.length(params), 2),
        _ => isTrue(sg, "expected two-param lambda", False)
      };
      eq(sg, "async lambda", pe("async (x) => x"),
        ELambda(True, [], [{name="x", type_=None}], EIdent("x")));
      eq(sg, "paren grouping not lambda", pe("(x)"), EIdent("x"))
    });

    // ── Match expressions ─────────────────────────────────────────────────────

    group(s1, "match", (sg: Suite) => {
      eq(sg, "match basic", pe("match (x) { 1 => 2 }"),
        EMatch(EIdent("x"), [{pattern=PLit("int","1"), body=ELit("int","2")}]));
      match (pe("match (x) { 1 => 2, 3 => 4 }")) {
        EMatch(_, cases) => eq(sg, "two cases", Lst.length(cases), 2),
        _ => isTrue(sg, "expected two-case EMatch", False)
      };
      match (pe("match (x) { _ => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) => eq(sg, "wildcard arm", c.pattern, PWild),
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected EMatch wild", False)
      };
      match (pe("match (x) { v => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) => eq(sg, "var arm", c.pattern, PVar("v")),
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected EMatch var", False)
      };
      match (pe("match (x) { Some(v) => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) =>
              match (c.pattern) {
                PCon(conName, conFields) => {
                  eq(sg, "con pattern name", conName, "Some");
                  eq(sg, "con fields len", Lst.length(conFields), 1)
                },
                _ => isTrue(sg, "expected PCon", False)
              },
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected EMatch con", False)
      }
    });

    // ── Collections and records ───────────────────────────────────────────────

    group(s1, "collections/records", (sg: Suite) => {
      eq(sg, "list three", pe("[1, 2, 3]"),
        EList([LElem(ELit("int","1")), LElem(ELit("int","2")), LElem(ELit("int","3"))]));
      eq(sg, "list empty", pe("[]"), EList([]));
      eq(sg, "list spread", pe("[...xs, 1]"),
        EList([LSpread(EIdent("xs")), LElem(ELit("int","1"))]));
      eq(sg, "record two fields", pe("{x = 1, y = 2}"),
        ERecord(None, [{name="x",mut_=False,value=ELit("int","1")}, {name="y",mut_=False,value=ELit("int","2")}]));
      eq(sg, "record mut field", pe("{mut x = 1}"),
        ERecord(None, [{name="x",mut_=True,value=ELit("int","1")}]));
      match (pe("{...r, x = 1}")) {
        ERecord(spreadExpr, fields) => {
          eq(sg, "record spread expr", spreadExpr, Some(EIdent("r")));
          eq(sg, "record spread fields", Lst.length(fields), 1)
        },
        _ => isTrue(sg, "expected ERecord spread", False)
      };
      eq(sg, "record empty", pe("{}"), ERecord(None, []));
      eq(sg, "tuple two", pe("(1, 2)"), ETuple([ELit("int","1"), ELit("int","2")]));
      match (pe("(1, 2, 3)")) {
        ETuple(elems) => eq(sg, "tuple three", Lst.length(elems), 3),
        _ => isTrue(sg, "expected ETuple three", False)
      }
    });

    // ── Blocks ────────────────────────────────────────────────────────────────

    group(s1, "blocks", (sg: Suite) => {
      eq(sg, "block simple", pe("{x}"), EBlock({stmts=[], result=EIdent("x")}));
      eq(sg, "block val", pe("{val x = 1; x}"),
        EBlock({stmts=[SVal("x",None,ELit("int","1"))], result=EIdent("x")}));
      match (pe("{var x = 1; x := 2; x}")) {
        EBlock(blk) => {
          eq(sg, "block var assign stmts", Lst.length(blk.stmts), 2);
          eq(sg, "block var assign result", blk.result, EIdent("x"))
        },
        _ => isTrue(sg, "expected EBlock assign", False)
      };
      match (pe("{1; 2}")) {
        EBlock(blk) => {
          eq(sg, "block expr stmts len", Lst.length(blk.stmts), 1);
          eq(sg, "block expr result", blk.result, ELit("int","2"))
        },
        _ => isTrue(sg, "expected EBlock two exprs", False)
      };
      match (pe("{break}")) {
        EBlock(blk) => {
          eq(sg, "block break stmts len", Lst.length(blk.stmts), 1);
          eq(sg, "block break result", blk.result, ENever)
        },
        _ => isTrue(sg, "expected EBlock break", False)
      }
    });

    // ── Template strings ──────────────────────────────────────────────────────

    group(s1, "templates", (sg: Suite) => {
      val tmpl1 = "\"\u{24}{x}\""
      eq(sg, "template interp", pe(tmpl1), ETemplate([TmplExpr(EIdent("x"))]));
      val tmpl2 = "\"hello \u{24}{name}\""
      eq(sg, "template lit then interp", pe(tmpl2),
        ETemplate([TmplLit("hello "), TmplExpr(EIdent("name"))]));
      val tmpl3 = "\"\u{24}name\""
      eq(sg, "template short dollar", pe(tmpl3), ETemplate([TmplExpr(EIdent("name"))]));
      val tmpl4 = "\"a \u{24}{1 + 2} b\""
      eq(sg, "template complex", pe(tmpl4),
        ETemplate([TmplLit("a "), TmplExpr(EBinary("+", ELit("int","1"), ELit("int","2"))), TmplLit(" b")]))
    });

    // ── Type annotations ──────────────────────────────────────────────────────

    group(s1, "type annotations", (sg: Suite) => {
      match (firstDecl("fun f(x: Int): Bool = True")) {
        TDFun(fd) => {
          match (Lst.head(fd.params)) {
            Some(pm) => eq(sg, "prim param type", pm.type_, Some(ATPrim("Int"))),
            None => isTrue(sg, "expected param", False)
          };
          eq(sg, "prim return type", fd.retType, ATPrim("Bool"))
        },
        _ => isTrue(sg, "expected annotated fun", False)
      };
      match (firstDecl("fun f(x: List<Int>): Unit = ()")) {
        TDFun(fd) => {
          match (Lst.head(fd.params)) {
            Some(pm) => eq(sg, "app param type", pm.type_, Some(ATApp("List", [ATPrim("Int")]))),
            None => isTrue(sg, "expected param", False)
          }
        },
        _ => isTrue(sg, "expected app type fun", False)
      };
      match (firstDecl("fun f(x: Int -> Bool): Unit = ()")) {
        TDFun(fd) => {
          match (Lst.head(fd.params)) {
            Some(pm) => eq(sg, "arrow param type", pm.type_, Some(ATArrow([ATPrim("Int")], ATPrim("Bool")))),
            None => isTrue(sg, "expected param", False)
          }
        },
        _ => isTrue(sg, "expected arrow type fun", False)
      };
      match (firstDecl("fun f(x: {a: Int}): Unit = ()")) {
        TDFun(fd) => {
          match (Lst.head(fd.params)) {
            Some(pm) =>
              match (pm.type_) {
                Some(ATRecord(fields)) => eq(sg, "record type fields", Lst.length(fields), 1),
                _ => isTrue(sg, "expected ATRecord", False)
              },
            None => isTrue(sg, "expected param", False)
          }
        },
        _ => isTrue(sg, "expected record type fun", False)
      };
      match (firstDecl("fun f(x: A | B): Unit = ()")) {
        TDFun(fd) => {
          match (Lst.head(fd.params)) {
            Some(pm) =>
              match (pm.type_) {
                Some(ATUnion(leftType, rightType)) => {
                  eq(sg, "union left", leftType, ATIdent("A"));
                  eq(sg, "union right", rightType, ATIdent("B"))
                },
                _ => isTrue(sg, "expected ATUnion", False)
              },
            None => isTrue(sg, "expected param", False)
          }
        },
        _ => isTrue(sg, "expected union type fun", False)
      };
      match (firstDecl("fun f(x: A * B): Unit = ()")) {
        TDFun(fd) => {
          match (Lst.head(fd.params)) {
            Some(pm) =>
              match (pm.type_) {
                Some(ATTuple(typeElems)) => eq(sg, "tuple type len", Lst.length(typeElems), 2),
                _ => isTrue(sg, "expected ATTuple", False)
              },
            None => isTrue(sg, "expected param", False)
          }
        },
        _ => isTrue(sg, "expected tuple type fun", False)
      }
    });

    // ── Patterns ──────────────────────────────────────────────────────────────

    group(s1, "patterns", (sg: Suite) => {
      match (pe("match (x) { _ => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) => eq(sg, "wildcard", c.pattern, PWild),
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected match wild", False)
      };
      match (pe("match (x) { v => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) => eq(sg, "var pattern", c.pattern, PVar("v")),
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected match var", False)
      };
      match (pe("match (x) { 42 => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) => eq(sg, "int lit pattern", c.pattern, PLit("int","42")),
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected match int lit", False)
      };
      match (pe("match (x) { 3.14 => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) => eq(sg, "float lit pattern", c.pattern, PLit("float","3.14")),
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected match float", False)
      };
      match (pe("match (x) { \"s\" => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) => eq(sg, "string lit pattern", c.pattern, PLit("string","s")),
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected match string", False)
      };
      match (pe("match (x) { True => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) => eq(sg, "True pattern", c.pattern, PCon("True",[])),
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected match True", False)
      };
      match (pe("match (x) { None => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) => eq(sg, "None pattern", c.pattern, PCon("None",[])),
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected match None", False)
      };
      match (pe("match (x) { Some(v) => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) =>
              match (c.pattern) {
                PCon(conName, conFields) => {
                  eq(sg, "positional con name", conName, "Some");
                  eq(sg, "positional field name", Opt.getOrElse(Lst.head(Lst.map(conFields, (f: Ast.ConField) => f.name)), ""), "__field_0")
                },
                _ => isTrue(sg, "expected PCon Some", False)
              },
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected match constructor", False)
      };
      match (pe("match (x) { [a, b] => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) =>
              match (c.pattern) {
                PList(elems, rest) => {
                  eq(sg, "list pattern len", Lst.length(elems), 2);
                  eq(sg, "list pattern no rest", rest, None)
                },
                _ => isTrue(sg, "expected PList", False)
              },
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected match list", False)
      };
      match (pe("match (x) { [a, ...xs] => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) =>
              match (c.pattern) {
                PList(elems, rest) => {
                  eq(sg, "list rest elems", Lst.length(elems), 1);
                  eq(sg, "list rest name", rest, Some("xs"))
                },
                _ => isTrue(sg, "expected PList rest", False)
              },
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected match list rest", False)
      };
      match (pe("match (x) { [] => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) => eq(sg, "empty list pattern", c.pattern, PList([], None)),
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected match empty list", False)
      };
      match (pe("match (x) { h :: t => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) => eq(sg, "cons pattern", c.pattern, PCons(PVar("h"), PVar("t"))),
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected match cons", False)
      };
      match (pe("match (x) { (a, b) => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) => eq(sg, "tuple pattern", c.pattern, PTuple([PVar("a"), PVar("b")])),
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected match tuple", False)
      };
      match (pe("match (x) { () => 0 }")) {
        EMatch(_, cases) =>
          match (Lst.head(cases)) {
            Some(c) => eq(sg, "unit pattern", c.pattern, PLit("unit","()")),
            None => isTrue(sg, "expected case", False)
          },
        _ => isTrue(sg, "expected match unit", False)
      }
    })

  })
