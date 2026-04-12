# 10 – Compile-time Diagnostics and Error Reporting

Version: 1.0

---

This document specifies how the Kestrel compiler reports compile-time errors and warnings. It is the requirements document for all development related to compile-time diagnostics: diagnostic structure, location rules, output formats (human and machine), compiler API, and CLI behaviour. Implementations must conform to this spec.

---

## 1. Purpose and Scope

- **Scope:** Diagnostics emitted by the parser, module resolver, typechecker, and package (multi-file) compilation. Lexer and codegen may emit diagnostics in the future; they must follow this spec.
- **Output:** Human-readable output (source snippet and caret) and optional machine-readable output (JSON/JSONL) for IDEs and CI.
- **API:** The compiler’s public API returns structured diagnostics on failure; the CLI renders them per §6 and §7.
- **Self-hosting parity:** The Kestrel-side modules `kestrel:tools/compiler/diagnostics` and `kestrel:tools/compiler/reporter` must preserve the same diagnostic field names and stable `code` strings as the TypeScript bootstrap compiler during transition.

---

## 2. Diagnostic Structure

Every compile-time diagnostic is a **Diagnostic** with the following structure.

### 2.1 Severity

- **error:** Compilation cannot succeed (e.g. syntax error, type error, module not found).
- **warning:** Compilation may succeed but the implementation may report a warning (e.g. unused variable). All current diagnostics are errors.

### 2.2 Source Location

Every diagnostic has a **SourceLocation**:

- **file:** string. In package builds (`compileFile`), the absolute path of the source file where the issue occurs. For single-file `compile(source)` with no path, a placeholder (e.g. `""` or `"<source>"`) so the reporter can still show a line number.
- **line:** number. 1-based line in the file.
- **column:** number. 1-based column (start of the span).
- **endLine:** number (optional). 1-based end line for multi-line spans.
- **endColumn:** number (optional). 1-based end column.
- **offset:** number (optional). 0-based character offset in the file, for tooling.
- **endOffset:** number (optional). 0-based end offset.

Implementations must set at least `file`, `line`, and `column`. The reporter may derive a source line from the file when rendering human output.

### 2.3 Diagnostic Fields

- **severity:** `'error' | 'warning'`.
- **code:** string. Stable identifier for this kind of diagnostic (e.g. `parse:unexpected_token`, `type:unknown_variable`, `resolve:module_not_found`). Used for documentation and filtering. See §4.
- **message:** string. Human-readable description.
- **location:** SourceLocation. Required.
- **sourceLine:** string (optional). Precomputed source line for display; may be omitted and derived by the reporter.
- **related:** array (optional). Secondary locations with messages (e.g. “expected type inferred here”).
- **suggestion:** string (optional). Short suggestion (e.g. “Did you mean `println`?”).
- **hint:** string (optional). Extra context (e.g. “expected String, got Int”).

---

## 3. Location Rules

- Every diagnostic has a location. There is no “global” diagnostic without file/line/column.
- For parser errors: location is the token or span where the error was detected (line/column from the parser).
- For typecheck errors: location is the AST node span (expression or declaration) that caused the error. The typechecker receives a **sourceFile** (path) and attaches it to every diagnostic.
- For resolution errors: location is the file that contains the failing import and, when available, the span of the import declaration (or the specifier).
- For package errors (cannot read file, circular import, module does not export X): file is the relevant source file; line/column when an import is involved come from the import declaration span.

---

## 4. Error Codes

Each diagnostic has a stable **code** from one of the following name spaces (or as specified here):

- **parse:*** — Parser (syntax) errors. Example: `parse:unexpected_token`.
- **resolve:*** — Module resolution. Examples: `resolve:module_not_found`, `resolve:stdlib_not_configured`.
- **type:*** — Typechecker. Examples: `type:unknown_variable`, `type:unify`, `type:non_exhaustive_match`, `type:break_outside_loop`, `type:continue_outside_loop`, `type:narrow_impossible`, `type:narrow_opaque`.
- **export:*** — Export/import mismatch. Examples: `export:not_exported`, `export:reexport_conflict`.
- **file:*** — Package/file system. Examples: `file:read_error`, `file:circular_import`.

**Error code catalog (representative):**

