# Epic E08: Source Formatter (`kestrel fmt`)

## Status

Unplanned

## Summary

An opinionated, Elm-style source code formatter for Kestrel, written entirely in Kestrel — including its own lexer and recursive-descent parser. It normalises whitespace, indentation (2 spaces), and line breaks to a canonical 120-character-wide layout, using as much of that width as possible before breaking. `fun` declarations always break after `=`; `match` arms, `if`/`else` branches, record fields, and list elements break when they would exceed the line limit.

Because the formatter is the first major developer tool, this epic begins with establishing a complete, principled stdlib namespace structure. The existing flat `kestrel:X` stdlib is reorganised into `kestrel:data/*`, `kestrel:io/*`, and `kestrel:sys/*` categories (breaking change — all callers within the repo are updated). Developer infrastructure lives under `kestrel:dev/*`. User-facing tools live under `kestrel:tools/*`, and each tool module is directly runnable via `./kestrel run kestrel:tools/<name>` — `kestrel test` and `kestrel fmt` become thin CLI aliases over this mechanism.

## Stories

(None yet — use plan-epic to decompose, or story-create to add individual stories.)

## Dependencies

- None required. The formatter is self-contained: it reads source files via `kestrel:io/fs`, tokenises and parses them in Kestrel, and writes formatted output back. No TypeScript changes beyond the resolver extension and `kestrel run` accepting module specifiers.

## Epic Completion Criteria

- Existing flat stdlib modules are moved to `kestrel:data/*`, `kestrel:io/*`, and `kestrel:sys/*`; all import sites in `stdlib/`, `tests/`, and example programs are updated.
- The `kestrel:dev/*` and `kestrel:tools/*` sub-namespaces are defined in specs and the resolver supports all sub-paths via file-existence fallback (no hardcoded whitelist for sub-paths).
- `./kestrel run kestrel:tools/test` runs the test tool directly; `kestrel test` is a thin alias for it.
- `kestrel fmt <file.ks>` reformats a Kestrel source file in-place according to the opinionated rules.
- `kestrel fmt --check <file.ks>` exits non-zero when the file is not already canonical; used in CI without modifying files.
- When no file argument is given, `kestrel fmt` reads from stdin and writes to stdout.
- The formatter is idempotent: `fmt(fmt(source)) == fmt(source)` for all valid Kestrel programs.
- The formatter is written entirely in Kestrel, including its own lexer and parser (no TypeScript, no subprocess spawning).
- All existing programs in `tests/conformance/`, `tests/unit/`, `stdlib/kestrel/`, `mandelbrot.ks`, and `primes.ks` pass through the formatter without semantic change (same runtime output before and after).
- `docs/specs/09-tools.md` documents the `fmt` subcommand with its flags and exit codes, and the `./kestrel run <module-specifier>` invocation form.
- `docs/specs/02-stdlib.md` and `docs/specs/07-modules.md` document the full namespace structure.
- All formatter unit and golden-file tests pass (`cd compiler && npm test`; `./scripts/kestrel test`).

## Implementation Approach

### Namespace design

#### Full namespace map

