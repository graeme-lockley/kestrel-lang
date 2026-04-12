# Epic E09: Documentation Browser (`kestrel doc`)

## Status

Unplanned

## Summary

Delivers an interactive, web-based documentation browser for Kestrel developers — analogous to Javadoc (Java) or Haddock (Haskell), but live-served rather than statically generated. Running `kestrel doc` starts a local HTTP server that indexes every exported declaration in the Kestrel stdlib (`kestrel:*`) and in the project the tool is run from, renders attached doc-comments as Markdown, and exposes a real-time server-side search API. A new `///` (per-declaration) and `//!` (module-level) doc-comment syntax is introduced to let authors annotate their public API; the compiler treats these as ordinary line comments, so no compiler changes are required. The tool is written entirely in Kestrel and follows the `kestrel:tools/*` and `kestrel:dev/*` namespace conventions established by E08.

## Stories (ordered — implement sequentially)

1. [S09-01-doc-comment-syntax-and-extract.md](../../done/S09-01-doc-comment-syntax-and-extract.md) ✓
2. [S09-02-commonmark-markdown-renderer.md](../../done/S09-02-commonmark-markdown-renderer.md) ✓
3. [S09-03-declaration-signature-pretty-printer.md](../../done/S09-03-declaration-signature-pretty-printer.md) ✓
4. [S09-04-dev-doc-render-html-generation.md](../../done/S09-04-dev-doc-render-html-generation.md) ✓
5. [S09-05-dev-doc-index-search.md](../../done/S09-05-dev-doc-index-search.md) ✓
6. [S09-06-file-watching-primitive.md](../../done/S09-06-file-watching-primitive.md) ✓
7. [S09-07-tools-doc-server.md](../../done/S09-07-tools-doc-server.md) ✓
8. [S09-08-live-reload-integration.md](../../done/S09-08-live-reload-integration.md) ✓
9. [S09-09-exported-val-var-type-inference-in-doc-index.md](../../unplanned/S09-09-exported-val-var-type-inference-in-doc-index.md)
10. [S09-10-kestrel-syntax-colorization-for-declaration-signatures.md](../../unplanned/S09-10-kestrel-syntax-colorization-for-declaration-signatures.md)
11. [S09-11-cross-module-hyperlinks-for-declarations.md](../../unplanned/S09-11-cross-module-hyperlinks-for-declarations.md)
12. [S09-12-index-menu-layout-and-horizontal-scroll.md](../../unplanned/S09-12-index-menu-layout-and-horizontal-scroll.md)

**Notes on parallelism:**
- S09-01 must come first (defines the `DocModule` / `DocEntry` ADT used by everything else).
- S09-02 and S09-03 depend only on S09-01 and can be built in parallel with each other.
- S09-04 and S09-05 can be built in parallel with each other after S09-01, S09-02, and S09-03.
- S09-06 is fully independent of S09-01–S09-05 and can be built at any point.
- S09-07 requires S09-01 through S09-05 (all converge here).
- S09-08 requires S09-06 and S09-07.
- S09-09 requires S09-03 and S09-07 (typed declaration metadata must be available in the doc index).
- S09-10 requires S09-04 and S09-07 (rendered declaration signatures must already be part of the HTML output).
- S09-11 requires S09-05 and S09-07 (search/index metadata and route handling are reused for cross-module declaration links).
- S09-12 requires S09-04 (UI/layout follow-up on the generated docs index view).

## Dependencies

- **E08 (Source Formatter)** — provides `kestrel:dev/parser` (lexer + AST + parser), `kestrel:dev/cli` (CLI argument parsing), `kestrel:io/fs` (file discovery and watching), `kestrel:tools/*` namespace convention, and `./kestrel run <module-specifier>` invocation support.
- **E03 (HTTP and Networking Platform)** — provides `kestrel:io/http` server primitives needed to serve documentation pages and the search API.
- **E01 (Async Runtime Foundation)** — required by E03 and E08; already complete.

