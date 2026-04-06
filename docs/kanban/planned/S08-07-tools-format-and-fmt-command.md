# kestrel:tools/format + kestrel fmt command

## Sequence: S08-07
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/unplanned/E08-source-formatter.md)
- Companion stories: S08-01, S08-02, S08-03, S08-04, S08-05, S08-06

## Summary

Create `stdlib/kestrel/tools/format.ks` — the opinionated Kestrel source code formatter — and add `kestrel fmt` as a thin CLI alias for `./kestrel run kestrel:tools/format`. The formatter reads source files, parses them with `kestrel:dev/parser`, converts the AST to a `Doc` IR using `kestrel:dev/text/prettyprinter`, and renders at 120 columns. It writes the formatted result back to the file, or to stdout when `--stdin` is used.

## Current State

No source formatter exists for Kestrel. All formatting is manual.

## Relationship to other stories

- **Depends on** S08-01 (namespace restructure) — imports from `kestrel:data/*`, `kestrel:io/*`.
- **Depends on** S08-02 (module-specifier support) — `./kestrel run kestrel:tools/format` must work.
- **Depends on** S08-03 (dev/cli) — uses `Cli.run` with its `CliSpec`.
- **Depends on** S08-04 (prettyprinter) — uses the `Doc` IR for rendering.
- **Depends on** S08-05 (dev/parser) — uses `lex` and `parse` to read source.
- **Final story in E08.**

## Goals

1. Implement `stdlib/kestrel/tools/format.ks` with:
   - `CliSpec` and `main : List<String> -> Task<Int>` using `Cli.run`.
   - `format : String -> Result<String, FormatError>` — formats source text.
   - `formatFile : String -> Task<Result<Unit, FormatError>>` — reads, formats, writes.
2. Implement all formatting rules from the epic:
   | Rule | Value |
   |------|-------|
   | Line width | 120 characters |
   | Indent unit | 2 spaces |
   | `fun` body | Always break after `=`; body indented 2 |
   | `match` arms | Each arm on its own line; multiline body indented 2 |
   | `if`/`else` | Inline when ≤ 120; break branches otherwise |
   | Record literals | Inline when short; one field per line when long |
   | List literals | Inline when short; one element per line when long |
   | Function call args | Inline when short; one per line when long |
   | Pipeline `\|>` | Each step on its own line |
   | Imports | All specs on one line when short; one spec per line when long |
   | Trailing newline | Always exactly one |
3. Add `kestrel fmt` alias in `scripts/kestrel`.
4. Add `kestrel fmt --check` mode: exit non-zero without modifying files.
5. Add stdin/stdout mode when `--stdin` is given.

## Acceptance Criteria

- `kestrel fmt hello.ks` reformats `hello.ks` in-place.
- `kestrel fmt --check hello.ks` exits 0 if already formatted, 1 if not, without modifying the file.
- `cat hello.ks | kestrel fmt --stdin` reads from stdin, writes formatted output to stdout.
- When no args and no `--stdin`, print usage/help.
- Formatter is **idempotent**: `format(format(source)) == format(source)` — verified by a test that formats every file in `stdlib/kestrel/` twice and asserts the second pass is identical.
- All files in `tests/conformance/`, `tests/unit/`, `stdlib/kestrel/` pass through the formatter without changing runtime output (run tests before and after formatting; both must pass).
- `./kestrel run kestrel:tools/format --help` prints auto-generated help from `CliSpec`.
- `kestrel fmt --version` prints `format 0.1.0`.
- `cd compiler && npm test` passes.
- `./scripts/kestrel test` passes.
- `./scripts/run-e2e.sh` passes (both positive and negative E2E scenarios).

## Spec References

- `docs/specs/01-language.md` — formatting rules align with language grammar
- `docs/specs/02-stdlib.md` — stdlib public API
- `docs/specs/09-tools.md` — `kestrel fmt` CLI reference

## Risks / Notes

- The formatter outputs source code regenerated from the AST + comment tokens. Comments that appear between tokens must be re-attached to AST nodes (most likely as leading/trailing trivia). This is the hardest part of the formatter.
- Test idempotency by formatting all stdlib files and checking the second pass produces no diff.
- The `--check` flag is important for CI: `kestrel fmt --check ./**/*.ks` should pass in CI after the formatter is applied.
- If `kestrel:dev/parser` does not preserve all whitespace/comment tokens (from S08-05), source round-trip is lossless only for the structured layout. Comments that appear in unusual positions may be re-located. Document any such limitations in the spec.
- `FormatError` should include a parse error message and the failing file path.
- Start with declarations and simple expressions; layer in complex forms (match, record, pipeline) as the test corpus grows.
- **Comment re-attachment is a first-class concern** — Phase H is designed to preserve top-level leading comments (the common case). Intra-expression comments (e.g. a `//` inside a function body) are not preserved in the first version; this is a known limitation to document.
- **Stdin reading requires a new KRuntime primitive** — `System.in` is not currently accessible via stdlib; Phase A adds it.
- **AST nodes carry no spans** — `kestrel:dev/parser` AST types have no source-position fields. Comment association (Phase H) therefore works at the token-stream level, not at the AST-node level.
- **Literal re-encoding** — `ELit("string", decodedValue)` stores the decoded value; the formatter must re-encode it (add quotes, escape `\n` etc.). `ELit("int","0xff")` stores the raw text and can be emitted verbatim.
- **Formatting reference** — `samples/lambda.ks` is the primary style reference. Key rules derived from it:
  - `fun` body **always** breaks: `fun f(...): T =\n  body` even for single-line bodies.
  - `match` arms: `pat =>\n  body` (pattern and `=>` on one line, body on next, indented +2 from arm column).
  - Chained `if/else if/else`: `if (c)\n  t\nelse if (c2)\n  t2\nelse\n  e` — `else` keyword at same column as `if`.
  - When `else`/`then` branch is a `{ block }`, opening `{` stays on the `if`/`else` line.
  - Pipelines always break: each `|>` step on its own line indented by 2 from the first.
  - No trailing semicolons inside blocks; stmts separated by newlines only.
  - `type` ADT with ≥2 constructors: `type T =\n    Ctor1\n  | Ctor2` (first +4, rest +2 with `| `).
  - Blank line between each top-level declaration.

