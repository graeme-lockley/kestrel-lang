# Epic E08: Source Formatter (`kestrel fmt`)

## Status

Unplanned

## Summary

An opinionated, Elm-style source code formatter for Kestrel, written entirely in Kestrel — including its own lexer and recursive-descent parser. It normalises whitespace, indentation (2 spaces), and line breaks to a canonical 120-character-wide layout, using as much of that width as possible before breaking. `fun` declarations always break after `=`; `match` arms, `if`/`else` branches, record fields, and list elements break when they would exceed the line limit. The formatter exposes a `kestrel fmt` CLI subcommand that reformats files in-place, and a `kestrel fmt --check` mode that verifies formatting in CI without modifying files. No TypeScript changes are required; the formatter reads source directly, tokenises and parses it in Kestrel, converts the AST to a Doc IR via the Wadler–Lindig layout algorithm, and renders canonical source. This also serves as a first meaningful step toward a self-hosting Kestrel compiler.

## Stories

(None yet — use plan-epic to decompose, or story-create to add individual stories.)

## Dependencies

- None required. The formatter is self-contained: it reads source files via `kestrel:fs`, tokenises and parses them in Kestrel, and writes formatted output back. No TypeScript changes, no subprocess spawning.

## Epic Completion Criteria

- `kestrel fmt <file.ks>` reformats a Kestrel source file in-place according to the opinionated rules.
- `kestrel fmt --check <file.ks>` exits non-zero when the file is not already canonical; used in CI without modifying files.
- When no file argument is given, `kestrel fmt` reads from stdin and writes to stdout.
- The formatter is idempotent: `fmt(fmt(source)) == fmt(source)` for all valid Kestrel programs.
- The formatter is written entirely in Kestrel, including its own lexer and parser (no TypeScript, no subprocess spawning).
- All existing programs in `tests/conformance/`, `tests/unit/`, `stdlib/kestrel/`, `mandelbrot.ks`, and `primes.ks` pass through the formatter without semantic change (same runtime output before and after).
- `docs/specs/09-tools.md` documents the `fmt` subcommand with its flags and exit codes.
- All formatter unit and golden-file tests pass (`cd compiler && npm test`; `./scripts/kestrel test`).

## Implementation Approach

### Architecture

The formatter is a pure Kestrel pipeline with no dependency on the TypeScript compiler at runtime:

1. **Kestrel lexer** (`tools/fmt/Lexer.ks`) — tokenises the raw source string into a `List<Token>`, producing `Token(kind, line, col)` values. Written in Kestrel using `kestrel:string` primitives (`codePointAt`, `slice`, `length`).
2. **Kestrel parser** (`tools/fmt/Parser.ks`) — recursive-descent parser over the token list, producing the `AstNode` ADT. Does not type-check; assumes syntactically valid input.
3. **Kestrel formatter** (`tools/fmt/fmt.ks`) — translates the `AstNode` ADT into a `Doc` IR using the Wadler–Lindig document algebra and renders it to a 120-column string.

This approach requires no TypeScript changes, no subprocess spawning, and is a meaningful step toward a self-hosting Kestrel compiler.

### Formatting rules (opinionated)

| Rule | Value |
|------|-------|
| Line width | 120 characters |
| Indent unit | 2 spaces |
| `fun` body | Always break after `=`; body indented 2 |
| `match` arms | Each arm on its own line; multiline body indented 2 |
| `if`/`else` | Inline when ≤ 120; break branches to blocks otherwise |
| Record literals | Inline when short; one field per line with trailing `,` when long |
| List literals | Inline when short; one element per line with trailing `,` when long |
| Function call args | Inline when short; one arg per line when long |
| Pipeline `\|>` | Each step on its own line |
| Imports | All specs on one line when short; one spec per line with trailing `,` when long |
| Trailing newline | Always exactly one |

### Doc IR

The formatter uses the Wadler–Lindig pretty-printing algorithm with a `Doc` ADT:

```
type Doc = Empty | Text(String) | Concat(Doc, Doc) | Nest(Int, Doc)
         | Line | LineBreak | Group(Doc) | FlatAlt(Doc, Doc)
```

`Group(d)` tries to render `d` flat (spaces instead of newlines); if it does not fit within 120 columns, it breaks.
