// Tests for kestrel:dev/doc/render
import { Suite, group, eq, isTrue, isFalse } from "kestrel:dev/test"
import { renderModuleList, renderModule, renderDeclaration, staticCss, staticJs } from "kestrel:dev/doc/render"
import { DocModule, DocEntry, extract } from "kestrel:dev/doc/extract"
import { DKFun, DKVal } from "kestrel:dev/doc/extract"
import * as Str from "kestrel:data/string"
import * as Lst from "kestrel:data/list"

// ── Helpers ───────────────────────────────────────────────────────────────────

fun mkMod(spec: String, src: String): DocModule = extract(src, spec)

fun mod1(): DocModule =
  mkMod("kestrel:data/foo", "/// Adds two numbers.\nexport fun add(a: Int, b: Int): Int = a + b\n/// The answer.\nexport val answer: Int = 42\n")

fun mod2(): DocModule =
  mkMod("kestrel:data/bar", "//! Bar module.\nexport fun bar(): Unit = ()\n")

fun modLongFun(): DocModule =
  mkMod("kestrel:data/long", "/// Long function.\nexport fun reallyLongFunctionName(parameterOne: SomeVeryLongTypeName, parameterTwo: AnotherLongTypeName): ResultTypeWithLongName = todo()\n")

fun modInferredBindings(): DocModule =
  mkMod("kestrel:data/infer", "export val answer = 42\nexport var counter = 0\n")