---

## Impact Analysis

| Area | Change |
|------|--------|
| `runtime/jvm/src/kestrel/runtime/KRuntime.java` | Add `readAllStdin()` — reads `System.in` to EOF as UTF-8 |
| `stdlib/kestrel/io/fs.ks` | Add `export async fun readStdin(): Task<String>` wrapping the new JVM primitive |
| `stdlib/kestrel/tools/format.ks` | New file — `FormatError`, all `fmt*` Doc functions, `format`, `formatFile`, `checkFile`, `cliSpec`, `main` |
| `stdlib/kestrel/tools/format.test.ks` | New file — unit tests for all formatter phases |
| `scripts/kestrel` | Add `fmt` command alias (`cmd_fmt`) and entry in `usage()` and main `case` dispatch |
| `docs/specs/09-tools.md` | Add §2.5 `kestrel fmt` — usage, flags, exit codes |
| `docs/specs/02-stdlib.md` | Add `kestrel:tools/format` module entry |
| Compiler / JVM codegen | No changes |

---

## Tasks

Work in phases A → K. Each phase is independently committable.

### Phase A — Stdin support (KRuntime + stdlib)

- [ ] Add `public static Object readAllStdin()` to `KRuntime.java` — reads `System.in` until EOF using `BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8))`, returns the full content as a Kestrel `String` (Java `String`)
- [ ] Add `extern fun readAllStdinAsync(): Task<String>` and `export async fun readStdin(): Task<String>` (returning the stdin content) in `stdlib/kestrel/io/fs.ks`, using the JVM binding `kestrel.runtime.KRuntime#readAllStdin()`
- [ ] Run `cd runtime/jvm && bash build.sh` to rebuild the runtime jar
- [ ] Smoke-test: `echo "hello" | ./kestrel run -e 'import { readStdin } from "kestrel:io/fs"; val s = await readStdin(); println(s)'`

### Phase B — format.ks skeleton: imports, FormatError, literal encoders

- [ ] Create `stdlib/kestrel/tools/format.ks` with all necessary imports:
  ```
  import * as Lst from "kestrel:data/list"
  import * as Str from "kestrel:data/string"
  import * as Opt from "kestrel:data/option"
  import * as Res from "kestrel:data/result"
  import { readText, writeText, readStdin } from "kestrel:io/fs"
  import * as PP from "kestrel:dev/text/prettyprinter"
  import { Doc, Empty, Text } from "kestrel:dev/text/prettyprinter"
  import * as Cli from "kestrel:dev/cli"
  import * as Token from "kestrel:dev/parser/token"
  import * as Ast from "kestrel:dev/parser/ast"
  import { lex } from "kestrel:dev/parser/lexer"
  import { parse, ParseError } from "kestrel:dev/parser/parser"
  import { getProcess } from "kestrel:sys/process"
  ```
- [ ] Define `export type FormatError = FmtParseError(String, Int, Int, Int) | FmtIoError(String)` — parse errors carry (message, offset, line, col); I/O errors carry a message string
- [ ] Define `val fmtWidth: Int = 120` and `val fmtIndent: Int = 2`
- [ ] Implement `fun encodeString(s: String): String` — surround with `"`, escape `\n → \\n`, `\r → \\r`, `\t → \\t`, `\\ → \\\\`, `" → \\"`, all other chars pass through; use a char-by-char scan (`Str.codePointAt` loop) building the output with `Str.concat`
- [ ] Implement `fun encodeChar(c: String): String` — same as `encodeString` but surround with `'` and escape `' → \\'` instead of `" → \\"`; input `c` is a single decoded character (or empty for edge cases)
- [ ] Implement `fun commaDoc(docs: List<Doc>): Doc` — `PP.encloseSep(PP.text("("), PP.text(")"), PP.text(", "), docs)` — inline comma-separated list in parens
- [ ] Implement `fun commaSepBreak(open: String, close: String, docs: List<Doc>): Doc` — `PP.group(PP.encloseSep(PP.text(open), PP.text(close), PP.concat(PP.comma, PP.line), docs))` — inline when fits, one-per-line when broken (use `PP.nest(fmtIndent, ...)` for broken form)
- [ ] Verify file compiles: `./kestrel build stdlib/kestrel/tools/format.ks`