| Namespace | Purpose | Physical location | Moved from |
|-----------|---------|-------------------|------------|
| `kestrel:data/basics` | Primitive ops and built-ins | `stdlib/kestrel/data/basics.ks` | `kestrel:basics` |
| `kestrel:data/char` | Character operations | `stdlib/kestrel/data/char.ks` | `kestrel:char` |
| `kestrel:data/string` | String operations | `stdlib/kestrel/data/string.ks` | `kestrel:string` |
| `kestrel:data/list` | List operations | `stdlib/kestrel/data/list.ks` | `kestrel:list` |
| `kestrel:data/dict` | Dictionary (map) | `stdlib/kestrel/data/dict.ks` | `kestrel:dict` |
| `kestrel:data/set` | Set | `stdlib/kestrel/data/set.ks` | `kestrel:set` |
| `kestrel:data/tuple` | Tuple utilities | `stdlib/kestrel/data/tuple.ks` | `kestrel:tuple` |
| `kestrel:data/option` | Option type | `stdlib/kestrel/data/option.ks` | `kestrel:option` |
| `kestrel:data/result` | Result type | `stdlib/kestrel/data/result.ks` | `kestrel:result` |
| `kestrel:data/json` | JSON encoding/decoding | `stdlib/kestrel/data/json.ks` | `kestrel:json` |
| `kestrel:io/console` | Console I/O | `stdlib/kestrel/io/console.ks` | `kestrel:console` |
| `kestrel:io/fs` | Filesystem | `stdlib/kestrel/io/fs.ks` | `kestrel:fs` |
| `kestrel:io/http` | HTTP client | `stdlib/kestrel/io/http.ks` | `kestrel:http` |
| `kestrel:sys/process` | Process spawning | `stdlib/kestrel/sys/process.ks` | `kestrel:process` |
| `kestrel:sys/task` | Async tasks | `stdlib/kestrel/sys/task.ks` | `kestrel:task` |
| `kestrel:sys/runtime` | Runtime errors | `stdlib/kestrel/sys/runtime.ks` | `kestrel:runtime` |
| `kestrel:dev/stack` | Stack trace (debug) | `stdlib/kestrel/dev/stack.ks` | `kestrel:stack` |
| `kestrel:dev/parser` | Lexer + AST + parser (single module) | `stdlib/kestrel/dev/parser.ks` | *(new)* |
| `kestrel:dev/doc` | Wadler–Lindig Doc IR | `stdlib/kestrel/dev/doc.ks` | *(new)* |
| `kestrel:tools/test` | Test framework + runner | `stdlib/kestrel/tools/test.ks` | `kestrel:test` |
| `kestrel:tools/format` | Source formatter | `stdlib/kestrel/tools/format.ks` | *(new)* |

#### Category rationale

- **`kestrel:data/*`** — pure, stateless modules: data structures, algorithms, type utilities. No I/O.
- **`kestrel:io/*`** — effectful modules that communicate with the outside world: console, filesystem, network.
- **`kestrel:sys/*`** — system-level concerns: processes, concurrency, runtime error types.
- **`kestrel:dev/*`** — infrastructure for working with Kestrel source code; not end-user-visible, consumed by tools. `kestrel:dev/parser` is a single flat module (no sub-modules) that exports everything needed to lex and parse Kestrel: `Token`, `TokenKind`, all AST ADTs (`Expr`, `Pattern`, `Type`, `TopLevelDecl`, …), `lex : String -> Result<List<Token>, LexError>`, and `parse : List<Token> -> Result<Program, ParseError>`.
- **`kestrel:tools/*`** — user-facing tools. Each tool module exports `main : List<String> -> Task<Int>` and is directly runnable.

#### Resolver change

The current resolver has a hardcoded whitelist of stdlib names and rejects unknown `kestrel:*` specifiers. The resolver is extended with a **file-existence fallback**: any `kestrel:X` specifier that is not in the whitelist but whose path `stdlib/kestrel/X.ks` exists on disk resolves successfully. The whitelist is retained only for error-message quality on genuine typos.

```
specifier = "kestrel:data/string"
// path segment = "data/string"
// candidate = stdlib/kestrel/data/string.ks  ← exists → resolved
```

### Tools as first-class runnable modules

Each `kestrel:tools/X` module exports a `main` function:

```
main : List<String> -> Task<Int>
```

`./kestrel run` is extended to accept module specifiers in addition to file paths:

```bash
./kestrel run kestrel:tools/test          # run the test tool
./kestrel run kestrel:tools/format src/   # run the formatter on a directory
```

The CLI convenience commands are thin aliases over this mechanism:

| CLI command | Equivalent |
|-------------|-----------|
| `kestrel test [args]` | `kestrel run kestrel:tools/test [args]` |
| `kestrel fmt [args]` | `kestrel run kestrel:tools/format [args]` |

This means tools are self-contained Kestrel programs, testable and runnable without special CLI knowledge, and new tools are added by creating a new `kestrel:tools/X` module — no CLI changes required.

### Formatter architecture

```
kestrel:tools/format
  ├── import kestrel:dev/parser    → Token, AST types, lex, parse
  ├── import kestrel:dev/doc       → Doc IR, pretty
  └── import kestrel:io/fs / kestrel:io/console  → I/O
```

1. Read source file via `kestrel:io/fs` `readText`.
2. Lex → `List<Token>` via `kestrel:dev/parser` `lex`.
3. Parse → `Program` AST via `kestrel:dev/parser` `parse`.
4. Translate AST → `Doc` (declaration and expression formatters).
5. Render `Doc` at 120 columns via `kestrel:dev/doc` `pretty`.
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
