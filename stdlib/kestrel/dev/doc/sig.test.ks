// Tests for kestrel:dev/doc/sig
import { Suite, group, eq, isTrue, isFalse } from "kestrel:dev/test"
import { format, formatWith } from "kestrel:dev/doc/sig"
import { DocEntry, DKFun, DKType, DKVal, DKVar, DKException, DKExternFun, DKExternType } from "kestrel:dev/doc/extract"
import * as Str from "kestrel:data/string"

// ── Helper: build a DocEntry ──────────────────────────────────────────────────

fun mkEntry(kind: DocKind, name: String, sig: String): DocEntry =
  { name = name, kind = kind, signature = sig, doc = "" }

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:dev/doc/sig", (sg: Suite) => {

    // ── DKFun minimal ─────────────────────────────────────────────────────────
    group(sg, "DKFun: simple function signature", (g: Suite) => {
      val e = mkEntry(DKFun, "foo", "fun foo(): Unit")
      eq(g, "format", format(e), "fun foo(): Unit")
    });

    // ── DKFun with type parameters ────────────────────────────────────────────
    group(sg, "DKFun: generic function signature", (g: Suite) => {
      val e = mkEntry(DKFun, "map", "fun map<A, B>(xs: List<A>, f: A -> B): List<B>")
      eq(g, "format", format(e), "fun map<A, B>(xs: List<A>, f: A -> B): List<B>")
    });

    // ── DKFun leading/trailing whitespace stripped ─────────────────────────────
    group(sg, "DKFun: leading/trailing whitespace stripped", (g: Suite) => {
      val e = mkEntry(DKFun, "f", "  fun f(): Int  ")
      eq(g, "trimmed", format(e), "fun f(): Int")
    });

    // ── DKType minimal (no body) ───────────────────────────────────────────────
    group(sg, "DKType: simple type signature", (g: Suite) => {
      val e = mkEntry(DKType, "Bool", "type Bool")
      eq(g, "format", format(e), "type Bool")
    });

    // ── DKType with type parameter ──────────────────────────────────────────
    group(sg, "DKType: generic type signature", (g: Suite) => {
      val e = mkEntry(DKType, "Option", "type Option<A>")
      eq(g, "format", format(e), "type Option<A>")
    });

    // ── DKType with full ADT body ───────────────────────────────────────────
    group(sg, "DKType: full ADT body preserved verbatim", (g: Suite) => {
      val body = "type CliOptionKind = Flag | Value(String)"
      val e = mkEntry(DKType, "CliOptionKind", body)
      eq(g, "format", format(e), body)
    });

    // ── DKType long body is NOT truncated ─────────────────────────────────────
    group(sg, "DKType: long signature is not truncated", (g: Suite) => {
      // 130-char type body (longer than the 120 limit applied to non-types)
      val longBody = "type E = A | B | C | D | E | F | G | H | I | J | K | L | M | N | O | P | Q | R | S | T | U | V | W | X | Y | Z | AA"
      val e = mkEntry(DKType, "E", longBody)
      val out = format(e);
      eq(g, "not truncated", out, longBody);
      isFalse(g, "no ellipsis", Str.endsWith(" …", out))
    });

    // ── DKVal ─────────────────────────────────────────────────────────────────
    group(sg, "DKVal signature", (g: Suite) => {
      val e = mkEntry(DKVal, "PI", "val PI: Float")
      eq(g, "format", format(e), "val PI: Float")
    });

    // ── DKVar ─────────────────────────────────────────────────────────────────
    group(sg, "DKVar signature", (g: Suite) => {
      val e = mkEntry(DKVar, "counter", "var counter: Int")
      eq(g, "format", format(e), "var counter: Int")
    });

    // ── DKException no payload ────────────────────────────────────────────────
    group(sg, "DKException no payload", (g: Suite) => {
      val e = mkEntry(DKException, "Error", "exception Error")
      eq(g, "format", format(e), "exception Error")
    });

    // ── DKException with payload ──────────────────────────────────────────────
    group(sg, "DKException with payload", (g: Suite) => {
      val e = mkEntry(DKException, "ParseError", "exception ParseError(String)")
      eq(g, "format", format(e), "exception ParseError(String)")
    });

    // ── DKExternFun ───────────────────────────────────────────────────────────
    group(sg, "DKExternFun signature", (g: Suite) => {
      val e = mkEntry(DKExternFun, "jvmFn", "extern fun jvmFn(x: Int): String")
      eq(g, "format", format(e), "extern fun jvmFn(x: Int): String")
    });

    // ── DKExternType ──────────────────────────────────────────────────────────
    group(sg, "DKExternType signature", (g: Suite) => {
      val e = mkEntry(DKExternType, "Socket", "extern type Socket")
      eq(g, "format", format(e), "extern type Socket")
    });

    // ── Long signature truncated at 120 chars ──────────────────────────────────
    group(sg, "long signature truncated at 120 chars", (g: Suite) => {
      // Build a 125-character signature
      val longSig = "fun reallyLongFunctionName(parameterOne: SomeVeryLongTypeName, parameterTwo: AnotherLongTypeName): ResultTypeWithLongName"
      val e = mkEntry(DKFun, "reallyLongFunctionName", longSig)
      val out = format(e)
      isTrue(g, "length <= 120 + 2", Str.length(out) <= 122);
      isTrue(g, "ends with ellipsis", Str.endsWith(" …", out))
    });

    group(sg, "long function signature can be rendered as multiline", (g: Suite) => {
      val longSig = "fun reallyLongFunctionName(parameterOne: SomeVeryLongTypeName, parameterTwo: AnotherLongTypeName): ResultTypeWithLongName"
      val e = mkEntry(DKFun, "reallyLongFunctionName", longSig)
      val out = formatWith(e, { multilineFunctions = True })
      isTrue(g, "contains newline after open paren", Str.contains("(\n", out));
      isTrue(g, "contains indented second parameter", Str.contains("\n  parameterTwo: AnotherLongTypeName", out));
      isTrue(g, "closing line keeps return type", Str.contains("\n): ResultTypeWithLongName", out));
      isFalse(g, "no ellipsis", Str.endsWith(" …", out))
    });

    group(sg, "short function signature can be rendered as multiline", (g: Suite) => {
      val e = mkEntry(DKFun, "add", "fun add(a: Int, b: Int): Int")
      val out = formatWith(e, { multilineFunctions = True })
      isTrue(g, "contains newline after open paren", Str.contains("(\n", out));
      isTrue(g, "contains first parameter line", Str.contains("\n  a: Int,\n", out));
      isTrue(g, "contains second parameter line", Str.contains("\n  b: Int\n", out));
      isTrue(g, "closing line keeps return type", Str.contains("\n): Int", out))
    });

    // ── Exactly 120 chars not truncated ──────────────────────────────────────
    group(sg, "exactly 120 chars not truncated", (g: Suite) => {
      // Build a 120-character string for padding
      val s120 = Str.repeat(120, "x")
      val e = mkEntry(DKFun, "f", s120)
      val out = format(e)
      eq(g, "not truncated", out, s120)
    })

  })
