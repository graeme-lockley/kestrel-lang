# kestrel:dev/parser — Kestrel lexer, AST, and parser (written in Kestrel)

## Sequence: S08-05
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/unplanned/E08-source-formatter.md)
- Companion stories: S08-01, S08-02, S08-03, S08-04, S08-06, S08-07

## Summary

Create `stdlib/kestrel/dev/parser.ks` — a single Kestrel module that implements the full Kestrel lexer, AST type definitions, and recursive-descent parser. The formatter (S08-07) uses this to parse source files. The documentation browser (E09) will also use this module for indexing and cross-referencing.

This is the largest story in E08. The parser must handle the full Kestrel language as documented in `docs/specs/01-language.md`.

## Current State

The authoritative Kestrel parser is the TypeScript implementation in `compiler/src/parser/parse.ts`. This story creates a second, Kestrel-native parser that matches the TypeScript parser's behaviour on all valid Kestrel programs. Error recovery is not required (the formatter only formats valid programs).

## Relationship to other stories

- **Depends on** S08-01 (namespace restructure) — imports from `kestrel:data/*` and `kestrel:sys/*`.
- **Required by** S08-07 (kestrel:tools/format).
- **Independent of** S08-03 (dev/cli) and S08-04 (prettyprinter).
- **Used by** E09 (documentation browser, future epic).

## Goals

1. **Lexer**: Implement `lex : String -> List<Token>` producing a token list from source text.
   - Token types: `Int`, `Float`, `String`, `Char`, `Ident`, `UpperIdent`, `Operator`, `Keyword`, `Punctuation`, `EOF`, `Whitespace`, `LineComment`, `BlockComment`.
   - Tokens carry their source span (start offset, end offset).
   - The formatter needs comments and whitespace tokens for round-trip accuracy.
2. **AST**: Define all AST node types (declarations, expressions, patterns, types, imports) with source spans.
3. **Parser**: Implement `parse : List<Token> -> Result<Program, ParseError>` using recursive descent.
   - Handles all Kestrel declarations: `fun`, `val`, `type`, `import`, `export`.
   - Handles all expression forms: literals, identifiers, function application, binary operators, `let`, `if/else`, `match`, record construction/access, list literals, pipelines `|>`, string interpolation, `do` blocks, `async`/`await`.
   - Handles all pattern forms: literal, wildcard, constructor, record, list, cons.

## Acceptance Criteria

- `parse (lex source)` produces the same AST structure as the TypeScript parser for all files in `tests/conformance/`, `stdlib/kestrel/`, and the root example programs.
- `lex` round-trips the source: `join (map token.text (lex source)) == source` (tokens, including whitespace/comments, reconstruct the original).
- Parse errors include the source offset.
- Unit tests covering at least: all literal types, all operator precedences, `match` with all pattern forms, `if/else`, `let`, records, lists, `|>` pipelines, `do` blocks, `async`/`await`, and import/export declarations.

## Spec References

- `docs/specs/01-language.md` — full language specification
- `docs/specs/02-stdlib.md` — stdlib API

## Risks / Notes

- This is the largest single story in E08. The implementation may take multiple sessions.
- The TypeScript parser is the ground truth; when in doubt, match its behaviour.
- String interpolation (`"${expr}"`) requires the lexer to tokenise strings specially — use a state machine.
- Operator precedence must exactly match `docs/specs/01-language.md §6` (operators). Implement a Pratt/precedence-climbing parser for expressions.
- The AST types need to be recursive (e.g., `Expr` contains `Expr`). Kestrel supports recursive types.
- Comment tokens are needed by the formatter to preserve comments in the output. Include them in the token stream.
- If the full parser proves too large for a single story, the formatter only needs the subset of the AST it actually formats; stub unneeded branches with an `Unsupported` node and note the limitation.