## Epic Completion Criteria

- `kestrel doc` (alias for `./kestrel run kestrel:tools/doc`) starts an HTTP server on `localhost:7070` (port configurable via `--port`).
- All exported declarations from all `kestrel:*` stdlib modules are indexed and browsable.
- All exported declarations discovered transitively from the project root (or `--project-root PATH`) are indexed and browsable.
- `///` doc-comments placed immediately before an `export` declaration are parsed and rendered as CommonMark Markdown in that declaration's documentation entry.
- `//!` doc-comments at the top of a source file are rendered as module-level prose documentation.
- A search endpoint (`GET /api/search?q=…`) returns ranked JSON results (exact name > prefix name > signature substring > doc body substring).
- Modifying a `.ks` source file causes the affected module to be re-indexed within 2 seconds; the browser page reflects the change on the next request (or via live-reload).
- `GET /docs/` lists all indexed modules; `GET /docs/{module}` shows all exports for that module; `GET /docs/{module}/{name}` anchors to a single declaration.
- `docs/specs/09-tools.md` documents the `doc` subcommand (flags, routes, exit codes).
- `docs/specs/01-language.md` §2.1 documents `///` and `//!` doc-comment syntax.
- All new Kestrel unit tests pass (`./scripts/kestrel test`); all compiler tests pass (`cd compiler && npm test`).

## Implementation Approach

### Doc-comment syntax

Two new comment forms are added at the **source level only** (the extractor recognises them; the compiler discards them as ordinary `//` comments):

| Form | Placement | Purpose |
|------|-----------|---------|
| `/// <text>` | Immediately before an `export` declaration | Per-declaration doc-comment |
| `//! <text>` | Anywhere at file top (before first declaration) | Module-level prose |

Multi-line doc-comments are formed by consecutive `///` (or `//!`) lines. Block form `/** … */` is also accepted as a doc-comment when placed immediately before an `export`. Comment bodies are CommonMark Markdown; backtick-quoted names (`` `List.map` ``) are resolved to cross-reference links.

### Tool namespace layout

```
kestrel:tools/doc          — main module; cli.ks convention; exports main
kestrel:dev/doc/extract    — re-lex source files, extract DocModule ADT
kestrel:dev/doc/render     — DocModule → HTML fragments (signatures + Markdown)
kestrel:dev/doc/index      — build in-memory search index; query API
```

### Server routes

| Route | Response |
|-------|----------|
| `GET /` | Redirect to `/docs/` |
| `GET /docs/` | Module list + search UI |
| `GET /docs/{module}` | All exports for one module |
| `GET /docs/{module}/{name}` | Single declaration (anchor) |
| `GET /api/search?q=…` | JSON ranked results |
| `GET /api/index` | Full JSON index (for editor/tooling integration) |
| `GET /static/*` | Bundled CSS; minimal vanilla JS for search UI |

### Comparison with prior art

| Feature | Javadoc | Haddock | `kestrel doc` |
|---------|---------|---------|---------------|
| Comment style | `/** */` + `@tags` | `-- \|` / `{- \| -}` | `///` / `//!` / `/** */` |
| Markup | HTML + `@tags` | Custom wiki | CommonMark Markdown |
| Output mode | Static HTML | Static HTML | Live HTTP server |
| Search | Client-side JS | Hoogle (separate tool) | Server-side, real-time |
| Live reload | No | No | Yes (file watcher) |
| Type info source | Compiler doclet | GHC compiler API | `kestrel:dev/parser` + type-printer |
| Written in | Java | Haskell | Kestrel |

### Stdlib coverage

The tool resolves `kestrel:*` specifiers using the same resolver logic as the compiler. After E08's namespace restructure (`kestrel:data/*`, `kestrel:io/*`, `kestrel:sys/*`, `kestrel:dev/*`, `kestrel:tools/*`), all stdlib modules are discovered via the file-existence fallback and indexed automatically — no hardcoded module list is needed in the doc tool.
