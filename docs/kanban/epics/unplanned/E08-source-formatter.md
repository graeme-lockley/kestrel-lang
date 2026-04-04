# Epic E08: Source Formatter (`kestrel fmt`)

## Status

Unplanned

## Summary

An opinionated, Elm-style source code formatter for Kestrel, written entirely in Kestrel — including its own lexer and recursive-descent parser. It normalises whitespace, indentation (2 spaces), and line breaks to a canonical 120-character-wide layout, using as much of that width as possible before breaking. `fun` declarations always break after `=`; `match` arms, `if`/`else` branches, record fields, and list elements break when they would exceed the line limit. The formatter exposes a `kestrel fmt` CLI subcommand that reformats files in-place, and a `kestrel fmt --check` mode that verifies formatting in CI without modifying files. No TypeScript changes are required; the formatter reads source directly, tokenises and parses it in Kestrel, converts the AST to a Doc IR via the Wadler–Lindig layout algorithm, and renders canonical source. This also serves as a first meaningful step toward a self-hosting Kestrel compiler.

Because the formatter is the first major developer tool, this epic begins with establishing the stdlib namespace structure that will house all future tooling.

## Stories

(None yet — use plan-epic to decompose, or story-create to add individual stories.)

## Dependencies

- None required. The formatter is self-contained: it reads source files via `kestrel:fs`, tokenises and parses them in Kestrel, and writes formatted output back. No TypeScript changes, no subprocess spawning.

## Epic Completion Criteria

- The `kestrel:tools/*` sub-namespace is defined in specs and the resolver supports it (file-existence-based, no hardcoded whitelist for sub-paths).
- `kestrel fmt <file.ks>` reformats a Kestrel source file in-place according to the opinionated rules.
- `kestrel fmt --check <file.ks>` exits non-zero when the file is not already canonical; used in CI without modifying files.
- When no file argument is given, `kestrel fmt` reads from stdin and writes to stdout.
- The formatter is idempotent: `fmt(fmt(source)) == fmt(source)` for all valid Kestrel programs.
- The formatter is written entirely in Kestrel, including its own lexer and parser (no TypeScript, no subprocess spawning).
- All existing programs in `tests/conformance/`, `tests/unit/`, `stdlib/kestrel/`, `mandelbrot.ks`, and `primes.ks` pass through the formatter without semantic change (same runtime output before and after).
- `docs/specs/09-tools.md` documents the `fmt` subcommand with its flags and exit codes.
- `docs/specs/02-stdlib.md` and `docs/specs/07-modules.md` document the `kestrel:tools/*` namespace convention.
- All formatter unit and golden-file tests pass (`cd compiler && npm test`; `./scripts/kestrel test`).

## Implementation Approach

### Namespace design

The existing stdlib uses a flat `kestrel:X` scheme (`kestrel:list`, `kestrel:string`, etc.) where each specifier maps to `stdlib/kestrel/X.ks`. These stay unchanged. A new sub-namespace `kestrel:tools/X` is introduced for developer tooling — importable libraries and programs that operate on Kestrel source code rather than on user data.

#### Naming convention

| Namespace | Purpose | Physical location |
|-----------|---------|-------------------|
| `kestrel:X` | Core stdlib (existing, unchanged) | `stdlib/kestrel/X.ks` |
| `kestrel:tools/X` | Developer tooling libraries | `stdlib/kestrel/tools/X.ks` |

Tool programs (entry points run via `kestrel run`) live in `tools/<name>/main.ks` at the project root and import from `kestrel:tools/*`. They are **not** importable as stdlib modules; they are programs.

#### Why `kestrel:tools/` not a flat `kestrel:lexer`?

- A bare `kestrel:lexer` would pollute the flat stdlib namespace with tooling concerns.
- The `/` acts as a category boundary, analogous to how Haskell groups `Data.*`, `System.*`, `Text.*` and Java groups `java.util.*`, `java.io.*`.
- Future tooling (`kestrel:tools/lint`, `kestrel:tools/lsp`, `kestrel:tools/docs`) naturally fits the same structure.
- The existing flat stdlib is **not** reorganised — that would be a large breaking change and is deferred to a future decision.

#### Resolver change

The current resolver has a hardcoded whitelist of stdlib names and rejects any unknown `kestrel:*` specifier. For `kestrel:tools/X` to work, the resolver is extended with a **file-existence fallback** for `kestrel:` specifiers: if the specifier is not in the whitelist but maps to an existing file under `stdlibDir`, it resolves successfully. The whitelist still guards the canonical flat stdlib names; the fallback allows open-ended sub-paths without enumerating them.

Concretely, `kestrel:tools/doc` resolves via:
```
[prefix, ...rest] = "kestrel:tools/doc".split(":")
// prefix = "kestrel", rest = "tools/doc"
// candidate = stdlib/kestrel/tools/doc.ks
// if exists → resolved
```

#### Formatter-specific modules under `kestrel:tools/`

| Module | Description |
|--------|-------------|
| `kestrel:tools/token` | `Token` ADT and `TokenKind` — the shared token vocabulary |
| `kestrel:tools/lexer` | Tokeniser: `String -> Result<List<Token>, LexError>` |
| `kestrel:tools/ast` | Kestrel AST ADTs (`Expr`, `Pattern`, `Type`, `TopLevelDecl`, …) |
| `kestrel:tools/parser` | Recursive-descent parser: `List<Token> -> Result<Program, ParseError>` |
| `kestrel:tools/doc` | Wadler–Lindig `Doc` ADT and `pretty : Int -> Doc -> String` |

The formatter entry point lives at `tools/fmt/main.ks` and imports all five modules above.

### Formatter architecture

```
tools/fmt/main.ks
  ├── import kestrel:tools/lexer   → List<Token>
  ├── import kestrel:tools/parser  → Program AST
  ├── import kestrel:tools/doc     → Doc IR
  ├── import kestrel:tools/ast     → (shared types)
  └── import kestrel:fs / kestrel:process  → I/O
```

1. Read source file via `kestrel:fs` `readText`.
2. Lex → `List<Token>` via `kestrel:tools/lexer`.
3. Parse → `Program` AST via `kestrel:tools/parser`.
4. Translate AST → `Doc` (declaration and expression formatters).
5. Render `Doc` at 120 columns via `kestrel:tools/doc` `pretty`.
6. Write result back to file (or stdout).

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