### Phase C — Type expression Doc

- [ ] Implement `fun fmtTypeField(f: Ast.TypeField): Doc` — `[mut ]name: T` (prefix `mut ` when `f.mut_`)
- [ ] Implement `fun fmtType(t: Ast.AstType): Doc` dispatching all 10 variants:
  - `ATPrim(n)` → `PP.text(n)`
  - `ATIdent(n)` → `PP.text(n)`
  - `ATQualified(m, n)` → `PP.text("${m}.${n}")`
  - `ATRowVar(r)` → `PP.text("...${r}")`
  - `ATApp(n, args)` → `PP.hcat([PP.text(n), PP.text("<"), PP.hcat(PP.punctuate(PP.text(", "), Lst.map(args, fmtType))), PP.text(">")])`
  - `ATUnion(a, b)` → `PP.hsep([fmtType(a), PP.text("|"), fmtType(b)])`
  - `ATInter(a, b)` → `PP.hsep([fmtType(a), PP.text("&"), fmtType(b)])`
  - `ATTuple(ts)` → join `fmtType` results with ` * `
  - `ATRecord([])` → `PP.text("{}")`
  - `ATRecord(fields)` → `PP.group(PP.encloseSep(PP.text("{ "), PP.text(" }"), PP.text(", "), Lst.map(fields, fmtTypeField)))`
  - `ATArrow([], ret)` → `fmtType(ret)` (edge case — emit just return type)
  - `ATArrow([p], ret)` → `PP.hcat([fmtType(p), PP.text(" -> "), fmtType(ret)])`
  - `ATArrow(params, ret)` → `PP.hcat([PP.text("("), PP.hcat(PP.punctuate(PP.text(", "), Lst.map(params, fmtType))), PP.text(") -> "), fmtType(ret)])`
- [ ] Implement `fun fmtParam(p: Ast.Param): Doc` — `name` when `type_=None`; `name: T` when `type_=Some(t)` (using `fmtType(t)`)
- [ ] Implement `fun fmtTypeParams(ps: List<String>): Doc` — empty `Doc` when list empty; `<A, B>` when non-empty
- [ ] Implement `fun fmtParamList(ps: List<Ast.Param>): Doc` — `(p1, p2)` using comma-sep; always inline (param lists are short)
- [ ] Verify `./kestrel build stdlib/kestrel/tools/format.ks` compiles cleanly

### Phase D — Pattern Doc

- [ ] Implement `fun fmtConField(f: Ast.ConField): Doc` — for positional fields (`name` starts with `"__field_"`), emit just the pattern; for record fields with `pattern=Some(PVar(name))` where name matches field name, emit just `name` (shorthand); otherwise emit `name = pat`
- [ ] Implement `fun fmtPattern(p: Ast.Pattern): Doc` dispatching all 7 variants:
  - `PWild` → `PP.text("_")`
  - `PVar(x)` → `PP.text(x)`
  - `PLit("unit", _)` → `PP.text("()")`
  - `PLit("true", _)` → `PP.text("True")`
  - `PLit("false", _)` → `PP.text("False")`
  - `PLit("string", v)` → `PP.text(encodeString(v))`
  - `PLit("char", v)` → `PP.text(encodeChar(v))`
  - `PLit(_, v)` → `PP.text(v)` (int, float — raw value stored verbatim)
  - `PCon(n, [])` → `PP.text(n)`
  - `PCon(n, fields)` where all names start with `"__field_"` → `PP.hcat([PP.text(n), commaDoc(Lst.map(fields, fmtConField))])` (positional)
  - `PCon(n, fields)` otherwise → `PP.hcat([PP.text(n), PP.text("{"), PP.hcat(PP.punctuate(PP.text(", "), Lst.map(fields, fmtConField))), PP.text("}")])` (record)
  - `PList([], None)` → `PP.text("[]")`
  - `PList(pats, None)` → `PP.hcat([PP.text("["), PP.hcat(PP.punctuate(PP.text(", "), Lst.map(pats, fmtPattern))), PP.text("]")])`
  - `PList(pats, Some(rest))` → same but append `, ...rest` before `]`
  - `PCons(h, t)` → `PP.hsep([fmtPatternAtom(h), PP.text("::"), fmtPattern(t)])` — wrap `h` in parens when `h` is `PCons`
  - `PTuple(ps)` → `commaDoc(Lst.map(ps, fmtPattern))`
- [ ] Implement `fun fmtPatternAtom(p: Ast.Pattern): Doc` — wraps `fmtPattern(p)` in parens when `p` is `PCons` (needed for `(h :: t) :: rest`)
- [ ] Verify `./kestrel build stdlib/kestrel/tools/format.ks` compiles cleanly

### Phase E — Expression Doc

This is the largest phase. Work through sub-tasks in order:

- [ ] Implement `fun exprPrec(e: Ast.Expr): Int` — numeric precedence for binary-op context:
  - `EPipe` → 0; `ECons` → 1; `EBinary("|")` → 2; `EBinary("&")` → 3; `EIs` → 4
  - `EBinary("==" | "!=" | "<" | ">" | "<=" | ">=")` → 5
  - `EBinary("+" | "-")` → 6; `EBinary("*" | "/" | "%")` → 7; `EBinary("**")` → 8
  - `EUnary` → 9
  - All other forms (`ELit`, `EIdent`, `ECall`, `EField`, `EAwait`, `EIf`, `EMatch`, `ELambda`, `EBlock`, `ETemplate`, `EList`, `ERecord`, `ETuple`, `EThrow`, `ETry`, `ENever`) → 10 (atoms; never need outer parens)