fun modFallbackBinding(): DocModule =
  mkMod("kestrel:data/fallback", "export val broken = (\n")

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:dev/doc/render", (sg: Suite) => {

    // ── renderModuleList: empty ────────────────────────────────────────────────
    group(sg, "renderModuleList([]) returns valid HTML without crash", (g: Suite) => {
      val out = renderModuleList([])
      isTrue(g, "has <!DOCTYPE>",   Str.contains("<!DOCTYPE html>", out));
      isTrue(g, "has </html>",      Str.contains("</html>", out));
      isTrue(g, "has no crash",     !Str.isEmpty(out))
    });

    // ── renderModuleList: one module ──────────────────────────────────────────
    group(sg, "renderModuleList([mod]) contains module link", (g: Suite) => {
      val out = renderModuleList([mod1()])
      isTrue(g, "has link",   Str.contains("kestrel:data/foo", out));
      isTrue(g, "has <ul>",   Str.contains("<ul", out));
      isTrue(g, "has <li>",   Str.contains("<li>", out))
    });

    // ── renderModuleList: multiple modules ────────────────────────────────────
    group(sg, "renderModuleList([a, b]) contains both module links", (g: Suite) => {
      val out = renderModuleList([mod1(), mod2()])
      isTrue(g, "has foo", Str.contains("kestrel:data/foo", out));
      isTrue(g, "has bar", Str.contains("kestrel:data/bar", out))
    });

    // ── renderModule: contains entry headings ─────────────────────────────────
    group(sg, "renderModule contains section headings for each entry", (g: Suite) => {
      val out = renderModule(mod1())
      isTrue(g, "has add section",    Str.contains("id=\"add\"", out));
      isTrue(g, "has answer section", Str.contains("id=\"answer\"", out));
      isTrue(g, "has <h2>",           Str.contains("<h2", out))
    });

    // ── renderModule: contains signature code block ───────────────────────────
    group(sg, "renderModule contains signature in <pre><code>", (g: Suite) => {
      val out = renderModule(mod1())
      isTrue(g, "has kestrel code",  Str.contains("class=\"kestrel\"", out));
      isTrue(g, "has fun add sig",   Str.contains("fun add", out))
    });

    group(sg, "renderModule shows inferred val/var signatures", (g: Suite) => {
      val out = renderModule(modInferredBindings())
      isTrue(g, "has inferred val signature", Str.contains("val answer: Int", out));
      isTrue(g, "has inferred var signature", Str.contains("var counter: Int", out))
    });

    group(sg, "renderModule shows fallback signature marker when inference fails", (g: Suite) => {
      val out = renderModule(modFallbackBinding())
      isTrue(g, "has fallback marker", Str.contains("&lt;inference-unavailable&gt;", out))
    });

    group(sg, "renderModule renders short function signatures as multiline", (g: Suite) => {
      val out = renderModule(mod1())
      isTrue(g, "has multiline short function", Str.contains("fun add(\n", out));
      isTrue(g, "has indented short parameter", Str.contains("\n  a: Int,\n", out));
      isTrue(g, "keeps return type on closing line", Str.contains("\n): Int", out))
    });

    group(sg, "renderModule renders long function signatures as multiline", (g: Suite) => {
      val out = renderModule(modLongFun())
      isTrue(g, "has multiline open paren", Str.contains("reallyLongFunctionName(\n", out));
      isTrue(g, "has indented parameter line", Str.contains("\n  parameterTwo: AnotherLongTypeName", out));
      isFalse(g, "does not use ellipsis", Str.contains(" …", out))
    });

    // ── renderModule: renders doc prose ───────────────────────────────────────
    group(sg, "renderModule renders doc body as HTML", (g: Suite) => {
      val out = renderModule(mod1())
      isTrue(g, "has doc text",   Str.contains("Adds two numbers.", out));
      isTrue(g, "has The answer", Str.contains("The answer.", out))
    });

    // ── renderModule: module prose ────────────────────────────────────────────
    group(sg, "renderModule includes module prose when present", (g: Suite) => {
      val out = renderModule(mod2())
      isTrue(g, "has module prose", Str.contains("Bar module.", out))
    });

    // ── renderModule: module spec in title ────────────────────────────────────
    group(sg, "renderModule includes moduleSpec in page title", (g: Suite) => {
      val out = renderModule(mod1())
      isTrue(g, "spec in title", Str.contains("kestrel:data/foo", out))
    });

    // ── renderDeclaration: existing entry ─────────────────────────────────────
    group(sg, "renderDeclaration for existing entry returns section HTML", (g: Suite) => {
      val out = renderDeclaration(mod1(), "add")
      isTrue(g, "has section",  Str.contains("<section", out));
      isTrue(g, "has id",       Str.contains("id=\"add\"", out));
      isTrue(g, "has sig",      Str.contains("fun add", out))
    });

    // ── renderDeclaration: missing entry ──────────────────────────────────────
    group(sg, "renderDeclaration for missing entry returns not-found fragment", (g: Suite) => {
      val out = renderDeclaration(mod1(), "missing")
      isTrue(g, "has not-found class",  Str.contains("not-found", out));
      isTrue(g, "mentions missing",     Str.contains("missing", out))
    });

    // ── renderModule: declaration index present ───────────────────────────────
    group(sg, "renderModule includes a sidebar declaration index", (g: Suite) => {
      val out = renderModule(mod1())
      isTrue(g, "has sidebar aside",   Str.contains("module-sidebar", out));
      isTrue(g, "has nav",             Str.contains("<nav class=\"decl-index\"", out));
      isTrue(g, "has index title",     Str.contains("decl-index-title", out));
      isTrue(g, "has index link #add",    Str.contains("#add", out));
      isTrue(g, "has index link #answer", Str.contains("#answer", out))
    });

    // ── renderModule: index is sorted alphabetically ──────────────────────────
    group(sg, "renderModule index is sorted alphabetically", (g: Suite) => {
      // mod1 has 'add' and 'answer'; alphabetically 'add' < 'answer'
      val out = renderModule(mod1());
      val iAdd    = Str.indexOf(out, "#add");
      val iAnswer = Str.indexOf(out, "#answer");
      isTrue(g, "add appears before answer in index", iAdd < iAnswer)
    });

    // ── renderModule: index shows kind labels ─────────────────────────────────
    group(sg, "renderModule index shows kind labels", (g: Suite) => {
      val out = renderModule(mod1())
      isTrue(g, "has 'fun' kind label", Str.contains("idx-kind", out));
      isTrue(g, "has fun text",         Str.contains(">fun<", out));
      isTrue(g, "has val text",         Str.contains(">val<", out))
    });

    // ── renderModule: no index for empty module ───────────────────────────────
    group(sg, "renderModule omits index when module has no entries", (g: Suite) => {
      val empty = mkMod("kestrel:empty", "//! Empty module.\n")
      val out = renderModule(empty)
      isFalse(g, "no sidebar element", Str.contains("module-sidebar", out))
    });

    // ── staticCss ─────────────────────────────────────────────────────────────
    group(sg, "staticCss returns non-empty CSS", (g: Suite) => {
      val css = staticCss()
      isTrue(g, "non-empty",      !Str.isEmpty(css));
      isTrue(g, "has body rule",  Str.contains("body", css));
      isTrue(g, "has font-family", Str.contains("font-family", css))
    });

    // ── staticJs ──────────────────────────────────────────────────────────────
    group(sg, "staticJs returns non-empty JavaScript", (g: Suite) => {
      val js = staticJs()
      isTrue(g, "non-empty",         !Str.isEmpty(js));
      isTrue(g, "has search",        Str.contains("search", js));
      isTrue(g, "has fetch",         Str.contains("fetch", js));
      isTrue(g, "uses h.moduleSpec", Str.contains("h.moduleSpec", js));
      isTrue(g, "uses h.name",       Str.contains("h.name", js));
      isFalse(g, "no h.url",         Str.contains("h.url", js));
      isFalse(g, "no h.label",       Str.contains("h.label", js))
    })

  })
