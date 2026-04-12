// Tests for kestrel:dev/doc/markdown
import { Suite, group, eq, isTrue, isFalse } from "kestrel:dev/test"
import { render, renderInline } from "kestrel:dev/doc/markdown"
import * as Str from "kestrel:data/string"

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:dev/doc/markdown", (sg: Suite) => {

    // ── Empty / whitespace-only ───────────────────────────────────────────────
    group(sg, "empty input returns empty string", (g: Suite) => {
      eq(g, "empty",     render(""), "");
      eq(g, "whitespace", render("   \n  "), "")
    });

    // ── Plain paragraph ───────────────────────────────────────────────────────
    group(sg, "plain paragraph wrapped in <p>", (g: Suite) => {
      val out = render("Hello world.")
      eq(g, "contains <p>",    Str.contains("<p>Hello world.</p>", out), True)
    });

    // ── Multi-line paragraph (soft wrap) ─────────────────────────────────────
    group(sg, "multi-line paragraph joined with space", (g: Suite) => {
      val out = render("Line one.\nLine two.")
      isTrue(g, "contains both lines joined", Str.contains("Line one. Line two.", out))
    });

    // ── ATX headings ─────────────────────────────────────────────────────────
    group(sg, "ATX headings h1–h6", (g: Suite) => {
      isTrue(g, "h1", Str.contains("<h1>Title</h1>",     render("# Title")));
      isTrue(g, "h2", Str.contains("<h2>Sub</h2>",       render("## Sub")));
      isTrue(g, "h3", Str.contains("<h3>Third</h3>",     render("### Third")));
      isTrue(g, "h4", Str.contains("<h4>Four</h4>",      render("#### Four")));
      isTrue(g, "h5", Str.contains("<h5>Five</h5>",      render("##### Five")));
      isTrue(g, "h6", Str.contains("<h6>Six</h6>",       render("###### Six")))
    });

    // ── Fenced code block (no lang) ───────────────────────────────────────────
    group(sg, "fenced code block without language tag", (g: Suite) => {
      val src = "```\nval x = 1\n```"
      val out = render(src)
      isTrue(g, "has <pre><code>",  Str.contains("<pre><code>", out));
      isTrue(g, "has code content", Str.contains("val x = 1", out));
      isTrue(g, "has </code></pre>", Str.contains("</code></pre>", out))
    });

    // ── Fenced code block (with lang) ─────────────────────────────────────────
    group(sg, "fenced code block with language tag", (g: Suite) => {
      val src = "```kestrel\nfun f(): Int = 0\n```"
      val out = render(src)
      isTrue(g, "has lang class", Str.contains("class=\"language-kestrel\"", out));
      isTrue(g, "has kw token",   Str.contains("<span class=\"tok-kw\">fun</span>", out));
      isTrue(g, "has type token", Str.contains("<span class=\"tok-type\">Int</span>", out));
      isTrue(g, "has lit token",  Str.contains("<span class=\"tok-lit\">0</span>", out))
    });

    // ── Fenced code block (ks alias) ─────────────────────────────────────────
    group(sg, "fenced code block with ks alias", (g: Suite) => {
      val src = "```ks\nval answer = 42\n```"
      val out = render(src)
      isTrue(g, "has lang class", Str.contains("class=\"language-ks\"", out));
      isTrue(g, "has kw token",   Str.contains("<span class=\"tok-kw\">val</span>", out));
      isTrue(g, "has lit token",  Str.contains("<span class=\"tok-lit\">42</span>", out))
    });

    // ── HTML entity escaping in code block ────────────────────────────────────
    group(sg, "fenced code block HTML-escapes content", (g: Suite) => {
      val src = "```\n<div> & </div>\n```"
      val out = render(src)
      isTrue(g, "amp escaped",  Str.contains("&amp;", out));
      isTrue(g, "lt escaped",   Str.contains("&lt;", out));
      isTrue(g, "gt escaped",   Str.contains("&gt;", out))
    });

    // ── Unordered list ─────────────────────────────────────────────────────────
    group(sg, "unordered list with - items", (g: Suite) => {
      val src = "- Item one\n- Item two\n- Item three"
      val out = render(src)
      isTrue(g, "has <ul>",    Str.contains("<ul>", out));
      isTrue(g, "has </ul>",   Str.contains("</ul>", out));
      isTrue(g, "item one",    Str.contains("<li>Item one</li>", out));
      isTrue(g, "item two",    Str.contains("<li>Item two</li>", out))
    });

    // ── Ordered list ───────────────────────────────────────────────────────────
    group(sg, "ordered list", (g: Suite) => {
      val src = "1. First\n2. Second\n3. Third"
      val out = render(src)
      isTrue(g, "has <ol>",   Str.contains("<ol>", out));
      isTrue(g, "has </ol>",  Str.contains("</ol>", out));
      isTrue(g, "first item", Str.contains("<li>First</li>", out));
      isTrue(g, "third item", Str.contains("<li>Third</li>", out))
    });

    // ── Blockquote ─────────────────────────────────────────────────────────────
    group(sg, "blockquote", (g: Suite) => {
      val out = render("> Some quoted text.")
      isTrue(g, "has <blockquote>",  Str.contains("<blockquote>", out));
      isTrue(g, "has content",       Str.contains("Some quoted text.", out));
      isTrue(g, "has </blockquote>", Str.contains("</blockquote>", out))
    });

    // ── Horizontal rule ───────────────────────────────────────────────────────
    group(sg, "horizontal rule ---", (g: Suite) => {
      val out = render("---")
      isTrue(g, "has <hr />", Str.contains("<hr />", out))
    });

    // ── Inline code ───────────────────────────────────────────────────────────
    group(sg, "inline code renders as <code>", (g: Suite) => {
      val out = renderInline("Use `List.map` to transform.")
      isTrue(g, "has <code>",  Str.contains("<code>List.map</code>", out))
    });

    // ── Inline code HTML-escapes content ────────────────────────────────────
    group(sg, "inline code content is HTML-escaped", (g: Suite) => {
      val out = renderInline("`a < b`")
      isTrue(g, "escaped lt", Str.contains("<code>a &lt; b</code>", out))
    });

    // ── Bold ** ───────────────────────────────────────────────────────────────
    group(sg, "bold **text** renders as <strong>", (g: Suite) => {
      val out = renderInline("This is **bold** text.")
      isTrue(g, "has <strong>", Str.contains("<strong>bold</strong>", out))
    });

    // ── Bold __ ───────────────────────────────────────────────────────────────
    group(sg, "bold __text__ renders as <strong>", (g: Suite) => {
      val out = renderInline("This is __bold__ text.")
      isTrue(g, "has <strong>", Str.contains("<strong>bold</strong>", out))
    });

    // ── Italic * ──────────────────────────────────────────────────────────────
    group(sg, "italic *text* renders as <em>", (g: Suite) => {
      val out = renderInline("This is *italic* text.")
      isTrue(g, "has <em>", Str.contains("<em>italic</em>", out))
    });

    // ── Italic _ ──────────────────────────────────────────────────────────────
    group(sg, "italic _text_ renders as <em>", (g: Suite) => {
      val out = renderInline("This is _italic_ text.")
      isTrue(g, "has <em>", Str.contains("<em>italic</em>", out))
    });

    // ── Link ──────────────────────────────────────────────────────────────────
    group(sg, "link [label](url) renders as <a>", (g: Suite) => {
      val out = renderInline("See [the docs](https://example.com) for details.")
      isTrue(g, "has <a>",     Str.contains("<a ", out));
      isTrue(g, "has href",    Str.contains("href=\"https://example.com\"", out));
      isTrue(g, "has label",   Str.contains("the docs", out));
      isTrue(g, "has </a>",    Str.contains("</a>", out))
    });

    // ── HTML entity escaping ──────────────────────────────────────────────────
    group(sg, "HTML entities are escaped in plain text", (g: Suite) => {
      val out = renderInline("a & b < c > d")
      isTrue(g, "amp",  Str.contains("&amp;", out));
      isTrue(g, "lt",   Str.contains("&lt;", out));
      isTrue(g, "gt",   Str.contains("&gt;", out))
    });

    // ── Bold inside list item ─────────────────────────────────────────────────
    group(sg, "bold inside list item", (g: Suite) => {
      val out = render("- **important** note")
      isTrue(g, "has <strong>",   Str.contains("<strong>important</strong>", out));
      isTrue(g, "inside <li>",    Str.contains("<li>", out))
    });

    // ── Two paragraphs separated by blank line ─────────────────────────────────
    group(sg, "blank line separates two paragraphs", (g: Suite) => {
      val out = render("First.\n\nSecond.")
      val p1 = Str.contains("<p>First.</p>", out)
      val p2 = Str.contains("<p>Second.</p>", out)
      isTrue(g, "p1", p1);
      isTrue(g, "p2", p2)
    })

  })
