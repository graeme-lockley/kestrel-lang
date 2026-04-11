# Doc-comment syntax spec and `kestrel:dev/doc/extract`

## Sequence: S09-01
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser](../epics/unplanned/E09-documentation-browser.md)
- Companion stories: S09-02, S09-03, S09-04, S09-05, S09-06, S09-07, S09-08

## Summary

Specifies the `///` and `//!` doc-comment syntax in `docs/specs/01-language.md` §2.1 and
implements `kestrel:dev/doc/extract` — the module that re-lexes a Kestrel source file (using
`kestrel:dev/parser/lexer`) and produces a `DocModule` ADT describing the module's doc prose,
exported declarations, and their attached doc-comment strings.

This story is the foundation for all other E09 stories: the `DocModule` ADT and the extractor
are consumed by the renderer (S09-04), the search index (S09-05), and the server (S09-07).

## Current State

- `kestrel:dev/parser/lexer` already tokenises line comments as `TkLineComment` with raw text
  (including the `//` prefix); block comments are `TkBlockComment`.
- The parser skips all trivia tokens (whitespace + comments) before building the AST, so
  doc-comment text is not currently retained anywhere above the lexer.
- `kestrel:dev/parser/ast` defines all top-level declaration types (`FunDecl`, `TypeDecl`,
  `ExternFunDecl`, `ExternTypeDecl`, `ExceptionDecl`, `TDVal`, `TDVar`, etc.).
- There is no `docs/specs/01-language.md` entry for `///` or `//!` syntax.
- No `kestrel:dev/doc/` directory or module exists yet.

## Relationship to other stories

- **Blocks:** S09-02, S09-03, S09-04, S09-05, S09-07 — all depend on the `DocModule` ADT
  defined here.
- **Independent of:** S09-06 (file watching — no shared types).

## Goals

1. Document `///` and `//!` doc-comment syntax in `docs/specs/01-language.md` §2.1 with
   precise grammar and semantics.
2. Implement `kestrel:dev/doc/extract` that:
   - Re-lexes a source string (or file path via `kestrel:io/fs`) keeping trivia tokens.
   - Collects consecutive `///` lines immediately before an `export` declaration into a
     per-declaration doc-comment string.
   - Collects `//!` lines at the top of the file (before the first declaration) into a
     module-level prose string.
   - Accepts `/** … */` block comments immediately before an `export` declaration as an
     alternative to `///` lines.
   - Returns a `DocModule` ADT value.

## Acceptance Criteria

- `DocModule` ADT is exported from `kestrel:dev/doc/extract` and includes:
  - `moduleSpec: String` — the module specifier (e.g. `"kestrel:data/list"`).
  - `moduleProse: String` — concatenated `//!` lines from the file top; empty string if none.
  - `entries: List<DocEntry>` — one entry per exported declaration.
- `DocEntry` includes at minimum:
  - `name: String` — declaration name.
  - `kind: DocKind` — `DKFun | DKType | DKVal | DKVar | DKException | DKExternType | DKExternFun`.
  - `signature: String` — raw source text of the declaration header (up to `=` or `{`, exclusive).
  - `doc: String` — concatenated doc-comment lines; empty string if no doc-comment.
- `extract(source: String, spec: String): DocModule` works correctly for:
  - Files with no doc-comments (returns entries with empty `doc` fields).
  - Mixed `///` and undocumented exports.
  - `//!` module-level prose.
  - `/** … */` block doc-comments immediately before an export.
- `extractFile(path: String, spec: String): Task<Result<DocModule, String>>` reads the file
  and calls `extract`.
- `docs/specs/01-language.md` §2.1 (Comments) is updated with precise `///` / `//!` rules.
- Unit tests in `stdlib/kestrel/dev/doc/extract.test.ks` cover all cases above.
- All compiler tests pass (`cd compiler && npm test`).
- All Kestrel tests pass (`./kestrel test`).

## Spec References

- `docs/specs/01-language.md` §2.1 (Comments) — to be updated.
- `docs/specs/09-tools.md` — referenced by S09-07.
- `kestrel:dev/parser/token` — `TkLineComment`, `TkBlockComment` token kinds.
- `kestrel:dev/parser/ast` — all `TopDecl` and `FunDecl` / `TypeDecl` variants.

## Risks / Notes

- The extractor must preserve relative whitespace ordering between doc-comment lines and the
  declaration that follows. A blank line between the last `///` and the `export` keyword breaks
  the association — this policy must be stated in the spec.
- `signature` extraction: we capture from the start of the declaration through to (but not
  including) the `=` or `{` body delimiter, stripping internal whitespace normalisation to keep
  it readable. A simple heuristic (scan token stream to the first `=` or `{` after the
  declaration head) is sufficient for V1.
- Block comment form `/** … */` should strip leading ` * ` prefixes per line (JavaDoc style)
  before storing the `doc` text.
- No compiler changes are required; the compiler already discards all comments as trivia.
