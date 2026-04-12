//! HTML fragment/page generator for `kestrel doc` browser.
//! Wires together the Markdown renderer, signature formatter, and `DocModule`
//! values into ready-to-serve HTML pages.
import * as Str from "kestrel:data/string"
import * as Lst from "kestrel:data/list"
import { DocModule, DocEntry, DKFun, DKType, DKVal, DKVar, DKException, DKExternType, DKExternFun } from "kestrel:dev/doc/extract"
import * as Md from "kestrel:dev/doc/markdown"
import * as Sig from "kestrel:dev/doc/sig"

// ── HTML escaping ─────────────────────────────────────────────────────────────

fun escapeHtml(s: String): String =
  Str.replace(">", "&gt;", Str.replace("<", "&lt;", Str.replace("&", "&amp;", s)))

fun escapeAttr(s: String): String =
  Str.replace("\"", "&quot;", escapeHtml(s))

// ── Page scaffold ─────────────────────────────────────────────────────────────

fun pageHead(title: String): String =
  Str.join("\n", [
    "<!DOCTYPE html>",
    "<html lang=\"en\">",
    "<head>",
    "  <meta charset=\"utf-8\">",
    "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
    "  <title>${escapeHtml(title)}</title>",
    "  <link rel=\"stylesheet\" href=\"/docs/static/style.css\">",
    "</head>",
    "<body>",
    "<header class=\"site-header\">",
    "  <a class=\"home-link\" href=\"/docs/\">Kestrel Docs</a>",
    "  <input class=\"search-box\" id=\"search\" type=\"search\" placeholder=\"Search…\" autocomplete=\"off\">",
    "  <div class=\"search-results\" id=\"search-results\"></div>",
    "</header>"
  ])

fun pageFooter(): String =
  Str.join("\n", [
    "<script src=\"/docs/static/search.js\"></script>",
    "</body>",
    "</html>"
  ])

fun page(title: String, body: String): String =
  "${pageHead(title)}\n<main>\n${body}\n</main>\n${pageFooter()}"

// ── Module list page ──────────────────────────────────────────────────────────

fun moduleListItem(mod: DocModule): String = {
  val spec = mod.moduleSpec
  "<li><a href=\"/docs/${escapeAttr(spec)}\">${escapeHtml(spec)}</a></li>"
}

/// Render the top-level module index page listing all known `DocModule` values.
export fun renderModuleList(modules: List<DocModule>): String = {
  val items = Str.join("\n    ", Lst.map(modules, (m: DocModule) => moduleListItem(m)))
  val listHtml =
    if (Lst.isEmpty(modules)) "<p>No modules found.</p>"
    else "<ul class=\"module-list\">\n    ${items}\n  </ul>"
  page("Kestrel Documentation", "<h1>Modules</h1>\n  ${listHtml}")
}

// ── Per-module page ───────────────────────────────────────────────────────────

// Short kind indicator shown in the declaration index.
fun kindLabel(e: DocEntry): String = match (e.kind) {
  DKFun        => "fun"
  DKType       => "type"
  DKVal        => "val"
  DKVar        => "var"
  DKException  => "exception"
  DKExternType => "extern type"
  DKExternFun  => "extern fun"
}

// Character-level string comparator (needed because < is not defined on String).
fun compareStrLoop(a: String, b: String, i: Int, la: Int, lb: Int): Int =
  if (i >= la & i >= lb) 0
  else if (i >= la) -1
  else if (i >= lb) 1
  else {
    val d = Str.codePointAt(a, i) - Str.codePointAt(b, i);
    if (d != 0) d else compareStrLoop(a, b, i + 1, la, lb)
  }

fun compareStr(a: String, b: String): Int =
  compareStrLoop(a, b, 0, Str.length(a), Str.length(b))

// One row in the declaration index.
fun indexItem(e: DocEntry): String =
  "<li><a href=\"#${escapeAttr(e.name)}\"><span class=\"idx-kind\">${escapeHtml(kindLabel(e))}</span>${escapeHtml(e.name)}</a></li>"

// Render a sorted sidebar <nav> index for the module.
fun renderIndex(entries: List<DocEntry>): String = {
  val sorted = Lst.sortWith(
    (a: DocEntry, b: DocEntry) => compareStr(a.name, b.name),
    entries
  );
  val items = Str.join("\n    ", Lst.map(sorted, (e: DocEntry) => indexItem(e)));
  "<nav class=\"decl-index\">\n<div class=\"decl-index-title\">Index (${Lst.length(entries)})</div>\n<ul>\n    ${items}\n</ul>\n</nav>"
}

