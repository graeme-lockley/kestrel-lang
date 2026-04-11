# `kestrel:dev/doc/render` — HTML fragment generation

## Sequence: S09-04
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser](../epics/unplanned/E09-documentation-browser.md)
- Companion stories: S09-01, S09-02, S09-03, S09-05, S09-06, S09-07, S09-08

## Summary

Implements `kestrel:dev/doc/render` — the module that turns `DocModule` values (from
`kestrel:dev/doc/extract`) into HTML string fragments ready to be served by the doc server.
It wires together the Markdown renderer (S09-02) and the signature pretty-printer (S09-03) and
produces three distinct views: the module list page, the per-module page, and a single-declaration
anchor fragment. Bundled static CSS and minimal vanilla JavaScript for the search UI are also
defined here.

## Current State

- `kestrel:dev/doc/extract` (S09-01 — not yet built): will provide `DocModule` and `DocEntry`.
- `kestrel:dev/doc/markdown` (S09-02 — not yet built): will provide `render(md: String): String`.
- `kestrel:dev/doc/sig` (S09-03 — not yet built): will provide `format(entry: DocEntry): String`.
- `kestrel:data/string` provides `join`, `replace`, and helpers for template building.
- No HTML templating library exists in the stdlib — string interpolation is used directly.

## Relationship to other stories

- **Depends on:** S09-01 (`DocModule`, `DocEntry`), S09-02 (Markdown renderer),
  S09-03 (signature pretty-printer).
- **Blocks:** S09-07 (the server calls `render.*` functions to build HTTP response bodies).
- **Independent of:** S09-05, S09-06.

## Goals

1. Export from `kestrel:dev/doc/render`:
   - `renderModuleList(modules: List<DocModule>): String` — HTML for `GET /docs/`.
   - `renderModule(mod: DocModule): String` — HTML for `GET /docs/{module}`.
   - `renderDeclaration(mod: DocModule, name: String): String` — HTML fragment (anchor) for
     `GET /docs/{module}/{name}` (redirects to the module page with `#name` anchor in practice;
     this function produces the fragment for embedding).
   - `staticCss(): String` — the bundled CSS stylesheet content.
   - `staticJs(): String` — the bundled search-UI JavaScript content.
2. Each rendered page includes:
   - A consistent navigation header with a link to `/docs/` and a live search box.
   - Module-level prose from `DocModule.moduleProse` rendered as Markdown.
   - Per-declaration sections: signature in a `<pre><code>` block + Markdown-rendered doc body.
   - Declaration anchors of the form `id="{name}"` for deep linking.
3. HTML must be well-formed (all tags closed, special characters escaped in prose sections).
4. The CSS provides a clean, minimal, readable layout (no external font or network resources —
   everything is self-contained so the browser works fully offline).

## Acceptance Criteria

- All four functions and two static-asset functions are exported and callable.
- `renderModuleList([])` returns valid HTML with an empty module table (no crash).
- `renderModule(mod)` includes section headings for each `DocEntry`, signature code blocks,
  and Markdown-rendered doc bodies.
- `staticCss()` returns a non-empty CSS string; `staticJs()` returns JavaScript that powers
  the search box (calls `GET /api/search?q=…`).
- HTML output passes a basic well-formedness check (matching open/close tags for the structures
  this module generates).
- Unit tests in `stdlib/kestrel/dev/doc/render.test.ks` cover:
  - `renderModuleList` with one and multiple modules.
  - `renderModule` with a module containing documented and undocumented exports.
  - `renderDeclaration` for an existing entry.
- All Kestrel tests pass (`./kestrel test`).

## Spec References

- `kestrel:dev/doc/extract` — `DocModule`, `DocEntry`, `DocKind` (S09-01).
- `kestrel:dev/doc/markdown` — `render` (S09-02).
- `kestrel:dev/doc/sig` — `format` (S09-03).

## Risks / Notes

- String interpolation for HTML templating is verbose but avoids any external dependency.
  A minimal helper `tag(name: String, attrs: String, body: String): String` can reduce
  repetition without generalising into a full template engine.
- CSS: aim for a single self-contained stylesheet under ~150 lines. Syntax highlighting for
  signatures can be done with a single `.kestrel code` rule (monospace, coloured background)
  rather than full tokeniser-based highlighting.
- JavaScript: the search box only needs to call `fetch('/api/search?q=…')` and render results
  — about 30 lines of vanilla JS. No frameworks.
- This story does not implement cross-reference link resolution for backtick names inside doc
  bodies (e.g. `` `List.map` `` → link). That is an Optional V2 enhancement.

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib (new module) | `stdlib/kestrel/dev/doc/render.ks` — `renderModuleList`, `renderModule`, `renderDeclaration`, `staticCss`, `staticJs` |
| Tests (new) | `stdlib/kestrel/dev/doc/render.test.ks` — unit tests |
| Specs | None required |

## Tasks

- [x] Create `stdlib/kestrel/dev/doc/render.ks` with all five exported functions
- [x] Implement `renderModuleList(modules: List<DocModule>): String`
- [x] Implement `renderModule(mod: DocModule): String`
- [x] Implement `renderDeclaration(mod: DocModule, name: String): String`
- [x] Implement `staticCss(): String` and `staticJs(): String`
- [x] Create `stdlib/kestrel/dev/doc/render.test.ks` with unit tests
- [x] Run `./kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | `renderModuleList([])` → valid HTML, no crash |
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | `renderModuleList([mod])` → contains module link |
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | `renderModule(mod)` → contains entry headings |
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | `renderModule(mod)` → contains signature code block |
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | `renderModule(mod)` → renders doc prose as HTML |
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | `renderDeclaration` for existing entry |
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | `renderDeclaration` for missing entry returns 404 fragment |
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | `staticCss()` returns non-empty string |
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | `staticJs()` returns non-empty string |

## Documentation and specs to update

- None.