- [ ] Implement `fun isRightAssoc(op: String): Bool` — `True` for `"**"`, `"::"`, `"|>"`, `"<|"`; `False` otherwise
- [ ] Implement `fun needsParens(parentPrec: Int, childExpr: Ast.Expr, isRightChild: Bool): Bool` — `True` when `exprPrec(child) < parentPrec`, OR `exprPrec(child) == parentPrec AND isRightAssoc AND NOT isRightChild`, OR `exprPrec(child) == parentPrec AND NOT isRightAssoc AND isRightChild`; `False` otherwise (if child is an atom, never wraps)
- [ ] Implement `fun wrapParens(d: Doc): Doc` — `PP.hcat([PP.text("("), d, PP.text(")")])`
- [ ] Implement `fun fmtExprInCtx(prec: Int, isRight: Bool, e: Ast.Expr): Doc` — calls `fmtExpr(e)`, wraps in `wrapParens` when `needsParens(prec, e, isRight)`
- [ ] Implement `fun fmtLit(kind: String, value: String): Doc`:
  - `"string"` → `PP.text(encodeString(value))`; `"char"` → `PP.text(encodeChar(value))`
  - `"unit"` → `PP.text("()")`; `"true"` → `PP.text("True")`; `"false"` → `PP.text("False")`
  - `"int" | "float"` → `PP.text(value)` (raw value verbatim)
- [ ] Implement `fun fmtCallExpr(callee: Ast.Expr, args: List<Ast.Expr>): Doc` — `callee(arg1, arg2)` using `commaSepBreak("(", ")", ...)`; callee formatted with `fmtExpr`
- [ ] Implement `fun fmtBinaryExpr(op: String, l: Ast.Expr, r: Ast.Expr): Doc`:
  - Prec = `exprPrec(EBinary(op, l, r))`
  - Left child: `fmtExprInCtx(prec, False, l)`; right child: `fmtExprInCtx(prec, True, r)`
  - Emit: `PP.group(PP.hsep([leftDoc, PP.text(op), rightDoc]))`
- [ ] Implement `fun fmtIfExpr(cond: Ast.Expr, then_: Ast.Expr, else_: Option<Ast.Expr>): Doc`:
  - Flat form: `if (cond) thenExpr[ else elseExpr]`
  - Broken form — then_ is EBlock: `if (cond) { stmts; result }` (EBlock keeps `{` on same line)
  - Broken form — then_ is not EBlock: `if (cond)\n  thenExpr`
  - `else`: if `else_=None`, omit; if `Some(EIf(...))`, emit `else if (...)` on same line; if `Some(EBlock)`, `else {`; otherwise `else\n  elseExpr`
  - Wrap the whole thing in `PP.group(...)` so it collapses to one line when ≤120 cols (except when then/else contain blocks — blocks always break)
- [ ] Implement `fun fmtWhileExpr(cond: Ast.Expr, body: Ast.Block): Doc` — `while (cond) {` + block body (always broken; no group)
- [ ] Implement `fun fmtCase(c: Ast.Case_): Doc` — `fmtPattern(c.pattern)` + ` =>` + `PP.nest(fmtIndent, PP.concat(PP.line, fmtExpr(c.body)))` (pattern and `=>` on one line, body on next line indented by 2)
- [ ] Implement `fun fmtMatchExpr(scrutinee: Ast.Expr, cases: List<Ast.Case_>): Doc` — `match (scrutinee) {` + newline + each case indented by 2 + `,\n` between cases + `}` on its own line; cases always broken (no group)
- [ ] Implement `fun fmtLambdaExpr(async_: Bool, typeParams: List<String>, params: List<Ast.Param>, body: Ast.Expr): Doc` — `[async ](typeParams)(params) => body`; async prefix when `async_`; typeParams via `fmtTypeParams`; params via `fmtParamList`; body via `fmtExpr`; inline when body is short (wrap in `PP.group(...)`)
- [ ] Implement `fun fmtTmplPart(p: Ast.TmplPart): String` — `TmplLit(s)` → `s`; `TmplExpr(e)` → `"${" ++ PP.pretty(fmtWidth, fmtExpr(e)) ++ "}"`
- [ ] Implement `fun fmtTemplateExpr(parts: List<Ast.TmplPart>): Doc` — reconstruct `"..."` with interpolations: collect `Str.join("", Lst.map(parts, fmtTmplPart))`, emit as `PP.text("\"${content}\"")`
- [ ] Implement `fun fmtListElem(e: Ast.ListElem): Doc` — `LElem(ex)` → `fmtExpr(ex)`; `LSpread(ex)` → `PP.hcat([PP.text("..."), fmtExpr(ex)])`
- [ ] Implement `fun fmtListLiteral(elems: List<Ast.ListElem>): Doc` — `[]` when empty; `[e1, e2]` using `commaSepBreak("[", "]", ...)`
- [ ] Implement `fun fmtRecField(f: Ast.RecField): Doc` — `[mut ]name = value`
- [ ] Implement `fun fmtRecordLiteral(spread: Option<Ast.Expr>, fields: List<Ast.RecField>): Doc`:
  - Spread doc: `...expr, ` prefix when `Some(e)` → `PP.hcat([PP.text("..."), fmtExpr(e)])`
  - Empty record `{}`; one-field `{ f = v }` (group, inline); multi-field with `commaSepBreak`
  - All docs: `[spreadDoc?] ++ Lst.map(fields, fmtRecField)`; wrapped with `{ ` and ` }` delimiters
