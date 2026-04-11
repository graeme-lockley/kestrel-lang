import { Suite, group, eq, isTrue, isFalse } from "kestrel:dev/test"
import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as Token from "kestrel:dev/parser/token"
import {
  TkInt, TkFloat, TkStr, TkTemplate, TkChar,
  TkIdent, TkUpper, TkKw, TkOp, TkPunct,
  TkWs, TkLineComment, TkBlockComment, TkEof,
  TPLiteral, TPInterp
} from "kestrel:dev/parser/token"
import { lex } from "kestrel:dev/parser/lexer"

// ─── Helpers ─────────────────────────────────────────────────────────────────

fun kindOf(src: String): Token.TokenKind =
  match (Lst.head(lex(src))) {
    Some(t) => t.kind,
    None => TkEof
  }

fun textOf(src: String): String =
  match (Lst.head(lex(src))) {
    Some(t) => t.text,
    None => ""
  }

fun allKinds(src: String): List<Token.TokenKind> =
  Lst.map(lex(src), (t: Token.Token) => t.kind)

fun joinTexts(src: String): String =
  Lst.foldl(lex(src), "", (acc: String, t: Token.Token) => Str.append(acc, t.text))

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:dev/parser/lexer", (s1: Suite) => {

    // ── Round-trip ────────────────────────────────────────────────────────────

    group(s1, "round-trip", (sg: Suite) => {
      eq(sg, "empty string", joinTexts(""), "");
      eq(sg, "fun main", joinTexts("fun main(): Unit = ()"), "fun main(): Unit = ()");
      eq(sg, "val with spaces", joinTexts("  val x = 1  "), "  val x = 1  ");
      eq(sg, "line comment + newline", joinTexts("// comment\nval x = 1"), "// comment\nval x = 1");
      eq(sg, "block comment", joinTexts("/* block */val x = 1"), "/* block */val x = 1");
      val str_src = "\"hello\""
      eq(sg, "string quotes preserved", joinTexts(str_src), str_src);
      val char_src = "'a'"
      eq(sg, "char quotes preserved", joinTexts(char_src), char_src);
      eq(sg, "comment between idents", joinTexts("x // c\ny"), "x // c\ny")
    });

    // ── Whitespace and comment tokens ─────────────────────────────────────────

    group(s1, "whitespace/comments", (sg: Suite) => {
      eq(sg, "spaces kind", kindOf("  "), TkWs);
      eq(sg, "newline kind", kindOf("\n"), TkWs);
      eq(sg, "tab+space text", textOf("\t "), "\t ");
      eq(sg, "line comment kind", kindOf("// hi"), TkLineComment);
      eq(sg, "line comment text", textOf("// hi there"), "// hi there");
      eq(sg, "block comment kind", kindOf("/* hi */"), TkBlockComment);
      eq(sg, "block comment text", textOf("/* hi */"), "/* hi */")
    });

    // ── Identifiers and keywords ──────────────────────────────────────────────

    group(s1, "identifiers/keywords", (sg: Suite) => {
      eq(sg, "ident kind", kindOf("foo"), TkIdent);
      eq(sg, "ident _ start", kindOf("_bar"), TkIdent);
      eq(sg, "ident text", textOf("myVar"), "myVar");
      eq(sg, "upper kind", kindOf("Foo"), TkUpper);
      eq(sg, "True is TkUpper", kindOf("True"), TkUpper);
      eq(sg, "False is TkUpper", kindOf("False"), TkUpper);
      // Keywords
      eq(sg, "kw as",         kindOf("as"),        TkKw);
      eq(sg, "kw fun",        kindOf("fun"),       TkKw);
      eq(sg, "kw type",       kindOf("type"),      TkKw);
      eq(sg, "kw val",        kindOf("val"),       TkKw);
      eq(sg, "kw var",        kindOf("var"),       TkKw);
      eq(sg, "kw mut",        kindOf("mut"),       TkKw);
      eq(sg, "kw if",         kindOf("if"),        TkKw);
      eq(sg, "kw else",       kindOf("else"),      TkKw);
      eq(sg, "kw while",      kindOf("while"),     TkKw);
      eq(sg, "kw break",      kindOf("break"),     TkKw);
      eq(sg, "kw continue",   kindOf("continue"),  TkKw);
      eq(sg, "kw match",      kindOf("match"),     TkKw);
      eq(sg, "kw try",        kindOf("try"),       TkKw);
      eq(sg, "kw catch",      kindOf("catch"),     TkKw);
      eq(sg, "kw throw",      kindOf("throw"),     TkKw);
      eq(sg, "kw async",      kindOf("async"),     TkKw);
      eq(sg, "kw await",      kindOf("await"),     TkKw);
      eq(sg, "kw export",     kindOf("export"),    TkKw);
      eq(sg, "kw import",     kindOf("import"),    TkKw);
      eq(sg, "kw from",       kindOf("from"),      TkKw);
      eq(sg, "kw exception",  kindOf("exception"), TkKw);
      eq(sg, "kw is",         kindOf("is"),        TkKw);
      eq(sg, "kw opaque",     kindOf("opaque"),    TkKw);
      eq(sg, "kw extern",     kindOf("extern"),    TkKw)
    });

    // ── Integer literals ──────────────────────────────────────────────────────

    group(s1, "integers", (sg: Suite) => {
      eq(sg, "int kind",        kindOf("42"),        TkInt);
      eq(sg, "int text",        textOf("42"),        "42");
      eq(sg, "zero kind",       kindOf("0"),         TkInt);
      eq(sg, "hex kind",        kindOf("0xff"),      TkInt);
      eq(sg, "hex text",        textOf("0xff"),      "0xff");
      eq(sg, "bin kind",        kindOf("0b101"),     TkInt);
      eq(sg, "bin text",        textOf("0b101"),     "0b101");
      eq(sg, "oct kind",        kindOf("0o77"),      TkInt);
      eq(sg, "underscore kind", kindOf("1_000_000"), TkInt);
      eq(sg, "underscore text", textOf("1_000_000"), "1_000_000")
    });

    // ── Float literals ────────────────────────────────────────────────────────

    group(s1, "floats", (sg: Suite) => {
      eq(sg, "float kind",    kindOf("3.14"),  TkFloat);
      eq(sg, "float text",    textOf("3.14"),  "3.14");
      eq(sg, "exp kind",      kindOf("1e10"),  TkFloat);
      eq(sg, "neg exp kind",  kindOf("1.5e-3"), TkFloat);
      eq(sg, "dot start",     kindOf(".5"),    TkFloat);
      eq(sg, "upper E",       kindOf("1E10"),  TkFloat)
    });

    // ── String literals ───────────────────────────────────────────────────────

    group(s1, "strings", (sg: Suite) => {
      val plain_src = "\"hello\""
      eq(sg, "str kind",    kindOf(plain_src), TkStr);
      eq(sg, "str text",    textOf(plain_src), plain_src);
      val esc_src = "\"a\\nb\""
      eq(sg, "escape preserved", textOf(esc_src), esc_src);
      // Template string tests
      val tmpl_src = "\"\u{24}{x}\""
      match (kindOf(tmpl_src)) {
        TkTemplate(parts) => {
          eq(sg, "template kind", True, True);
          eq(sg, "template parts length", Lst.length(parts), 1);
          match (Lst.head(parts)) {
            Some(p) => match (p) {
              TPInterp(src) => eq(sg, "interp content", src, "x"),
              _ => isTrue(sg, "expected TPInterp", False)
            },
            None => isTrue(sg, "expected part", False)
          }
        },
        _ => isTrue(sg, "expected TkTemplate", False)
      };
      val tmpl2 = "\"hello \u{24}{name}\""
      match (kindOf(tmpl2)) {
        TkTemplate(parts) => {
          eq(sg, "template2 parts count", Lst.length(parts), 2);
          match (Lst.head(parts)) {
            Some(p) => match (p) {
              TPLiteral(s) => eq(sg, "lit part 'hello '", s, "hello "),
              _ => isTrue(sg, "expected TPLiteral", False)
            },
            None => isTrue(sg, "expected head", False)
          }
        },
        _ => isTrue(sg, "expected TkTemplate", False)
      };
      val short_tmpl = "\"\u{24}name\""
      match (kindOf(short_tmpl)) {
        TkTemplate(parts) => eq(sg, "\u{24}ident parts count", Lst.length(parts), 1),
        _ => isTrue(sg, "expected TkTemplate for \u{24}ident", False)
      };
      val tmpl3 = "\"a \u{24}{1 + 2} b\""
      match (kindOf(tmpl3)) {
        TkTemplate(parts) => eq(sg, "complex template parts", Lst.length(parts), 3),
        _ => isTrue(sg, "expected TkTemplate for complex", False)
      };
      eq(sg, "template raw text", textOf(tmpl_src), tmpl_src)
    });

    // ── Char literals ─────────────────────────────────────────────────────────

    group(s1, "chars", (sg: Suite) => {
      val char_src = "'a'"
      eq(sg, "char kind", kindOf(char_src), TkChar);
      eq(sg, "char text", textOf(char_src), char_src);
      val esc_char = "'\\n'"
      eq(sg, "escape char text", textOf(esc_char), esc_char)
    });

    // ── Operators ─────────────────────────────────────────────────────────────

    group(s1, "operators", (sg: Suite) => {
      eq(sg, "=> kind",  kindOf("=>"),  TkOp);
      eq(sg, "=> text",  textOf("=>"),  "=>");
      eq(sg, ":= kind",  kindOf(":="),  TkOp);
      eq(sg, ":= text",  textOf(":="),  ":=");
      eq(sg, "== kind",  kindOf("=="),  TkOp);
      eq(sg, "== text",  textOf("=="),  "==");
      eq(sg, "!= kind",  kindOf("!="),  TkOp);
      eq(sg, "!= text",  textOf("!="),  "!=");
      eq(sg, ">= kind",  kindOf(">="),  TkOp);
      eq(sg, ">= text",  textOf(">="),  ">=");
      eq(sg, "<= kind",  kindOf("<="),  TkOp);
      eq(sg, "<= text",  textOf("<="),  "<=");
      eq(sg, "** kind",  kindOf("**"),  TkOp);
      eq(sg, "** text",  textOf("**"),  "**");
      eq(sg, "<| kind",  kindOf("<|"),  TkOp);
      eq(sg, "<| text",  textOf("<|"),  "<|");
      eq(sg, ":: kind",  kindOf("::"),  TkOp);
      eq(sg, ":: text",  textOf("::"),  "::");
      eq(sg, "|> kind",  kindOf("|>"),  TkOp);
      eq(sg, "|> text",  textOf("|>"),  "|>");
      eq(sg, "-> kind",  kindOf("->"),  TkOp);
      eq(sg, "-> text",  textOf("->"),  "->");
      eq(sg, "... kind", kindOf("..."), TkOp);
      eq(sg, "... text", textOf("..."), "...");
      eq(sg, "+ kind",   kindOf("+"),   TkOp);
      eq(sg, "- kind",   kindOf("-"),   TkOp);
      eq(sg, "! kind",   kindOf("!"),   TkOp)
    });

    // ── Punctuation ───────────────────────────────────────────────────────────

    group(s1, "punctuation", (sg: Suite) => {
      // colon vs double-colon disambiguation
      val colon_src = ": ::"
      val colon_kinds = allKinds(colon_src)
      eq(sg, ": :: kinds length", Lst.length(colon_kinds), 4);
      match (Lst.head(colon_kinds)) {
        Some(k) => eq(sg, ": is TkPunct", k, TkPunct),
        None => isTrue(sg, "expected head", False)
      };
      eq(sg, "( kind",  kindOf("("), TkPunct);
      eq(sg, "( text",  textOf("("), "(");
      eq(sg, ") kind",  kindOf(")"), TkPunct);
      eq(sg, "{ kind",  kindOf("{"), TkPunct);
      eq(sg, "} kind",  kindOf("}"), TkPunct);
      eq(sg, "[ kind",  kindOf("["), TkPunct);
      eq(sg, "] kind",  kindOf("]"), TkPunct);
      eq(sg, ", kind",  kindOf(","), TkPunct);
      eq(sg, ". kind",  kindOf("."), TkPunct);
      eq(sg, "; kind",  kindOf(";"), TkPunct)
    });

    // ── Span tracking ─────────────────────────────────────────────────────────

    group(s1, "spans", (sg: Suite) => {
      // "42": start=0, end=2, line=1, col=1
      match (Lst.head(lex("42"))) {
        Some(t) => {
          eq(sg, "span start=0", t.span.start, 0);
          eq(sg, "span end=2",   t.span.end,   2);
          eq(sg, "span line=1",  t.span.line,  1);
          eq(sg, "span col=1",   t.span.col,   1)
        },
        None => isTrue(sg, "expected token", False)
      };
      // "\nx": identifier x at line=2
      val newline_ident = "\nx"
      val toks_ni = lex(newline_ident)
      // tokens: TkWs("\n"), TkIdent("x"), TkEof
      match (Lst.head(Lst.tail(toks_ni))) {
        Some(t) => eq(sg, "x at line 2", t.span.line, 2),
        None => isTrue(sg, "expected ident token", False)
      };
      // "a\nb": second non-trivia token b at line 2
      val two_lines = "a\nb"
      val toks_tl = lex(two_lines)
      // TkIdent("a"), TkWs("\n"), TkIdent("b"), TkEof
      match (Lst.head(Lst.tail(Lst.tail(toks_tl)))) {
        Some(t) => eq(sg, "b at line 2", t.span.line, 2),
        None => isTrue(sg, "expected b token", False)
      }
    });

    // ── EOF token ─────────────────────────────────────────────────────────────

    group(s1, "EOF", (sg: Suite) => {
      val empty_toks = lex("")
      match (Lst.head(empty_toks)) {
        Some(t) => {
          eq(sg, "eof kind", t.kind, TkEof);
          eq(sg, "eof text", t.text, "")
        },
        None => isTrue(sg, "expected EOF token", False)
      };
      val x_toks = lex("x")
      eq(sg, "lex('x') length is 2", Lst.length(x_toks), 2)
    })

  })
