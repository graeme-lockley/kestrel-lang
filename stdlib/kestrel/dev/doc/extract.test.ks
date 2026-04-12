// Tests for kestrel:dev/doc/extract
import { Suite, group, eq, isTrue, isFalse } from "kestrel:dev/test"
import { DocKind, DocEntry, DocModule, extract } from "kestrel:dev/doc/extract"
import { DKFun, DKType, DKVal, DKVar, DKException, DKExternType, DKExternFun } from "kestrel:dev/doc/extract"
import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"

// ── Helpers ───────────────────────────────────────────────────────────────────

fun entryNamed(entries: List<DocEntry>, name: String): Option<DocEntry> =
  Lst.head(Lst.filter(entries, (e: DocEntry) => Str.equals(e.name, name)))

// ── Tests ─────────────────────────────────────────────────────────────────────

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:dev/doc/extract", (sg: Suite) => {

    // ── No doc-comments ───────────────────────────────────────────────────────
    group(sg, "no doc-comments: all doc fields empty", (g: Suite) => {
      val src = "export fun add(a: Int, b: Int): Int = a + b\n\nexport val PI: Float = 3.14159\n";
      val mod = extract(src, "test:mod");
      val add = entryNamed(mod.entries, "add");
      val pi  = entryNamed(mod.entries, "PI");
      isTrue(g, "add present", add != None);
      isTrue(g, "pi present",  pi  != None);
      eq(g, "add doc empty", match (add) { Some(e) => e.doc, None => "x" }, "");
      eq(g, "pi doc empty",  match (pi)  { Some(e) => e.doc, None => "x" }, "")
    });

    // ── /// doc-comment before export fun ────────────────────────────────────
    group(sg, "/// doc comment attached to export fun", (g: Suite) => {
      val src = "/// Adds two integers.\nexport fun add(a: Int, b: Int): Int = a + b\n";
      val mod = extract(src, "test:mod");
      val add = entryNamed(mod.entries, "add");
      eq(g, "doc text", match (add) { Some(e) => e.doc, None => "none" }, "Adds two integers.");
      eq(g, "kind DKFun", match (add) { Some(e) => e.kind == DKFun, None => False }, True)
    });

    // ── Multi-line /// block ──────────────────────────────────────────────────
    group(sg, "multi-line /// doc comment", (g: Suite) => {
      val src = "/// Line one.\n/// Line two.\nexport fun foo(): Unit = ()\n";
      val mod = extract(src, "test:mod");
      val foo = entryNamed(mod.entries, "foo");
      eq(g, "doc text", match (foo) { Some(e) => e.doc, None => "none" }, "Line one.\nLine two.")
    });

    // ── //! module-level prose ────────────────────────────────────────────────
    group(sg, "//! module-level prose collected", (g: Suite) => {
      val src = "//! This is the module.\n//! Second line.\nexport fun f(): Unit = ()\n";
      val mod = extract(src, "test:mod");
      eq(g, "prose", mod.moduleProse, "This is the module.\nSecond line.")
    });

    // ── Blank line breaks doc association ────────────────────────────────────
    group(sg, "blank line between /// and export discards doc", (g: Suite) => {
      val src = "/// stale doc\n\nexport fun foo(): Unit = ()\n";
      val mod = extract(src, "test:mod");
      val foo = entryNamed(mod.entries, "foo");
      eq(g, "doc discarded", match (foo) { Some(e) => e.doc, None => "none" }, "")
    });

    // ── /** */ block doc-comment ──────────────────────────────────────────────
    group(sg, "/** */ block doc comment attached to export", (g: Suite) => {
      val src = "/** Does something useful.\n * See also: bar.\n */\nexport fun foo(): Unit = ()\n";
      val mod = extract(src, "test:mod");
      val foo = entryNamed(mod.entries, "foo");
      isTrue(g, "foo present",   foo != None);
      isTrue(g, "doc non-empty", match (foo) { Some(e) => !Str.isEmpty(e.doc), None => False })
    });

    // ── export type ───────────────────────────────────────────────────────────
    group(sg, "export type produces DKType entry", (g: Suite) => {
      val src = "/// An option type.\nexport type Option<A> = None | Some(A)\n";
      val mod = extract(src, "test:mod");
      val opt = entryNamed(mod.entries, "Option");
      eq(g, "kind DKType", match (opt) { Some(e) => e.kind == DKType, None => False }, True);
      eq(g, "doc",         match (opt) { Some(e) => e.doc, None => "none" }, "An option type.")
    });

    // ── export val ────────────────────────────────────────────────────────────
    group(sg, "export val produces DKVal entry", (g: Suite) => {
      val src = "/// Pi.\nexport val PI: Float = 3.14159\n";
      val mod = extract(src, "test:mod");
      val pi = entryNamed(mod.entries, "PI");
      eq(g, "kind DKVal", match (pi) { Some(e) => e.kind == DKVal, None => False }, True)
    });

    group(sg, "export val without annotation includes inferred signature type", (g: Suite) => {
      val src = "export val answer = 42\n";
      val mod = extract(src, "test:mod");
      val answer = entryNamed(mod.entries, "answer");
      val sig = match (answer) { Some(e) => e.signature, None => "none" };
      eq(g, "inferred val signature", sig, "val answer: Int")
    });

    // ── export var ────────────────────────────────────────────────────────────
    group(sg, "export var produces DKVar entry", (g: Suite) => {
      val src = "export var counter: Int = 0\n";
      val mod = extract(src, "test:mod");
      val c = entryNamed(mod.entries, "counter");
      eq(g, "kind DKVar", match (c) { Some(e) => e.kind == DKVar, None => False }, True)
    });

    group(sg, "export var without annotation includes inferred signature type", (g: Suite) => {
      val src = "export var counter = 0\n";
      val mod = extract(src, "test:mod");
      val c = entryNamed(mod.entries, "counter");
      val sig = match (c) { Some(e) => e.signature, None => "none" };
      eq(g, "inferred var signature", sig, "var counter: Int")
    });

    group(sg, "inference fallback marker when typecheck cannot resolve export", (g: Suite) => {
      val src = "export val broken = (\n";
      val mod = extract(src, "test:mod");
      val broken = entryNamed(mod.entries, "broken");
      val sig = match (broken) { Some(e) => e.signature, None => "none" };
      eq(g, "fallback marker", sig, "val broken: <inference-unavailable>")
    });

    // ── export exception ──────────────────────────────────────────────────────
    group(sg, "export exception produces DKException entry", (g: Suite) => {
      val src = "/// Parse failed.\nexport exception ParseError(String)\n";
      val mod = extract(src, "test:mod");
      val pe2 = entryNamed(mod.entries, "ParseError");
      eq(g, "kind DKException", match (pe2) { Some(e) => e.kind == DKException, None => False }, True);
      eq(g, "doc",              match (pe2) { Some(e) => e.doc, None => "none" }, "Parse failed.")
    });

    // ── export extern fun ─────────────────────────────────────────────────────
    group(sg, "export extern fun produces DKExternFun entry", (g: Suite) => {
      val src = "/// JVM helper.\nexport extern fun jvmFn(x: Int): String =\n  jvm(\"Some#method(java.lang.Object)\")\n";
      val mod = extract(src, "test:mod");
      val jf = entryNamed(mod.entries, "jvmFn");
      eq(g, "kind DKExternFun", match (jf) { Some(e) => e.kind == DKExternFun, None => False }, True)
    });

    // ── export extern type ────────────────────────────────────────────────────
    group(sg, "export extern type produces DKExternType entry", (g: Suite) => {
      val src = "/// Opaque socket.\nexport extern type Socket = jvm(\"java.net.Socket\")\n";
      val mod = extract(src, "test:mod");
      val sk = entryNamed(mod.entries, "Socket");
      eq(g, "kind DKExternType", match (sk) { Some(e) => e.kind == DKExternType, None => False }, True)
    });

    // ── Signature stops before = for fun ─────────────────────────────────────
    group(sg, "signature stops before = for fun", (g: Suite) => {
      val src = "export fun add(a: Int, b: Int): Int = a + b\n";
      val mod = extract(src, "test:mod");
      val add = entryNamed(mod.entries, "add");
      val sig = match (add) { Some(e) => e.signature, None => "none" };
      isTrue(g,  "sig has fun",        Str.startsWith("fun", sig));
      isFalse(g, "sig has no =",       Str.contains("=", sig));
      isTrue(g,  "sig has return type", Str.contains("Int", sig))
    });

    // ── Signature includes full ADT body for type ────────────────────────────
    group(sg, "type signature includes full ADT body after =", (g: Suite) => {
      val src = "export type Option<A> = None | Some(A)\n";
      val mod = extract(src, "test:mod");
      val opt = entryNamed(mod.entries, "Option");
      val sig = match (opt) { Some(e) => e.signature, None => "none" };
      isTrue(g, "sig starts with type",   Str.startsWith("type", sig));
      isTrue(g, "sig contains =",         Str.contains("=", sig));
      isTrue(g, "sig contains None",      Str.contains("None", sig));
      isTrue(g, "sig contains Some(A)",   Str.contains("Some(A)", sig))
    });

    // ── Inline flags-only ADT ─────────────────────────────────────────────────
    group(sg, "type signature: inline flags ADT", (g: Suite) => {
      val src = "export type CliOptionKind = Flag | Value(String)\n";
      val mod = extract(src, "test:mod");
      val e   = entryNamed(mod.entries, "CliOptionKind");
      val sig = match (e) { Some(x) => x.signature, None => "none" };
      isTrue(g, "has Flag",         Str.contains("Flag", sig));
      isTrue(g, "has Value(String)", Str.contains("Value(String)", sig))
    });

    // ── Multi-line ADT (| on continuation lines) ──────────────────────────────
    group(sg, "type signature: multi-line ADT", (g: Suite) => {
      val src = "export type Color =\n  Red\n  | Green\n  | Blue\n\nexport fun f(): Unit = ()\n";
      val mod = extract(src, "test:mod");
      val e   = entryNamed(mod.entries, "Color");
      val sig = match (e) { Some(x) => x.signature, None => "none" };
      isTrue(g, "has Red",   Str.contains("Red", sig));
      isTrue(g, "has Green", Str.contains("Green", sig));
      isTrue(g, "has Blue",  Str.contains("Blue", sig))
    });

    group(sg, "type signature stops before following export after comment", (g: Suite) => {
      val src = "export type AstType =\n  A\n  | B\n  | C\n\n/// helper\nexport fun astTypeTag(t: AstType): String = \"\"\n";
      val mod = extract(src, "test:mod");
      val e   = entryNamed(mod.entries, "AstType");
      val sig = match (e) { Some(x) => x.signature, None => "none" };
      isFalse(g, "does not include next export", Str.contains("export fun astTypeTag", sig));
      isTrue(g, "keeps final variant", Str.contains("| C", sig))
    });

    // ── Record type shows all fields ──────────────────────────────────────────
    group(sg, "type signature: record body fully captured", (g: Suite) => {
      val src = "export type Point = {\n  x: Int,\n  y: Int\n}\n";
      val mod = extract(src, "test:mod");
      val e   = entryNamed(mod.entries, "Point");
      val sig = match (e) { Some(x) => x.signature, None => "none" };
      isTrue(g, "has {",   Str.contains("{", sig));
      isTrue(g, "has x",   Str.contains("x", sig));
      isTrue(g, "has y",   Str.contains("y", sig));
      isTrue(g, "has }",   Str.contains("}", sig))
    });

    // ── Multiple exports each get own doc ─────────────────────────────────────
    group(sg, "consecutive exports each get their own doc", (g: Suite) => {
      val src = "/// Doc for foo.\nexport fun foo(): Unit = ()\n/// Doc for bar.\nexport fun bar(): Unit = ()\n";
      val mod = extract(src, "test:mod");
      val foo = entryNamed(mod.entries, "foo");
      val bar = entryNamed(mod.entries, "bar");
      eq(g, "foo doc", match (foo) { Some(e) => e.doc, None => "none" }, "Doc for foo.");
      eq(g, "bar doc", match (bar) { Some(e) => e.doc, None => "none" }, "Doc for bar.")
    });

    // ── export async fun ─────────────────────────────────────────────────────
    group(sg, "export async fun produces DKFun entry", (g: Suite) => {
      val src = "/// Async helper.\nexport async fun fetchData(): Task<String> = async { \"\" }\n";
      val mod = extract(src, "test:mod");
      val fd = entryNamed(mod.entries, "fetchData");
      eq(g, "kind DKFun", match (fd) { Some(e) => e.kind == DKFun, None => False }, True)
    });

    // ── moduleSpec stored ─────────────────────────────────────────────────────
    group(sg, "moduleSpec is stored in DocModule", (g: Suite) => {
      val mod = extract("export val x: Int = 1\n", "kestrel:data/foo");
      eq(g, "spec", mod.moduleSpec, "kestrel:data/foo")
    });

    // ── Entry count ───────────────────────────────────────────────────────────
    group(sg, "each export generates exactly one entry", (g: Suite) => {
      val src = "export fun a(): Unit = ()\nexport fun b(): Unit = ()\nexport val c: Int = 0\n";
      val mod = extract(src, "test:mod");
      eq(g, "entry count", Lst.length(mod.entries), 3)
    });

    // ── Regular comment between /// and export resets doc ────────────────────
    group(sg, "regular // comment resets doc block", (g: Suite) => {
      val src = "/// stale\n// break\nexport fun foo(): Unit = ()\n";
      val mod = extract(src, "test:mod");
      val foo = entryNamed(mod.entries, "foo");
      eq(g, "doc cleared", match (foo) { Some(e) => e.doc, None => "none" }, "")
    })

  })