fun renderEntry(entry: DocEntry): String = {
  val sig     = Sig.formatWith(entry, { multilineFunctions = True })
  val docHtml = if (Str.isEmpty(entry.doc)) "" else Md.render(entry.doc)
  val docDiv  =
    if (Str.isEmpty(docHtml)) ""
    else "  <div class=\"doc-body\">${docHtml}</div>\n"
  "<section class=\"decl\" id=\"${escapeAttr(entry.name)}\">\n  <h2 class=\"decl-name\">${escapeHtml(entry.name)}</h2>\n  <pre><code class=\"kestrel\">${escapeHtml(sig)}</code></pre>\n${docDiv}</section>"
}

/// Render a full HTML page for a single `DocModule`.
export fun renderModule(mod: DocModule): String = {
  val proseHtml =
    if (Str.isEmpty(mod.moduleProse)) ""
    else "<div class=\"module-prose\">${Md.render(mod.moduleProse)}</div>\n"
  val entryHtml = Str.join("\n", Lst.map(mod.entries, (e: DocEntry) => renderEntry(e)))
  val contentHtml = "<div class=\"module-content\">\n<h1 class=\"module-title\">${escapeHtml(mod.moduleSpec)}</h1>\n${proseHtml}${entryHtml}\n</div>"
  val sidebarHtml =
    if (Lst.isEmpty(mod.entries)) ""
    else "\n<aside class=\"module-sidebar\">\n${renderIndex(mod.entries)}\n</aside>"
  val body = "<div class=\"module-layout\">${contentHtml}${sidebarHtml}\n</div>"
  page("${mod.moduleSpec} — Kestrel Docs", body)
}

// ── Single-declaration fragment ───────────────────────────────────────────────

fun findEntry(entries: List<DocEntry>, name: String): Option<DocEntry> =
  Lst.head(Lst.filter(entries, (e: DocEntry) => Str.equals(e.name, name)))

/// Return an HTML fragment for a single named declaration, or a "not found"
/// fragment if the name does not exist in the module.
export fun renderDeclaration(mod: DocModule, name: String): String =
  match (findEntry(mod.entries, name)) {
    Some(e) => renderEntry(e)
    None    => "<p class=\"not-found\">Declaration <code>${escapeHtml(name)}</code> not found in <code>${escapeHtml(mod.moduleSpec)}</code>.</p>"
  }

// ── Static CSS ────────────────────────────────────────────────────────────────

