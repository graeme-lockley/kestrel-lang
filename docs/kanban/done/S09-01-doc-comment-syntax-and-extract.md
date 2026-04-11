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

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib (new module) | `stdlib/kestrel/dev/doc/extract.ks` — new `DocKind`, `DocEntry`, `DocModule` types and `extract`, `extractFile` functions |
| Tests (new) | `stdlib/kestrel/dev/doc/extract.test.ks` — unit tests for extractor |
| Specs | `docs/specs/01-language.md` §2.1 — add `///` and `//!` doc-comment syntax documentation |

## Tasks

- [x] Create `stdlib/kestrel/dev/doc/extract.ks` with `DocKind`, `DocEntry`, `DocModule` ADTs and `extract`/`extractFile` functions
- [x] Create `stdlib/kestrel/dev/doc/extract.test.ks` with unit tests covering all acceptance criteria
- [x] Update `docs/specs/01-language.md` §2.1 with `///` and `//!` syntax rules
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/dev/doc/extract.test.ks` | Extract from source with no doc-comments → all `doc` fields empty |
| Kestrel harness | `stdlib/kestrel/dev/doc/extract.test.ks` | Extract `///` doc-comment before `export fun` |
| Kestrel harness | `stdlib/kestrel/dev/doc/extract.test.ks` | Extract `//!` module-level prose |
| Kestrel harness | `stdlib/kestrel/dev/doc/extract.test.ks` | `/** */` block comment before export |
| Kestrel harness | `stdlib/kestrel/dev/doc/extract.test.ks` | Blank line between `///` and `export` discards doc |
| Kestrel harness | `stdlib/kestrel/dev/doc/extract.test.ks` | Extract `export type`, `export val`, `export var`, `export exception`, `export extern fun/type` |
| Kestrel harness | `stdlib/kestrel/dev/doc/extract.test.ks` | Signature stops before `=` for type/val/fun |
| Kestrel harness | `stdlib/kestrel/dev/doc/extract.test.ks` | Multiple consecutive exports each get the right doc |

## Documentation and specs to update

- [ ] `docs/specs/01-language.md` §2.1 (Comments) — add `///` and `//!` syntax rules and semantics
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

## Build notes

- 2025-03-07: Implemented `stdlib/kestrel/dev/doc/extract.ks`. The extractor works purely on
  the token stream from `Lex.lex/Arr.fromList`; no AST walk is needed since all
  relevant tokens (`export`, `fun`, `async`, `type`, `val`, `var`, `exception`, `extern`,
  `TkUpper`/`TkIdent` names, `TkLineComment`, `TkBlockComment`) are already available.
- Kestrel language quirks encountered and resolved:
  - `True`/`False` (not `true`/`false`) — Bool constructors are uppercase identifiers.
  - String template syntax `"${var}"` not `+` operator for concatenation.
  - Record construction uses `{ field = val }` without type name prefix.
  - Blocks in `'expr'` context (function bodies, if-branches) cannot end with an `AssignStmt`
    (`:=`). The `resolveKind` helper was refactored from a mutable-variable pattern into a
    pure value-returning `if/else` chain to avoid this constraint.
  - Tuple access via `.0`, `.1` — no destructuring in `val` statements.
- `extract.test.ks` uses `group`/`eq`/`isTrue`/`isFalse` from `kestrel:dev/test` with
  `export async fun run(s: Suite): Task<Unit>` pattern (not an imaginary `Test.suite` API).
- All 30 unit tests pass; 1501 Kestrel tests pass; 424 compiler tests pass.