| Code | Description |
|------|-------------|
| `parse:unexpected_token` | Unexpected token; expected another token. |
| `parse:expected_semicolon` | Expected `;` (e.g. after statement in block). |
| `parse:unmatched_brace` | Unmatched `{`; expected `}`, or (when the message is “Expected expression before `}`”) a **block** in **expression** context ended after a statement only—add a trailing expression or explicit `()` (01 §3.3). |
| `parse:expected_expr` | Expected expression. |
| `resolve:module_not_found` | Module could not be resolved. |
| `type:unknown_variable` | Unknown variable (optionally with suggestion). |
| `type:unify` | Type mismatch (unification failed). |
| `type:non_exhaustive_match` | Match is not exhaustive. |
| `type:check` | General type-check error. |
| `type:break_outside_loop` | `break` is not inside a `while` body. |
| `type:continue_outside_loop` | `continue` is not inside a `while` body. |
| `type:narrow_impossible` | `e is T` rejected: **T** does not structurally overlap the type of **e** (06 §4). |
| `type:narrow_opaque` | `is` on an imported **opaque** ADT: RHS must be the exported type name only (06 §5.3, 07 §5.3). |
| `export:not_exported` | Module does not export the requested name. |
| `export:reexport_conflict` | The same export name would come from more than one source (07 §3.3). |
| `compile:jvm_namespace_constructor` | JVM compile path does not support namespace-qualified ADT constructor calls (`M.Ctor(…)`); use a wrapper function in the dependency. |
| `file:read_error` | Could not read file. |
| `file:circular_import` | Circular import detected. |

The compiler only needs to emit the code and the message.

---

## 5. Per-phase Requirements

| Phase       | Emits diagnostics | Location source                          |
|------------|--------------------|------------------------------------------|
| Parser     | Yes (multiple)     | Token span; file from caller             |
| Resolver   | Yes (caller builds)| Caller provides file + import decl span  |
| Typecheck  | Yes (multiple)     | AST node span + sourceFile from options  |
| Compile-file | Yes              | filePath; for import/export, import span |

The parser may collect multiple diagnostics (e.g. with error recovery for missing semicolons or unmatched braces) and return them; it may also throw a single error (converted to one Diagnostic by the caller). The typechecker collects multiple diagnostics where possible. Resolver returns success/failure; the caller (e.g. compile-file) builds Diagnostic(s) with file and import span.

---

## 6. Human-readable Output

When the CLI (or any consumer) prints diagnostics in human form:

- **Stream:** stderr.
- **Format (per diagnostic):**
  - First line: `  --> <file>:<line>:<column>` (optional range: `-<endLine>:<endColumn>`).
  - Then one or more lines of context: line number and the source line (e.g. ` 12 |   let x = 1`).
  - Then a caret line under the span: `^` for a single column or `^^^` (or similar) for a range, with the message (e.g. `^ expected expression`).
  - Optional `= hint:` or `= note:` lines for `hint`, `suggestion`, or `related` messages.
- **Tabs:** Expand tabs to a fixed width (e.g. 4 spaces) so the caret aligns with the source.
- **Long lines:** Implementations may truncate with `...` and show the relevant segment (threshold is implementation-defined).
- **Colour:** Optional. When stderr is a TTY and colour is enabled, use ANSI codes (e.g. red for error, yellow for warning, dim for path/line numbers). Disabled when `NO_COLOR` is set or when output is not a TTY.
- **Multiple diagnostics:** Each diagnostic is printed in the same format; order is the order emitted by the compiler.

---

## 7. Machine-readable Output

- **Trigger:** CLI flag `--format=json` (or equivalent). When set, diagnostics are emitted in machine form only (no human snippet).
- **Format:** JSON Lines (one JSON object per line, one object per diagnostic). Each object has the same shape as Diagnostic: `severity`, `code`, `message`, `location` (object with `file`, `line`, `column`, and optional `endLine`, `endColumn`, `offset`, `endOffset`), and optional `sourceLine`, `related`, `suggestion`, `hint`.
- **Stream:** stderr (same as human).
- **No ANSI:** No colour or formatting codes in machine output.

---

## 8. Compiler API

- **compile(source, options?):** On failure, returns `{ ok: false, diagnostics: Diagnostic[] }`. Options may include `sourceFile?: string` for diagnostic file paths. No legacy `errors: string[]` is required.
- **compileFile(inputPath, options?):** On failure, returns `{ ok: false, diagnostics: Diagnostic[] }`. Every diagnostic has a `file` path (the file being compiled or the file containing the failing import). No legacy `errors: string[]` is required.

---

## 9. CLI

- **Exit code:** Non-zero when compilation fails (any diagnostic with severity `error`).
- **Output:** When compilation fails, diagnostics are printed per [10-compile-diagnostics.md](10-compile-diagnostics.md) §6 (human) or §7 (machine) depending on the output format option (e.g. `--format=json`).
- **Stream:** stderr for diagnostic output.

---

## 10. Relation to Other Specs

- [01-language.md](01-language.md) – Syntax errors (parser) relate to the grammar in 01.
- [06-typesystem.md](06-typesystem.md) – Type errors (typechecker) relate to the type system in 06.
- [07-modules.md](07-modules.md) – Resolution and export errors relate to module resolution and exports in 07.
- [09-tools.md](09-tools.md) – CLI invocation, streams, and exit codes; compile error format and behaviour are specified in this document (10).