/// Return the bundled CSS stylesheet for the documentation browser.
export fun staticCss(): String =
  Str.join("\n", [
    "*, *::before, *::after { box-sizing: border-box; }",
    "body {",
    "  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;",
    "  font-size: 16px; line-height: 1.6; margin: 0;",
    "  background: #fff; color: #222;",
    "}",
    ".site-header {",
    "  position: sticky; top: 0; z-index: 100;",
    "  display: flex; align-items: center; gap: 1rem; padding: 0.5rem 1rem;",
    "  background: #1a1a2e; color: #eee;",
    "}",
    ".home-link { color: #7eb8f7; text-decoration: none; font-weight: bold; }",
    ".home-link:hover { text-decoration: underline; }",
    ".search-box {",
    "  flex: 1; max-width: 28rem; padding: 0.3rem 0.6rem;",
    "  border: 1px solid #555; border-radius: 4px;",
    "  background: #2a2a4e; color: #eee; font-size: 0.95rem;",
    "}",
    ".search-results {",
    "  position: absolute; top: 100%; left: 0; right: 0;",
    "  background: #fff; border: 1px solid #ccc; border-top: none;",
    "  max-height: 20rem; overflow-y: auto; z-index: 200;",
    "  box-shadow: 0 4px 8px rgba(0,0,0,0.1);",
    "}",
    ".search-results a {",
    "  display: block; padding: 0.4rem 0.8rem;",
    "  color: #1a1a2e; text-decoration: none; border-bottom: 1px solid #eee;",
    "}",
    ".search-results a:hover { background: #f0f4ff; }",
    "main { max-width: 1100px; margin: 0 auto; padding: 2rem 1rem; }",
    ".module-list { list-style: none; padding: 0; }",
    ".module-list li { margin: 0.4rem 0; }",
    ".module-list a { color: #0057b7; text-decoration: none; font-family: monospace; font-size: 0.95rem; }",
    ".module-list a:hover { text-decoration: underline; }",
    ".module-title { font-family: monospace; font-size: 1.4rem; }",
    ".module-prose { margin-bottom: 2rem; }",
    ".decl { margin: 2rem 0; padding-top: 1rem; border-top: 1px solid #eee; }",
    ".decl-name { font-family: monospace; font-size: 1.1rem; margin: 0 0 0.5rem; }",
    "pre { background: #f4f4f8; padding: 0.8rem 1rem; border-radius: 4px; overflow-x: auto; }",
    "code { font-family: 'Fira Code', 'Cascadia Code', Consolas, monospace; font-size: 0.92rem; }",
    ".doc-body p { margin: 0.6rem 0; }",
    ".doc-body code { background: #f0f0f4; padding: 0.1rem 0.3rem; border-radius: 3px; }",
    ".module-layout { display: flex; gap: 2.5rem; }",
    ".module-content { flex: 1; min-width: 0; }",
    ".module-sidebar { width: 210px; flex-shrink: 0; }",
    ".decl-index { position: sticky; top: 56px; max-height: calc(100vh - 72px); overflow-y: auto; border: 1px solid #dde; border-radius: 6px; padding: 0.8rem; background: #fafafe; }",
    ".decl-index-title { font-weight: 600; font-size: 0.9rem; margin-bottom: 0.5rem; color: #444; }",
    ".decl-index ul { list-style: none; padding: 0; margin: 0; }",
    ".decl-index li { margin: 0.25rem 0; }",
    ".decl-index a { text-decoration: none; color: #0057b7; font-family: monospace; font-size: 0.85rem; display: block; }",
    ".decl-index a:hover { text-decoration: underline; }",
    ".idx-kind { display: inline-block; min-width: 5.5rem; color: #777; font-size: 0.82rem; }",
    ".not-found { color: #c00; }",
    "@media (max-width: 900px) {",
    "  .module-layout { flex-direction: column; }",
    "  .module-sidebar { width: 100%; }",
    "  .decl-index { position: static; max-height: none; }",
    "}",
    "@media (max-width: 600px) {",
    "  .site-header { flex-wrap: wrap; }",
    "  .search-box { max-width: 100%; }",
    "}"
  ])

// ── Static JavaScript ─────────────────────────────────────────────────────────

/// Return the bundled JavaScript for the search box UI.
export fun staticJs(): String =
  Str.join("\n", [
    "(function() {",
    "  var box = document.getElementById('search');",
    "  var res = document.getElementById('search-results');",
    "  if (!box || !res) return;",
    "  var timer = null;",
    "  box.addEventListener('input', function() {",
    "    clearTimeout(timer);",
    "    var q = box.value.trim();",
    "    if (!q) { res.innerHTML = ''; res.style.display = 'none'; return; }",
    "    timer = setTimeout(function() {",
    "      fetch('/api/search?q=' + encodeURIComponent(q))",
    "        .then(function(r) { return r.json(); })",
    "        .then(function(hits) {",
    "          if (!hits.length) { res.innerHTML = '<a>No results</a>'; }",
    "          else {",
    "            res.innerHTML = hits.map(function(h) {",
    "              var url = '/docs/' + h.moduleSpec + '#' + h.name;",
    "              var label = h.moduleSpec + '  ' + h.name;",
    "              return '<a href=\"' + url + '\">' + label + '</a>';",
    "            }).join('');",
    "          }",
    "          res.style.display = 'block';",
    "        })",
    "        .catch(function() { res.style.display = 'none'; });",
    "    }, 200);",
    "  });",
    "  document.addEventListener('click', function(e) {",
    "    if (!res.contains(e.target) && e.target !== box) {",
    "      res.style.display = 'none';",
    "    }",
    "  });",
    "})();",
    ";(function() {",
    "  var _tok = null;",
    "  function _poll() {",
    "    fetch('/api/reload-token')",
    "      .then(function(r) { return r.text(); })",
    "      .then(function(t) {",
    "        if (_tok === null) { _tok = t; }",
    "        else if (t !== _tok) { location.reload(); }",
    "      })",
    "      .catch(function() {});",
    "  }",
    "  setInterval(_poll, 1000);",
    "})();"
  ])