- [ ] Implement `fun fmtTupleLiteral(elems: List<Ast.Expr>): Doc` — `(e1, e2)` using `commaDoc`
- [ ] Implement `fun fmtPipeExpr(op: String, l: Ast.Expr, r: Ast.Expr): Doc` — always broken: `fmtExpr(l)` + newline + `PP.nest(fmtIndent, PP.hcat([PP.text(op ++ " "), fmtExpr(r)]))`; chains: the left side is also an `EPipe` so nesting naturally produces the staircase layout
- [ ] Implement `fun fmtConsExpr(l: Ast.Expr, r: Ast.Expr): Doc` — `fmtExprInCtx(1, False, l)` + ` :: ` + `fmtExprInCtx(1, True, r)` (right-assoc: no parens on right unless lower prec)
- [ ] Implement `fun fmtTryExpr(body: Ast.Block, catchVar: Option<String>, cases: List<Ast.Case_>): Doc` — `try {` block `} catch[( [var] name )] {` cases `}`
- [ ] Implement full `fun fmtExpr(e: Ast.Expr): Doc` dispatcher for all 22 variants calling the above helpers; for `EAwait(inner)` → `PP.beside(PP.text("await"), fmtExpr(inner))`; for `EThrow(inner)` → `PP.beside(PP.text("throw"), fmtExpr(inner))`; for `EUnary(op, inner)` → `PP.hcat([PP.text(op), fmtExpr(inner)])` (no space between op and operand for `-x`, `!x`); for `EIs(e, t)` → `PP.hsep([fmtExpr(e), PP.text("is"), fmtType(t)])`;  `ENever` → `PP.empty`

### Phase F — Statement and Block Doc

- [ ] Implement `fun fmtStmt(s: Ast.Stmt): Doc`:
  - `SVal(name, None, e)` → `PP.hsep([PP.text("val"), PP.text(name), PP.text("="), fmtExpr(e)])`
  - `SVal(name, Some(t), e)` → `PP.hsep([PP.text("val"), PP.hcat([PP.text(name), PP.text(": "), fmtType(t)]), PP.text("="), fmtExpr(e)])`
  - `SVar(name, typeAnn, e)` → same as `SVal` but `var` keyword
  - `SAssign(target, rhs)` → `PP.hsep([fmtExpr(target), PP.text(":="), fmtExpr(rhs)])`
  - `SExpr(e)` → `fmtExpr(e)`
  - `SFun(async_, name, typeParams, params, retType, body)` → same layout as top-level `fun` (always break body): `[async ]fun name[<A>](params): retType =` + newline + 2-space indent + body
  - `SBreak` → `PP.text("break")`; `SContinue` → `PP.text("continue")`
- [ ] Implement `fun fmtBlock(b: Ast.Block): Doc` — `{` + newline + stmts and result indented by 2 + newline + `}`:
  - Collect all `Stmt` docs + the result doc (`fmtExpr(b.result)`) unless result is `ENever`
  - If result is `ENever` (block ends with `break`/`continue`): emit all stmts including the `SBreak`/`SContinue` and omit the `ENever`
  - Separate each item with `PP.line` (newline in broken mode)
  - Wrap with `PP.hcat([PP.text("{"), PP.nest(fmtIndent, PP.vcat([PP.empty] ++ items)), PP.line, PP.text("}")])`
  - Edge case empty block `{ }` → `PP.text("{}")` when no stmts and result is `ELit("unit","()")`
- [ ] Verify `./kestrel build stdlib/kestrel/tools/format.ks` compiles cleanly

### Phase G — Declaration Doc

- [ ] Implement `fun fmtImportSpec(s: Ast.ImportSpec): Doc` — `name` when `external == local`; `external as local` otherwise
- [ ] Implement `fun fmtImportDecl(d: Ast.ImportDecl): Doc`:
  - `IDSideEffect(spec)` → `import "spec"`
  - `IDNamespace(spec, alias)` → `import * as Alias from "spec"`
  - `IDNamed(spec, [])` → `import {} from "spec"` (should not occur, but handle)
  - `IDNamed(spec, specs)` → `PP.group(PP.hcat([PP.text("import { "), PP.hcat(PP.punctuate(PP.text(", "), Lst.map(specs, fmtImportSpec))), PP.text(" } from \"${spec}\"")]))` — inline when fits; when broken: `import {\n  s1,\n  s2\n} from "spec"`
