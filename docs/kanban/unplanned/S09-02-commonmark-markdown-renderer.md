# CommonMark subset Markdown renderer (`kestrel:dev/doc/markdown`)

## Sequence: S09-02
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser](../epics/unplanned/E09-documentation-browser.md)
- Companion stories: S09-01, S09-03, S09-04, S09-05, S09-06, S09-07, S09-08

## Summary

Implements `kestrel:dev/doc/markdown` — a pure-Kestrel parser and HTML renderer for the subset
of CommonMark used in Kestrel doc-comment bodies. The renderer takes a `String` (the raw
doc-comment text) and returns an HTML `String`. It is consumed by S09-04 (`kestrel:dev/doc/render`)
to embed Markdown-rendered doc prose inside generated HTML pages.

Writing the renderer as a standalone module with no external dependencies makes it independently
testable and reusable.

## Current State

- No Markdown renderer exists anywhere in the Kestrel stdlib.
- `kestrel:dev/parser` provides a general-purpose Kestrel-language lexer; it does not tokenise
  Markdown.
- `kestrel:data/string` provides `split`, `startsWith`, `trim`, `slice`, `replace`, and
  related helpers that are sufficient to build a line-at-a-time Markdown parser.
- The doc-comment body format defined in S09-01 is CommonMark; backtick-quoted `` `Name` ``
  identifiers in bodies may optionally be cross-reference links (V1 can emit plain `<code>`
  tags; cross-references can be added later).

## Relationship to other stories

- **Depends on:** S09-01 (defines what `doc: String` contains, establishing the format this
  renderer must handle).
- **Blocks:** S09-04 (the HTML renderer calls `markdown.render` to convert doc bodies).
- **Independent of:** S09-03, S09-05, S09-06, S09-07.
- Can be developed in parallel with S09-03 after S09-01 is done.

## Goals

1. Implement `kestrel:dev/doc/markdown` with an exported `render(md: String): String` function.
2. Support the following CommonMark block elements:
   - Paragraphs (blank-line-separated prose runs).
   - ATX headings `## Heading`.
   - Fenced code blocks (` ``` ` delimited, with optional language tag).
   - Unordered list items (`- item`, `* item`).
   - Ordered list items (`1. item`).
   - Blockquotes (`> text`).
   - Horizontal rules (`---`).
3. Support the following inline elements within paragraphs and headings:
   - Inline code `` `code` ``.
   - Bold `**text**` and `__text__`.
   - Italic `*text*` and `_text_`.
   - Hyperlinks `[label](url)`.
   - HTML-escape `<`, `>`, `&` in all non-code contexts.
4. Emit minimal, well-formed HTML fragments (no `<html>` / `<body>` wrapper).

## Acceptance Criteria

- `render` is exported from `kestrel:dev/doc/markdown`.
- All six block elements and five inline elements listed in Goals render to correct HTML.
- Backtick-quoted names `` `List.map` `` in normal prose are rendered as `<code>List.map</code>`.
- Fenced code blocks preserve internal whitespace and HTML-escape their content.
- An empty or whitespace-only input returns an empty string (no spurious `<p></p>`).
- Unit tests in `stdlib/kestrel/dev/doc/markdown.test.ks` cover each element type, including
  nesting (e.g. bold inside a list item).
- All Kestrel tests pass (`./kestrel test`).

## Spec References

- [CommonMark 0.31.2 specification](https://spec.commonmark.org/) — reference for element
  semantics; only the subset listed in Goals needs to be implemented.

## Risks / Notes

- A full CommonMark parser is complex; this story implements a well-defined **subset** that
  covers realistic doc-comment usage. Edge cases outside the subset (e.g. nested blockquotes,
  reference-style links, setext headings) are out of scope for V1 and may produce arbitrary
  output.
- The renderer operates line-by-line for block-level parsing and uses a simple state machine to
  track open elements (fenced code, list, blockquote). A single-pass approach is workable for
  the subset.
- The `kestrel:data/string` module provides `indexOf`, `slice`, `trim`, and `replace` which
  are sufficient for inline parsing via repeated scanning.