- [ ] Implement `fun fmtFunSignature(exported: Bool, async_: Bool, name: String, typeParams: List<String>, params: List<Ast.Param>, retType: Ast.AstType): Doc` — `[export ][async ]fun name[<A, B>](params): retType =`
- [ ] Implement `fun fmtFunBody(sig: Doc, body: Ast.Expr): Doc` — `sig` + `PP.nest(fmtIndent, PP.concat(PP.line, fmtExpr(body)))` — body always on new line at +2; no `PP.group` (always broken)
- [ ] Implement `fun fmtFunDecl(d: Ast.FunDecl, exported: Bool): Doc` — calls `fmtFunSignature` then `fmtFunBody`
- [ ] Implement `fun fmtCtorDef(c: Ast.CtorDef): Doc` — `Name` when `params=[]`; `Name(T1, T2)` when params non-empty
- [ ] Implement `fun fmtTypeBody(body: Ast.TypeBody): Doc`:
  - `TBAlias(t)` → `fmtType(t)`
  - `TBAdt([c])` → `fmtCtorDef(c)` (single ctor, inline)
  - `TBAdt(ctors)` → multi-ctor layout:
    ```
    Ctor1
      | Ctor2
      | Ctor3
    ```
    First ctor indented by +2 (from `=`'s column + 2), subsequent ctors at same +2 with `  | ` prefix (note: this aligns `|` at +2 from the `=` column)
- [ ] Implement `fun fmtTypeDecl(d: Ast.TypeDecl, exported: Bool): Doc`:
  - Visibility prefix: `""` for local, `"export "` for exported, `"opaque "` for opaque, `"export opaque "` for both
  - `[prefix]type Name[<A>] =\n  body` (body on new line, always broken, as per lambda.ks style)
  - Single-ctor ADT stays on one line: `type Name = Ctor`
- [ ] Implement `fun fmtExceptionDecl(d: Ast.ExceptionDecl, exported: Bool): Doc`:
  - `[export ]exception Name` when `fields=None`
  - `[export ]exception Name { field1: T1, field2: T2 }` when `fields=Some(fs)` (inline or broken)
- [ ] Implement `fun fmtExternFunDecl(d: Ast.ExternFunDecl, exported: Bool): Doc` — `[export ]extern fun name[<A>](params): retType =\n  jvm("desc")`
- [ ] Implement `fun fmtExternTypeDecl(d: Ast.ExternTypeDecl): Doc` — handles `visibility` field for `local`/`opaque`/`export` variants; `[export ][opaque ]extern type Name[<A>] =\n  jvm("class")`
- [ ] Implement `fun fmtExternOverride(o: Ast.ExternOverride): Doc` — `name(params): retType`
- [ ] Implement `fun fmtExternImportDecl(d: Ast.ExternImportDecl): Doc` — `extern import "target" as alias { overrides }`
- [ ] Implement `fun fmtExportInner(e: Ast.ExportInner): Doc`:
  - `EIStar(spec)` → `export * from "spec"`
  - `EINamed(spec, specs)` → `export { s1, s2 } from "spec"` (same group-breaking as import)
  - `EIDecl(decl)` → `fmtTopDecl(decl)` (declaration-level export handled at the decl level, this case is for re-exported decls included in body)
- [ ] Implement `fun fmtTopDecl(d: Ast.TopDecl): Doc` — dispatches all 13 variants; for `TDSVal`/`TDSVar`/`TDSAssign`/`TDSExpr` (top-level statement forms), emit the same as their statement counterparts; for `TDFun`/`TDVal`/`TDVar`/`TDType`/`TDException`/`TDExternFun`/`TDExternType`/`TDExternImport`/`TDExport`, delegate to the appropriate `fmt*` function with `exported=True/False` as applicable

### Phase H — Comment extraction and leading-comment association

This phase preserves `//` and `/* */` comments that appear **immediately before** a top-level declaration keyword (at column 1). Intra-expression comments are not preserved (known limitation).

- [ ] Implement `fun walkComments(tokens: List<Token.Token>, declStart: Int, acc: List<String>, ws: String): List<String>` — recursive walk backwards through the full token list to collect comments immediately preceding the token at `declStart` offset; stops when it hits a non-trivia token or when `ws` (accumulated whitespace) contains more than one blank line; returns the comment lines in forward order
- [ ] Implement `fun buildDeclComments(allToks: List<Token.Token>): List<(Int, List<String>)>` — scan `allToks` for each non-trivia token at `span.col == 1` (a declaration-start candidate); for each such token call `walkComments` to collect its leading comment block; return a list of `(span.start, comments)` pairs for all tokens that have at least one preceding comment
- [ ] Implement `fun lookupComments(map: List<(Int, List<String>)>, spanStart: Int): List<String>` — return the comment list whose key matches `spanStart`, or `[]` if not found
- [ ] Implement `fun fmtCommentBlock(lines: List<String>): Doc` — emit each comment line as `PP.text(line)` followed by `PP.lineBreak`; returns `PP.empty` when `lines` is empty
- [ ] Thread the comment map through `fmtProgram` (Phase I): before emitting each `TopDecl`, call `lookupComments` with the first token's approximate position and prepend `fmtCommentBlock` to the declaration Doc

**Note:** The comment map key is the `span.start` of the first non-trivia token of each top-level declaration. Since `TopDecl` AST nodes do not carry spans, the association works by matching by declaration **order**: the Nth top-level declaration corresponds to the Nth non-trivia token sequence at column 1 in the full token stream. This is a positional heuristic — it works correctly for normal code structure.

### Phase I — Program formatter and core API

- [ ] Implement `fun fmtProgramDoc(prog: Ast.Program, allToks: List<Token.Token>): Doc`:
  - Build `commentMap` via `buildDeclComments(allToks)`
  - Emit each import declaration with `fmtImportDecl`, separated by `PP.lineBreak`
  - If imports non-empty, add one blank line before the body
  - Emit each top-level declaration with `fmtTopDecl` prepended by `fmtCommentBlock(lookupComments(commentMap, ...))`
  - Separate top-level declarations with two `PP.lineBreak` (blank line between them)
- [ ] Implement `export fun format(src: String): Result<String, FormatError>`:
  - `val allToks = lex(src)`
  - `match (parse(allToks)) { Err(ParseError(msg, off, ln, col)) => Err(FmtParseError(msg, off, ln, col)), Ok(prog) => ... }`
  - `val doc = fmtProgramDoc(prog, allToks)`
  - `val rendered = PP.pretty(fmtWidth, doc)`
  - Ensure exactly one trailing newline: `if (Str.endsWith("\n", rendered)) Ok(rendered) else Ok("${rendered}\n")`
- [ ] Implement `export async fun formatFile(path: String): Task<Result<Unit, FormatError>>`:
  - `await readText(path)` → on `Err(fsErr)` map to `Err(FmtIoError(...))`; on `Ok(src)` call `format(src)`
  - On format error return it; on `Ok(formatted)` call `writeText(path, formatted)` and map fs error
- [ ] Implement `export async fun checkFile(path: String): Task<Result<Bool, FormatError>>`:
  - Same read + format steps; return `Ok(Str.equals(src, formatted))` (True = already formatted, False = would change)
- [ ] Verify `./kestrel build stdlib/kestrel/tools/format.ks`

### Phase J — Tests (`stdlib/kestrel/tools/format.test.ks`)

- [ ] Create `stdlib/kestrel/tools/format.test.ks` with imports for test harness and `format`, `formatFile` from `kestrel:tools/format`; add `export fun run(s: Suite): Task<Unit>` entry point
- [ ] Implement `fun ok(src: String): String` helper — calls `format(src)`, asserts `Ok`, returns formatted string
- [ ] Implement `fun chk(s: Suite, name: String, src: String, expected: String): Unit` — `eq(s, name, ok(src), expected)`

**Literal and basic expression tests:**
- [ ] `chk "val x = 42" → "val x = 42\n"` (integer literal, trailing newline added)
- [ ] `chk "val x = 3.14" → "val x = 3.14\n"` (float)
- [ ] `chk "val s = \"hello\"" → "val s = \"hello\"\n"` (string, decoded then re-encoded)
- [ ] `chk "val c = 'a'" → "val c = 'a'\n"` (char)
- [ ] `chk "val u = ()" → "val u = ()\n"` (unit)
- [ ] `chk "val b = True" → "val b = True\n"` (boolean literals)

**Encode/decode round-trip tests:**
- [ ] `encodeString("hello")` equals `"\"hello\""`
- [ ] `encodeString("a\nb")` equals `"\"a\\nb\""` (newline escaped)
- [ ] `encodeString("say \"hi\"")` equals `"\"say \\\"hi\\\"\""` (quote escaped)
- [ ] `encodeChar("a")` equals `"'a'"`
- [ ] `encodeChar("\n")` equals `"'\\n'"`

**Import formatting tests:**
- [ ] `import "m"` → `import "m"\n`
- [ ] `import * as M from "m"` → `import * as M from "m"\n`
- [ ] `import { foo } from "m"` → `import { foo } from "m"\n`
- [ ] `import { foo as bar } from "m"` → `import { foo as bar } from "m"\n`
- [ ] Long import (> 120 cols) breaks to one-spec-per-line

**Function declaration tests:**
- [ ] `fun f(x: Int): Int = x` → `fun f(x: Int): Int =\n  x\n` (body always on new line)
- [ ] `export fun f(): Unit = ()` → `export fun f(): Unit =\n  ()\n`
- [ ] `async fun f(): Task<Int> = 1` → `async fun f(): Task<Int> =\n  1\n`
- [ ] `fun f<A>(x: A): A = x` → `fun f<A>(x: A): A =\n  x\n`

**Type declaration tests:**
- [ ] `type Alias = Int` → `type Alias =\n  Int\n` (alias always breaks)
- [ ] `type Color = Red | Green | Blue` → multi-line ADT with `| ` prefix
- [ ] `opaque type T = Int` → `opaque type T =\n  Int\n`

**Match expression tests:**
- [ ] Format a `match (x) { 1 => 2 }` correctly (arm pattern, `=>`, body on next line)
- [ ] Multi-arm match produces each arm on its own line with correct indentation
- [ ] `PWild` arm becomes `_`; `PVar` arm becomes the variable name

**If/else tests:**
- [ ] Short `if (x) True else False` stays inline (fits in 120 cols)
- [ ] Long if/else breaks to multiple lines with `else` at same column as `if`

**Block tests:**
- [ ] `{ val x = 1; x }` → `{\n  val x = 1\n  x\n}`
- [ ] `{}` (empty record) is not the same as `{ () }` (block with unit result)

**Pipeline tests:**
- [ ] `xs |> Lst.map(f) |> Lst.filter(g)` → always broken: `xs\n  |> Lst.map(f)\n  |> Lst.filter(g)\n`

**Comment preservation tests:**
- [ ] A `// comment` on the line immediately before a `fun` declaration is emitted before the declaration in the output
- [ ] A comment between two declarations is associated with the declaration that follows it

**Idempotency test:**
- [ ] Load `samples/lambda.ks` source; apply `format` twice; assert `format(format(src)) == format(src)`
- [ ] Same test for `stdlib/kestrel/tools/format.ks` itself (format the formatter)

- [ ] Run: `./kestrel test stdlib/kestrel/tools/format.test.ks` → all tests pass

### Phase K — CLI entry point and `kestrel fmt` command

- [ ] Define `val cliSpec: Cli.CliSpec` in `format.ks`:
  ```
  {
    name = "kestrel fmt",
    version = "0.1.0",
    description = "Opinionated Kestrel source code formatter",
    usage = "kestrel fmt [--check] [--stdin] [files...]",
    options = [
      { short = Some("-c"), long = "--check",   kind = Flag, description = "Check if files are formatted; exit 1 if not" },
      { short = None,       long = "--stdin",   kind = Flag, description = "Read from stdin, write formatted output to stdout" }
    ],
    args = [{ name = "files", description = "Kestrel source files to format", variadic = True }]
  }
  ```
- [ ] Implement `fun fmtError(e: FormatError): String`:
  - `FmtParseError(msg, _, ln, col)` → `"parse error at ${ln}:${col}: ${msg}"`
  - `FmtIoError(msg)` → `"io error: ${msg}"`
- [ ] Implement `async fun handler(parsed: Cli.ParsedArgs): Task<Int>`:
  - If `--stdin` flag: `readStdin()`, `format(src)`, print to stdout; return 0 (1 on error, print error to stdout)
  - If `--check` + files: for each file, `checkFile`; accumulate failures; print `"NOT OK filename"` for each unformatted file; return 0 if all formatted, 1 if any not
  - If files only (no `--check`): for each file, `formatFile`; print `"formatted: filename"` on success; print error on failure; return 0 if all OK, 1 if any error
  - If no positional args and no `--stdin`: print `Cli.help(cliSpec)` and return 1
- [ ] Implement `export async fun main(allArgs: List<String>): Task<Int>` — `Cli.run(cliSpec, handler, allArgs)`; add a top-level call: `val exitCode = await main(getProcess().args); exit(exitCode)`
- [ ] Add `fmt` to `usage()` in `scripts/kestrel`:
  ```bash
  echo "  fmt   [--check] [--stdin] [files...]  Format Kestrel source files in-place" >&2
  ```
- [ ] Add `cmd_fmt()` function in `scripts/kestrel`:
  ```bash
  cmd_fmt() {
    ensure_tools
    build_if_needed
    exec node "$COMPILER_CLI" run --exit-wait kestrel:tools/format -- "$@"
  }
  ```
- [ ] Add `fmt) shift; cmd_fmt "$@" ;;` to the main `case "${1:-}"` dispatch in `scripts/kestrel`
- [ ] Smoke-test: `./kestrel fmt --help` prints usage and exits 0
- [ ] Smoke-test: `./kestrel fmt --version` prints `kestrel fmt v0.1.0` and exits 0
- [ ] Smoke-test: `./kestrel fmt --check samples/lambda.ks` — exits 0 if already formatted, 1 if not (either is correct; should not error or crash)
- [ ] Smoke-test: `cat samples/hello.ks | ./kestrel fmt --stdin` emits formatted source to stdout

### Final verification

- [ ] Run `./kestrel test --summary` — 1459+ tests pass
- [ ] Run `cd compiler && npm test` — 420+ tests pass
- [ ] Idempotency: `./kestrel fmt stdlib/kestrel/tools/format.ks && ./kestrel fmt --check stdlib/kestrel/tools/format.ks` exits 0
- [ ] Run `./scripts/run-e2e.sh` — all E2E scenarios pass

---

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel unit harness | `stdlib/kestrel/tools/format.test.ks` | All formatter phases: literal encoding, types, patterns, exprs, stmts, decls, idempotency |
| Kestrel unit harness | `stdlib/kestrel/tools/format.test.ks` | CLI smoke: `--help`, `--version`, `--check`, `--stdin` |
| Kestrel unit harness | `stdlib/kestrel/tools/format.test.ks` | Idempotency on `samples/lambda.ks` and `format.ks` itself |
| E2E positive | (manual CLI smoke in Phase K, already in acceptance criteria) | `fmt hello.ks` and `fmt --check` round-trip |

---

## Documentation and specs to update

- [ ] `docs/specs/09-tools.md` — add §2.5 `kestrel fmt`: usage line, `--check` and `--stdin` flags, exit codes (0 = success/already-formatted, 1 = needs formatting or error), known limitations (intra-expression comments not preserved)
- [ ] `docs/specs/02-stdlib.md` — add `kestrel:tools/format` module entry documenting `FormatError`, `format`, `formatFile`, `checkFile`, and `main`
