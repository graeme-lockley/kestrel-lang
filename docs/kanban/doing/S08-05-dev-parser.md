# kestrel:dev/parser — Kestrel lexer, AST, and parser (written in Kestrel)

## Sequence: S08-05
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/unplanned/E08-source-formatter.md)
- Companion stories: S08-01, S08-02, S08-03, S08-04, S08-06, S08-07

## Summary

Create four implementation files and four test files under `stdlib/kestrel/dev/parser/`:
`token.ks`, `token.test.ks`, `ast.ks`, `ast.test.ks`, `lexer.ks`, `lexer.test.ks`,
`parser.ks`, and `parser.test.ks`. Together they implement the full Kestrel lexer, AST,
and recursive-descent parser written in Kestrel. Consumers import directly from the
sub-module specifiers (e.g. `kestrel:dev/parser/lexer`); there is no top-level
re-export facade. The formatter (S08-07) and documentation browser (E09) import the
sub-modules they need.

## Current State

The authoritative Kestrel parser is the TypeScript implementation in
`compiler/src/parser/parse.ts` (1432 lines) with lexer in
`compiler/src/lexer/tokenize.ts` (330 lines) and AST nodes in
`compiler/src/ast/nodes.ts` (530 lines). The folder `stdlib/kestrel/dev/parser/` already
exists but is empty. This story creates a Kestrel-native second implementation that
matches the TypeScript parser's behaviour on all valid programs. Error recovery is **not**
required (the formatter only formats valid programs; compilation errors use the TS parser).

## Relationship to other stories

- **Depends on** S08-01 (namespace restructure) — imports from `kestrel:data/*`.
- **Required by** S08-07 (kestrel:tools/format).
- **Independent of** S08-03 (dev/cli) and S08-04 (prettyprinter).
- **Used by** E09 (documentation browser, future epic).

## Goals

1. **Token types** (`kestrel:dev/parser/token`) — `Span`, `TemplatePart`, `TokenKind`, `Token`, `isTrivia`.
2. **AST types** (`kestrel:dev/parser/ast`) — full recursive type hierarchy mirroring `compiler/src/ast/nodes.ts`.
3. **Lexer** (`kestrel:dev/parser/lexer`) — `lex : String -> List<Token>`, including whitespace and comments for round-trip.
4. **Parser** (`kestrel:dev/parser/parser`) — `parse : List<Token> -> Result<Program, ParseError>`, recursive descent, no error recovery.
5. **Unit tests** for each sub-module, runnable with `./kestrel test`.

## Acceptance Criteria

- `parse(lex(source))` succeeds for every `.ks` file in `tests/conformance/`, `stdlib/kestrel/`, and `samples/`.
- Round-trip: `Str.join("", Lst.map(lex(src), (t) => t.text)) == src` for every source file.
- Parse errors carry source offset, line, and column.
- Each sub-module has its own `*.test.ks` with passing tests covering all relevant functionality.
- Unit tests cover: all literal kinds, all keyword/operator/punctuation token kinds, all operator precedences, `match` with every pattern form, `if/else`, records, lists, `|>` pipes, blocks, `async`/`await`, imports, exports, type declarations.

## Spec References

- `docs/specs/01-language.md` — full language specification
- `docs/specs/02-stdlib.md` — stdlib API

## Risks / Notes

- The TypeScript parser is ground truth; when in doubt, match its behaviour exactly.
- Backtracking in `tryParseParenLambda` requires saving and restoring `ps.pos` — see Tasks § Phase D.
- String interpolation requires the lexer to extract the raw source text of each `${...}` segment, and the parser to recursively call `lex` + `parseExpr` on each segment. See Phase C note.
- The TS tokeniser skips whitespace/comments (no token emitted); the Kestrel lexer must emit them as `TkWs`/`TkLineComment`/`TkBlockComment`. The parser pre-filters them at startup.
- `True`/`False` are tokenised as `TkUpper` by the Kestrel lexer (the TS lexer emits `true`/`false` kind). The parser maps them to boolean literals in `parseAtom`.
- The TS `newline` token kind is declared but never actually emitted (all whitespace is skipped). The Kestrel parser does not need `newline`-as-separator logic.
- `records vs blocks` disambiguation: look one token ahead of `{`; if token+1 is `val`, `var`, `fun`, `async` → block; if `}` or `...` or `mut ident` → record; if `ident =` → record; else → block.
- `tryParseParenLambda` uses speculative parsing: save pos, attempt param list, check for `=>`, restore on failure. No errors should be recorded in the speculative pass — save `errors` list length and trim it on backtrack.
- This story is intentionally large. Work in the six phases below. Each phase can be committed independently.

---

## Impact Analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/dev/parser/token.ks` | New file — `Span`, `TemplatePart`, `TokenKind`, `Token` types |
| `stdlib/kestrel/dev/parser/token.test.ks` | New file — comprehensive unit tests for token |
| `stdlib/kestrel/dev/parser/ast.ks` | New file — all AST types mirroring `compiler/src/ast/nodes.ts` |
| `stdlib/kestrel/dev/parser/ast.test.ks` | New file — comprehensive unit tests for ast |
| `stdlib/kestrel/dev/parser/lexer.ks` | New file — `lex : String -> List<Token>`, mutable `LexState` record |
| `stdlib/kestrel/dev/parser/lexer.test.ks` | New file — `comprehensive unit tests for lexer |
| `stdlib/kestrel/dev/parser/parser.ks` | New file — `parse`, `parseExpr`, mutable `ParseState` record |
| `stdlib/kestrel/dev/parser/parser.test.ks` | New file — comprehensive tests for parser |
| Compiler / JVM codegen / JVM runtime | No changes |
| CI pipeline | No changes (new stdlib test file picked up automatically) |

---

## Tasks

Follow **TDD order** A → H. Phases pair as: (A tests, B impl), (C tests, D impl), (E tests, F impl), (G tests, H impl).

**Within each pair:**
1. Write the full test file first (the *-red* phase) — run tests to confirm compile error (module not
   yet written is the expected failure).
2. Implement the module (the *-green* phase) — run tests again to confirm all pass.

Do NOT skip ahead or implement before writing the corresponding tests.

---

### Phase A — Token unit tests — *TDD red* (`stdlib/kestrel/dev/parser/token.test.ks`)

- [x] Create `stdlib/kestrel/dev/parser/token.test.ks` with imports:
  ```
  import { run as testRun, group, test, assertEqual, assertTrue, assertFalse } from "kestrel:tools/test"
  import * as Token from "kestrel:dev/parser/token"
  ```
- [x] Add `export fun run(): Unit` entry point calling `testRun` with all groups

**`Token.spanZero` tests:**
- [x] Assert `Token.spanZero().start == 0`
- [x] Assert `Token.spanZero().end == 0`
- [x] Assert `Token.spanZero().line == 1`
- [x] Assert `Token.spanZero().col == 1`

**`Token.isTrivia` tests:**
- [x] Assert `Token.isTrivia({ kind = Token.TkWs, text = " ", span = Token.spanZero() }) == True`
- [x] Assert `Token.isTrivia({ kind = Token.TkLineComment, text = "// x", span = Token.spanZero() }) == True`
- [x] Assert `Token.isTrivia({ kind = Token.TkBlockComment, text = "/* */", span = Token.spanZero() }) == True`
- [x] Assert `Token.isTrivia({ kind = Token.TkIdent, text = "x", span = Token.spanZero() }) == False`
- [x] Assert `Token.isTrivia({ kind = Token.TkKw, text = "fun", span = Token.spanZero() }) == False`
- [x] Assert `Token.isTrivia({ kind = Token.TkEof, text = "", span = Token.spanZero() }) == False`

**`Token.TemplatePart` construction tests:**
- [x] Construct `Token.TPLiteral("hello")`, match to extract string, assert equals `"hello"`
- [x] Construct `Token.TPInterp("x + 1")`, match to extract string, assert equals `"x + 1"`
- [x] Construct `Token.TkTemplate([Token.TPLiteral("a"), Token.TPInterp("x")])`, match to verify list length is 2

- [x] Run: `./kestrel test stdlib/kestrel/dev/parser/token.test.ks` → confirm compile error (`token.ks` not yet written — **red phase**)

### Phase B — Token types — *TDD green* (`stdlib/kestrel/dev/parser/token.ks`)

- [x] Create `stdlib/kestrel/dev/parser/token.ks` with module-level imports: `import * as Lst from "kestrel:data/list"`
- [x] Define `export type Span = { start: Int, end: Int, line: Int, col: Int }`
- [x] Define `export type TemplatePart = TPLiteral(String) | TPInterp(String)`
  - `TPLiteral(String)` — a decoded literal text segment between interpolations
  - `TPInterp(String)` — the raw source of an interpolated expression (between `${` and `}`)
- [x] Define `export type TokenKind` sum type with all 14 variants:
  ```
  export type TokenKind =
      TkInt               // integer literal; token.text = raw ("42", "0xff", "0b101")
    | TkFloat             // float literal;   token.text = raw ("3.14", "1e10")
    | TkStr               // plain string;    token.text = raw source incl. surrounding "quotes"
    | TkTemplate(List<TemplatePart>)  // interpolated; token.text = full raw source incl. quotes
    | TkChar              // char literal;    token.text = raw source incl. surrounding 'quotes'
    | TkIdent             // lowercase-first identifier; token.text = name
    | TkUpper             // uppercase-first ident (incl. True, False); token.text = name
    | TkKw                // keyword; token.text = the keyword
    | TkOp                // operator; token.text = operator text
    | TkPunct             // punctuation; token.text = single-char string
    | TkWs                // whitespace (spaces, tabs, newlines); token.text = raw
    | TkLineComment       // // … to end-of-line; token.text = raw incl. "//"
    | TkBlockComment      // /* … */; token.text = raw incl. delimiters
    | TkEof               // end of file; token.text = ""
  ```
  Key invariant: `token.text` is **always the raw source text** — concatenating all token
  texts reconstructs the original source exactly (round-trip property).
  Additional notes embedded in comments:
  - `TkStr.text` and `TkChar.text` include their surrounding quote characters so round-trip holds. The parser decodes escape sequences from the raw text when constructing AST literals.
  - `True` and `False` → `TkUpper`, NOT `TkKw` (mirrors the TypeScript lexer's special handling).
  - Keywords (23 total): `as fun type val var mut if else while break continue match try catch throw async await export import from exception is opaque extern`
  - Multi-char operators (longest-match first): `=> := == != >= <= ** <| :: |> -> ...`
  - Single-char operators: `+ - * / % | & < > = !`
  - Single-char punctuation (not operators): `( ) { } [ ] , : . ;`
  - `:` alone is `TkPunct`; `::` is `TkOp` — multi-op check runs before single-char check.
- [x] Define `export type Token = { kind: TokenKind, text: String, span: Span }`
- [x] Implement `export fun isTrivia(t: Token): Bool` — returns `True` for `TkWs`, `TkLineComment`, `TkBlockComment`; `False` for all other variants
- [x] Implement `export fun spanZero(): Span` — returns `{ start = 0, end = 0, line = 1, col = 1 }`
- [x] Verify file compiles: `./kestrel build stdlib/kestrel/dev/parser/token.ks`
- [x] Run: `./kestrel test stdlib/kestrel/dev/parser/token.test.ks` → confirm all tests pass (**green**)

### Phase C — AST unit tests — *TDD red* (`stdlib/kestrel/dev/parser/ast.test.ks`)

- [x] Create `stdlib/kestrel/dev/parser/ast.test.ks` with imports for test harness and all exported types from `kestrel:dev/parser/ast`
- [x] Add `export fun run(): Unit` entry point

**AstType construction tests:**
- [x] Construct `ATIdent("Foo")`, match to extract name, assert equals `"Foo"`
- [x] Construct `ATArrow([ATPrim("Int")], ATPrim("Bool"))`, match params list and return type
- [x] Construct `ATApp("List", [ATPrim("Int")])`, match name and args
- [x] Construct `ATRecord([{ name = "x", mut_ = False, type_ = ATPrim("Int") }])`, match fields list
- [x] Construct `ATTuple([ATPrim("Int"), ATPrim("Bool")])`, match list length is 2
- [x] Construct `ATUnion(ATIdent("A"), ATIdent("B"))`, match both sides
- [x] Construct `ATQualified("Mod", "T")`, match both strings

**Pattern construction tests:**
- [x] Construct `PWild`, match fires the `PWild` branch
- [x] Construct `PVar("x")`, match to extract name, assert equals `"x"`
- [x] Construct `PLit("int", "42")`, match kind and value
- [x] Construct `PCon("Some", [{ name = "__field_0", pattern = Some(PVar("x")) }])`, match name and field
- [x] Construct `PList([PWild], Some("rest"))`, match list and rest name
- [x] Construct `PCons(PVar("h"), PVar("t"))`, match head and tail
- [x] Construct `PTuple([PVar("a"), PVar("b")])`, match elements list length is 2

**Expr construction tests:**
- [x] Construct `ELit("int", "42")`, match kind is `"int"` and value is `"42"`
- [x] Construct `EIdent("x")`, match name is `"x"`
- [x] Construct `ECall(EIdent("f"), [ELit("int", "1")])`, match callee and args
- [x] Construct `EBinary("+", ELit("int","1"), ELit("int","2"))`, match op and operands
- [x] Construct `EIf(EIdent("c"), EIdent("t"), Some(EIdent("e")))`, match all three parts
- [x] Construct `EIf(EIdent("c"), EIdent("t"), None)`, confirm else is `None`
- [x] Construct `ELambda(False, [], [{ name="x", type_=None }], EIdent("x"))`, match params list
- [x] Construct `ETemplate([TmplLit("hello "), TmplExpr(EIdent("name"))])`, match both parts
- [x] Construct `ERecord(None, [{ name="x", mut_=False, value=ELit("int","1") }])`, match spread is None and fields
- [x] Construct `ENever`, match fires the `ENever` branch

**Stmt construction tests:**
- [x] Construct `SVal("x", None, ELit("int","1"))`, match name and expr
- [x] Construct `SAssign(EIdent("x"), ELit("int","2"))`, match target and rhs
- [x] Construct `SBreak`, match fires
- [x] Construct `SContinue`, match fires
- [x] Construct `SFun(False, "f", [], [], ATPrim("Unit"), ELit("unit","()"))`, match name

**ImportDecl construction tests:**
- [x] Construct `IDNamed("m", [{ external="foo", local="bar" }])`, match spec and importspecs
- [x] Construct `IDNamespace("m", "M")`, match spec and alias
- [x] Construct `IDSideEffect("m")`, match spec

**TopDecl construction tests:**
- [x] Construct `TDSVal("x", ELit("int","1"))`, match name and expr
- [x] Construct `TDExport(EIStar("m"))`, match inner spec
- [x] Construct `TDType(TypeDecl{ visibility="local", name="T", typeParams=[], body=TBAlias(ATPrim("Int")) })`, match fields

**Program construction test:**
- [x] Construct `{ imports = [], body = [TDSExpr(ELit("unit","()"))] }`, match imports length 0, body length 1

- [x] Run: `./kestrel test stdlib/kestrel/dev/parser/ast.test.ks` → confirm compile error (`ast.ks` not yet written — **red phase**)

### Phase D — AST types — *TDD green* (`stdlib/kestrel/dev/parser/ast.ks`)

- [x] Create `stdlib/kestrel/dev/parser/ast.ks` with imports:
  ```
  import * as Lst from "kestrel:data/list"
  import * as Token from "kestrel:dev/parser/token"
  ```
  Naming conventions: field/type names clashing with reserved words get a trailing underscore (`type_`, `mut_`, `async_`).

**Type-level types:**
- [x] Define `export type AstType` sum type with all 10 variants:
  - `ATIdent(String)` — simple type name e.g. `"Foo"`
  - `ATQualified(String, String)` — qualified `Mod.T` (module name, type name)
  - `ATPrim(String)` — primitive: `"Int"`, `"Float"`, `"Bool"`, `"String"`, `"Unit"`, `"Char"`
  - `ATArrow(List<AstType>, AstType)` — function type `(A, B) -> C`
  - `ATRecord(List<TypeField>)` — record type `{ x: Int, mut y: Bool }`
  - `ATRowVar(String)` — row type variable `{ ...r }`
  - `ATApp(String, List<AstType>)` — generic application `List<T>`
  - `ATUnion(AstType, AstType)` — union `A | B`
  - `ATInter(AstType, AstType)` — intersection `A & B`
  - `ATTuple(List<AstType>)` — tuple product `A * B * C`
- [x] Define `export type TypeField = { name: String, mut_: Bool, type_: AstType }` (forward ref to `AstType` — declare `AstType` first)

**Parameter type:**
- [x] Define `export type Param = { name: String, type_: Option<AstType> }`

**Pattern types:**
- [x] Define `export type ConField = { name: String, pattern: Option<Pattern> }`
  - Positional patterns use names `"__field_0"`, `"__field_1"`, … (matching TypeScript behaviour)
  - Record-style patterns use the field name; `pattern = None` means bind the field name as a variable
- [x] Define `export type Pattern` sum type with all 7 variants:
  - `PWild` — wildcard `_`
  - `PVar(String)` — variable binding `x`
  - `PLit(String, String)` — literal pattern `(kind, raw-value)` e.g. `("int","42")`
  - `PCon(String, List<ConField>)` — constructor pattern `Some(x)` or `Con{f=p}`
  - `PList(List<Pattern>, Option<String>)` — list pattern `[a, b, ...rest]`
  - `PCons(Pattern, Pattern)` — cons pattern `head :: tail`
  - `PTuple(List<Pattern>)` — tuple pattern `(a, b, c)`

**Expression types:**
- [x] Define `export type RecField = { name: String, mut_: Bool, value: Expr }`
- [x] Define `export type ListElem = LElem(Expr) | LSpread(Expr)`
- [x] Define `export type TmplPart = TmplLit(String) | TmplExpr(Expr)`
- [x] Define `export type Case_ = { pattern: Pattern, body: Expr }`
- [x] Define `export type Block = { stmts: List<Stmt>, result: Expr }`
- [x] Define `export type Expr` sum type with all 22 variants:
  - `ELit(String, String)` — literal `(kind, raw-value)`; kinds: `"int"`,`"float"`,`"string"`,`"char"`,`"true"`,`"false"`,`"unit"`
  - `EIdent(String)` — identifier name
  - `ECall(Expr, List<Expr>)` — function call `f(args)`
  - `EField(Expr, String)` — field access `obj.field` (tuple index: `"0"`, `"1"`, …)
  - `EAwait(Expr)` — `await e`
  - `EUnary(String, Expr)` — unary operator `op e` (ops: `"-"`, `"+"`, `"!"`)
  - `EBinary(String, Expr, Expr)` — binary operator `l op r`
  - `ECons(Expr, Expr)` — list cons `a :: b`
  - `EPipe(String, Expr, Expr)` — pipe `left "|>" right` or `left "<|" right`
  - `EIf(Expr, Expr, Option<Expr>)` — `if cond then else?`
  - `EWhile(Expr, Block)` — `while cond body`
  - `EMatch(Expr, List<Case_>)` — `match scrutinee { cases }`
  - `ELambda(Bool, List<String>, List<Param>, Expr)` — lambda `(async, typeParams, params, body)`
  - `ETemplate(List<TmplPart>)` — interpolated string
  - `EList(List<ListElem>)` — list literal `[elems]`
  - `ERecord(Option<Expr>, List<RecField>)` — record literal `{ ...spread?, fields }`
  - `ETuple(List<Expr>)` — tuple `(a, b, c)`
  - `EThrow(Expr)` — `throw e`
  - `ETry(Block, Option<String>, List<Case_>)` — `try { } catch(var?) { cases }`
  - `EBlock(Block)` — block expression `{ stmts; result }`
  - `EIs(Expr, AstType)` — type test `e is T`
  - `ENever` — synthetic unreachable node (result position of `break`/`continue`)

**Statement types:**
- [x] Define `export type Stmt` sum type with all 7 variants:
  - `SVal(String, Option<AstType>, Expr)` — `val name : T? = e`
  - `SVar(String, Option<AstType>, Expr)` — `var name : T? = e`
  - `SAssign(Expr, Expr)` — `target := rhs`
  - `SExpr(Expr)` — standalone expression statement
  - `SFun(Bool, String, List<String>, List<Param>, AstType, Expr)` — local fun `(async, name, typeParams, params, retType, body)`
  - `SBreak` — `break`
  - `SContinue` — `continue`

**Declaration types:**
- [x] Define `export type CtorDef = { name: String, params: List<AstType> }`
- [x] Define `export type TypeBody = TBAdt(List<CtorDef>) | TBAlias(AstType)`
- [x] Define `export type FunDecl = { exported: Bool, async_: Bool, name: String, typeParams: List<String>, params: List<Param>, retType: AstType, body: Expr }`
- [x] Define `export type ExternFunDecl = { exported: Bool, name: String, typeParams: List<String>, params: List<Param>, retType: AstType, jvmDesc: String }`
- [x] Define `export type ExternTypeDecl = { visibility: String, name: String, typeParams: List<String>, jvmClass: String }` (visibility: `"local"` | `"opaque"` | `"export"`)
- [x] Define `export type ExternOverride = { name: String, params: List<Param>, retType: AstType }`
- [x] Define `export type ExternImportDecl = { target: String, alias: String, overrides: List<ExternOverride> }`
- [x] Define `export type TypeDecl = { visibility: String, name: String, typeParams: List<String>, body: TypeBody }`
- [x] Define `export type ExceptionDecl = { exported: Bool, name: String, fields: Option<List<TypeField>> }`

**Import / export / program types:**
- [x] Define `export type ImportSpec = { external: String, local: String }`
- [x] Define `export type ImportDecl` sum type:
  - `IDNamed(String, List<ImportSpec>)` — `import { x, y as z } from "spec"`
  - `IDNamespace(String, String)` — `import * as M from "spec"` (spec, alias)
  - `IDSideEffect(String)` — `import "spec"`
- [x] Define `export type ExportInner` sum type:
  - `EIStar(String)` — `export * from "spec"`
  - `EINamed(String, List<ImportSpec>)` — `export { x } from "spec"`
  - `EIDecl(TopDecl)` — `export <decl>`
- [x] Define `export type TopDecl` sum type with all 13 variants:
  - `TDFun(FunDecl)`
  - `TDExternFun(ExternFunDecl)`
  - `TDExternImport(ExternImportDecl)`
  - `TDExternType(ExternTypeDecl)`
  - `TDType(TypeDecl)`
  - `TDException(ExceptionDecl)`
  - `TDExport(ExportInner)`
  - `TDVal(String, Option<AstType>, Expr)` — `export val name : T? = e` (has type annotation)
  - `TDVar(String, Option<AstType>, Expr)` — `export var name : T? = e` (has type annotation)
  - `TDSVal(String, Expr)` — top-level `val name = e` (NO type annotation, NO export — matches TS `parseTopLevelStmt`)
  - `TDSVar(String, Expr)` — top-level `var name = e` (NO type annotation, NO export)
  - `TDSAssign(Expr, Expr)` — top-level assignment statement
  - `TDSExpr(Expr)` — top-level expression statement
- [x] Define `export type Program = { imports: List<ImportDecl>, body: List<TopDecl> }`
- [x] Verify file compiles: `./kestrel build stdlib/kestrel/dev/parser/ast.ks`
- [x] Run: `./kestrel test stdlib/kestrel/dev/parser/ast.test.ks` → confirm all tests pass (**green**)

### Phase E — Lexer unit tests — *TDD red* (`stdlib/kestrel/dev/parser/lexer.test.ks`)

- [ ] Create `stdlib/kestrel/dev/parser/lexer.test.ks` with imports for test harness, `lex`, and the `Token` namespace from `kestrel:dev/parser/token`
- [ ] Add `export fun run(): Unit` entry point
- [ ] Implement helper `fun kindOf(src: String): Token.TokenKind` — `lex(src)` then return kind of first token
- [ ] Implement helper `fun textOf(src: String): String` — `lex(src)` then return text of first token
- [ ] Implement helper `fun allKinds(src: String): List<Token.TokenKind>` — `lex(src)` then map `.kind`
- [ ] Implement helper `fun joinTexts(src: String): String` — `lex(src)` then `Str.join("", Lst.map(tokens, (t) => t.text))`

**Round-trip tests:**
- [ ] `joinTexts("") == ""`
- [ ] `joinTexts("fun main(): Unit = ()")` equals source
- [ ] `joinTexts("  val x = 1  ")` equals `"  val x = 1  "` (whitespace preserved)
- [ ] `joinTexts("// comment\nval x = 1")` equals original (line comment and newline preserved)
- [ ] `joinTexts("/* block */val x = 1")` equals original (block comment preserved)
- [ ] `joinTexts("\"hello\"")` equals `"\"hello\""` (string quotes in token text)
- [ ] `joinTexts("'a'")` equals `"'a'"` (char quotes in token text)
- [ ] `joinTexts("x // c\ny")` equals original (comment between two identifiers preserved)

**Whitespace and comment token tests:**
- [ ] `kindOf("  ")` equals `Token.TkWs`
- [ ] `kindOf("\n")` equals `Token.TkWs`
- [ ] `textOf("\t ")` equals `"\t "` (raw tabs and spaces)
- [ ] `kindOf("// hi")` equals `Token.TkLineComment`
- [ ] `textOf("// hi there")` equals `"// hi there"`
- [ ] `kindOf("/* hi */")` equals `Token.TkBlockComment`
- [ ] `textOf("/* hi */")` equals `"/* hi */"`

**Identifier and keyword tests:**
- [ ] `kindOf("foo")` equals `Token.TkIdent`
- [ ] `kindOf("_bar")` equals `Token.TkIdent`
- [ ] `textOf("myVar")` equals `"myVar"`
- [ ] `kindOf("Foo")` equals `Token.TkUpper`
- [ ] `kindOf("True")` equals `Token.TkUpper` (NOT `Token.TkKw`)
- [ ] `kindOf("False")` equals `Token.TkUpper` (NOT `Token.TkKw`)
- [ ] Test each keyword tokenises as `Token.TkKw` — one test per keyword (23 tests): `as`, `fun`, `type`, `val`, `var`, `mut`, `if`, `else`, `while`, `break`, `continue`, `match`, `try`, `catch`, `throw`, `async`, `await`, `export`, `import`, `from`, `exception`, `is`, `opaque`, `extern`

**Integer literal tests:**
- [ ] `kindOf("42")` equals `Token.TkInt`, `textOf("42")` equals `"42"`
- [ ] `kindOf("0")` equals `Token.TkInt`
- [ ] `kindOf("0xff")` equals `Token.TkInt`, `textOf("0xff")` equals `"0xff"`
- [ ] `kindOf("0b101")` equals `Token.TkInt`, `textOf("0b101")` equals `"0b101"`
- [ ] `kindOf("0o77")` equals `Token.TkInt`
- [ ] `kindOf("1_000_000")` equals `Token.TkInt`, `textOf("1_000_000")` equals `"1_000_000"`

**Float literal tests:**
- [ ] `kindOf("3.14")` equals `Token.TkFloat`, `textOf("3.14")` equals `"3.14"`
- [ ] `kindOf("1e10")` equals `Token.TkFloat`
- [ ] `kindOf("1.5e-3")` equals `Token.TkFloat`
- [ ] `kindOf(".5")` equals `Token.TkFloat`
- [ ] `kindOf("1E10")` equals `Token.TkFloat`

**String literal tests:**
- [ ] `kindOf("\"hello\"")` equals `Token.TkStr`
- [ ] `textOf("\"hello\"")` equals `"\"hello\""` (raw text includes quotes)
- [ ] `textOf("\"a\\nb\"")` equals `"\"a\\nb\""` (raw text preserves backslash)
- [ ] Lex `"\"${x}\""` → first token kind is `Token.TkTemplate`
- [ ] Lex `"\"${x}\""` → `Token.TkTemplate` parts contain `Token.TPInterp("x")`
- [ ] Lex `"\"hello ${name}\""` → parts are `[Token.TPLiteral("hello "), Token.TPInterp("name")]`
- [ ] Lex `"\"$name\""` → parts are `[Token.TPInterp("name")]` (short `$ident` form)
- [ ] Lex `"\"a ${1 + 2} b\""` → parts are `[Token.TPLiteral("a "), Token.TPInterp("1 + 2"), Token.TPLiteral(" b")]`
- [ ] `textOf("\"${x}\"")` equals `"\"${x}\""` (raw text of whole template token preserved)

**Char literal tests:**
- [ ] `kindOf("'a'")` equals `Token.TkChar`
- [ ] `textOf("'a'")` equals `"'a'"` (raw text includes quotes)
- [ ] `textOf("'\\n'")` equals `"'\\n'"` (raw escape preserved)

**Operator tests:**
- [ ] `kindOf("=>")` is `Token.TkOp`, text is `"=>"`
- [ ] `kindOf(":=")` is `Token.TkOp`, text is `":="`
- [ ] `kindOf("==")` is `Token.TkOp`, text is `"=="`
- [ ] `kindOf("!=")` is `Token.TkOp`, text is `"!="`
- [ ] `kindOf(">=")` is `Token.TkOp`, text is `">="`
- [ ] `kindOf("<=")` is `Token.TkOp`, text is `"<="`
- [ ] `kindOf("**")` is `Token.TkOp`, text is `"**"`
- [ ] `kindOf("<|")` is `Token.TkOp`, text is `"<|"`
- [ ] `kindOf("::")` is `Token.TkOp`, text is `"::"`
- [ ] `kindOf("|>")` is `Token.TkOp`, text is `"|>"`
- [ ] `kindOf("->")` is `Token.TkOp`, text is `"->"`
- [ ] `kindOf("...")` is `Token.TkOp`, text is `"..."`
- [ ] `kindOf("+")` is `Token.TkOp`; `kindOf("-")` is `Token.TkOp`; `kindOf("!")` is `Token.TkOp`

**Punctuation tests:**
- [ ] `:` vs `::` — lex `": ::"` kinds are `[Token.TkPunct, Token.TkWs, Token.TkOp, Token.TkEof]`, texts are `[":", " ", "::", ""]`
- [ ] `kindOf("(")` is `Token.TkPunct`, text is `"("`
- [ ] `kindOf(")")` is `Token.TkPunct`; `kindOf("{")` is `Token.TkPunct`; `kindOf("}")` is `Token.TkPunct`
- [ ] `kindOf("[")` is `Token.TkPunct`; `kindOf("]")` is `Token.TkPunct`
- [ ] `kindOf(",")` is `Token.TkPunct`; `kindOf(".")` is `Token.TkPunct`; `kindOf(";")` is `Token.TkPunct`

**Span tracking tests:**
- [ ] Lex `"42"`: first token `span.start == 0`, `span.end == 2`, `span.line == 1`, `span.col == 1`
- [ ] Lex `"\nx"`: identifier `x` has `span.line == 2`, `span.col == 1`
- [ ] Lex `"a\nb"`: second non-trivia token is `b` at `line == 2`

**EOF token test:**
- [ ] Last token of `lex("")` kind is `Token.TkEof`, text is `""`
- [ ] `lex("x")` length is 2 (one `Token.TkIdent` plus `Token.TkEof`)

- [ ] Run: `./kestrel test stdlib/kestrel/dev/parser/lexer.test.ks` → confirm compile error (`lexer.ks` not yet written — **red phase**)

### Phase F — Lexer — *TDD green* (`stdlib/kestrel/dev/parser/lexer.ks`)

- [ ] Create `stdlib/kestrel/dev/parser/lexer.ks` with imports:
  ```
  import * as Str from "kestrel:data/string"
  import * as Lst from "kestrel:data/list"
  import * as Arr from "kestrel:array"
  import * as Chr from "kestrel:data/char"
  import * as Token from "kestrel:dev/parser/token"
  ```

**LexState and primitive helpers:**
- [ ] Define `LexState` mutable record:
  ```
  type LexState = {
    src: String,
    len: Int,         // Str.length(src) — cached at creation
    mut pos: Int,     // current byte position (1 byte per BMP char in Kestrel/Java strings)
    mut line: Int,    // current line, 1-based
    mut col: Int      // current column, 1-based
  }
  ```
- [ ] Implement `fun lsEof(ls: LexState): Bool` — returns `ls.pos >= ls.len`
- [ ] Implement `fun lsCp(ls: LexState): Int` — returns `Str.codePointAt(ls.src, ls.pos)` or `-1` when `lsEof`
- [ ] Implement `fun lsCp1(ls: LexState): Int` — returns code point at `ls.pos + 1`, or `-1` if out of bounds
- [ ] Implement `fun lsTake(ls: LexState): Int` — read `lsCp`, increment `ls.line` and reset `ls.col := 1` on LF (code point 10), else increment `ls.col`; then `ls.pos := ls.pos + 1`; return the code point read
- [ ] Implement `fun lsMakeSpan(ls: LexState, start: Int, startLine: Int, startCol: Int): Token.Span` — `{ start = start, end = ls.pos, line = startLine, col = startCol }`
- [ ] Implement `fun lsMakeTok(ls: LexState, kind: Token.TokenKind, text: String, start: Int, sl: Int, sc: Int): Token.Token` — `{ kind = kind, text = text, span = lsMakeSpan(ls, start, sl, sc) }`

**Skip helpers:**
- [ ] Implement `fun lexSkipToEndOfLine(ls: LexState): Unit` — consume chars until LF (10) or EOF
- [ ] Implement `fun lexSkipBom(ls: LexState): Unit` — consume one char if `lsCp == 0xFEFF` (U+FEFF BOM)
- [ ] Implement `fun lexSkipShebang(ls: LexState): Unit` — call `lexSkipToEndOfLine` if first two code points are `#` (35) and `!` (33)

**Whitespace and comment tokenisers:**
- [ ] Implement `fun lexWsLoop(ls: LexState): Unit` — call `lsTake` while current code point is space (32), tab (9), CR (13), or LF (10)
- [ ] Implement `fun lexWs(ls: LexState, tokens: Array<Token.Token>): Unit` — record start/line/col; call `lexWsLoop`; push `Token.TkWs` token with `Str.slice(ls.src, start, ls.pos)`
- [ ] Implement `fun lexLineComment(ls: LexState, tokens: Array<Token.Token>): Unit` — record start; consume `//` with two `lsTake` calls; call `lexSkipToEndOfLine`; push `Token.TkLineComment` with raw slice
- [ ] Implement `fun lexBlockCommentBody(ls: LexState): Unit` — consume chars until `*/` (code points 42 then 47) or EOF; consume both chars of `*/`
- [ ] Implement `fun lexBlockComment(ls: LexState, tokens: Array<Token.Token>): Unit` — record start; consume `/*`; call `lexBlockCommentBody`; push `Token.TkBlockComment` with raw slice

**Identifier/keyword tokeniser:**
- [ ] Implement `fun isIdentStart(cp: Int): Bool` — true for A–Z (65–90), a–z (97–122), `_` (95)
- [ ] Implement `fun isIdentContinue(cp: Int): Bool` — true for `isIdentStart(cp)` or 0–9 (48–57)
- [ ] Define `val keywords: List<String>` — the 23 keywords: `["as","fun","type","val","var","mut","if","else","while","break","continue","match","try","catch","throw","async","await","export","import","from","exception","is","opaque","extern"]`
- [ ] Implement `fun isKeyword(s: String): Bool` — uses `Lst.any(keywords, (kw) => Str.equals(kw, s))`
- [ ] Implement `fun lexIdentLoop(ls: LexState): Unit` — call `lsTake` while `isIdentContinue(lsCp(ls))`
- [ ] Implement `fun lexIdent(ls: LexState, tokens: Array<Token.Token>): Unit` — record start; call `lexIdentLoop`; slice text; check: if `isKeyword` → `Token.TkKw`; else if first code point A–Z (65–90) → `Token.TkUpper`; else → `Token.TkIdent`; push token with raw text. Note: `True` and `False` start uppercase so become `Token.TkUpper`.

**Number tokeniser:**
- [ ] Implement `fun isDigit(cp: Int): Bool` — true for 48–57
- [ ] Implement `fun isHexDigit(cp: Int): Bool` — true for 0–9 (48–57), A–F (65–70), a–f (97–102)
- [ ] Implement `fun lexDecDigits(ls: LexState): Unit` — consume decimal digits and underscores (95) while digit or underscore
- [ ] Implement `fun lexHexDigits(ls: LexState): Unit` — consume hex digits and underscores
- [ ] Implement `fun lexBinDigits(ls: LexState): Unit` — consume `0`, `1`, and underscores
- [ ] Implement `fun lexOctDigits(ls: LexState): Unit` — consume 0–7 (48–55) and underscores
- [ ] Implement `fun lexExponent(ls: LexState): Unit` — check for `e`/`E` (101/69); if present, call `lsTake`; then optional `+`/`-`; then `lexDecDigits`
- [ ] Implement `fun lexNumberBody(ls: LexState): Bool` — dispatches on prefix:
  - `0x`/`0X` → `lsTake` twice, `lexHexDigits`, return `False`
  - `0b`/`0B` → `lsTake` twice, `lexBinDigits`, return `False`
  - `0o`/`0O` → `lsTake` twice, `lexOctDigits`, return `False`
  - `.` followed by digit → `lsTake`, `lexDecDigits`, `lexExponent`, return `True`
  - otherwise → `lexDecDigits`; if `.` then digit: `lsTake`, `lexDecDigits`, `lexExponent`, return `True`; else if `e`/`E`: `lexExponent`, return `True`; else return `False`
- [ ] Implement `fun lexNumber(ls: LexState, tokens: Array<Token.Token>): Unit` — record start; call `lexNumberBody` (returns isFloat); slice text; push `Token.TkFloat` or `Token.TkInt`

**String and char tokenisers:**
- [ ] Implement `fun hexToIntLoop(hex: String, i: Int, acc: Int): Int` — recursive; each hex char: subtract 48 for `0–9`, 55 for `A–F`, 87 for `a–f`; multiply acc by 16 and add digit
- [ ] Implement `fun hexToInt(hex: String): Int` — calls `hexToIntLoop(hex, 0, 0)`
- [ ] Implement `fun lexEscape(ls: LexState): String` — called after consuming `\`; dispatch on next code point:
  - 110 `n` → consume, return `"\n"`
  - 114 `r` → consume, return `"\r"`
  - 116 `t` → consume, return `"\t"`
  - 34 `"` → consume, return `"\""`
  - 92 `\` → consume, return `"\\"`
  - 117 `u` when next is `{` (123) → consume `u{`, call `lexHexDigits`, slice hex, consume `}`, return `Chr.charToString(Chr.fromCode(hexToInt(hex)))`
  - else → consume, return `""` (unknown escape — skip)
- [ ] Implement `fun lexInterpBody(ls: LexState, depth: Int): Unit` — scan tracking brace depth: `{` (123) → recurse with `depth + 1`; `}` (125) → if depth is 1 consume and return, else recurse with `depth - 1`; else consume and recurse
- [ ] Implement `fun lexStringBody(ls: LexState, parts: Array<Token.TemplatePart>, litAcc: String): Unit` — state machine loop:
  - EOF or LF → stop (unterminated string)
  - `"` (34) → `lsTake`, stop (closing quote)
  - `\` (92) → `lsTake`; call `lexEscape`; append decoded char to `litAcc`; recurse
  - `${` (36 then 123) → flush `litAcc` to `parts` as `Token.TPLiteral` if non-empty; consume `${`; record `interpStart = ls.pos`; call `lexInterpBody(ls, 1)`; slice from `interpStart` to `ls.pos - 1` (excludes closing `}`); push `Token.TPInterp(src)`; recurse with empty acc
  - `$ident` (36 then `isIdentStart`) → flush `litAcc`; consume `$`; record identStart; call `lexIdentLoop`; push `Token.TPInterp` of sliced ident; recurse with empty acc
  - else → consume char, append to `litAcc`; recurse
  - At end (either stop condition): if `litAcc` is non-empty and template parts exist, push final `Token.TPLiteral(litAcc)`
- [ ] Implement `fun lexString(ls: LexState, tokens: Array<Token.Token>): Unit` — record start; consume opening `"`; create `parts: Array<Token.TemplatePart> = Arr.new()`; call `lexStringBody(ls, parts, "")`; slice `rawText = Str.slice(ls.src, start, ls.pos)`; if `Arr.length(parts) == 0` push `Token.TkStr` else push `Token.TkTemplate(Arr.toList(parts))`; both with `rawText` as token text
- [ ] Implement `fun lexChar(ls: LexState, tokens: Array<Token.Token>): Unit` — record start; consume `'`; if `\` consume `\` then call `lexEscape` (decoded content for AST use, but raw text for token); else consume one char; consume closing `'`; push `Token.TkChar` with `rawText = Str.slice(ls.src, start, ls.pos)` (includes surrounding `'` delimiters)

**Operator/punctuation tokeniser:**
- [ ] Define `val multiOps: List<String>` — `["=>",":=","==","!=",">=","<=","**","<|","::","|>","->","..."]` (order matters — longer first)
- [ ] Implement `fun tryMatchMultiOp(ls: LexState, ops: List<String>): String` — for each op, compare `Str.slice(ls.src, ls.pos, ls.pos + Str.length(op))` with op using `Str.equals`; on match, advance pos by `Str.length(op)` (loop with `lsTake`), return the matched op; if list exhausted return `""`
- [ ] Implement `fun lexOpOrPunct(ls: LexState, tokens: Array<Token.Token>): Unit` — record start; call `tryMatchMultiOp`; if matched push `Token.TkOp` with matched text; else consume one char with `lsTake` and push: if char is in `"+-*/%|&<>=!"` → `Token.TkOp`, else → `Token.TkPunct`

**Main lex loop:**
- [ ] Implement `fun lexLoop(ls: LexState, tokens: Array<Token.Token>): Unit` — while not `lsEof`:
  - Code point 32/9/13/10 (whitespace) → `lexWs`
  - Code points 47+47 (`//`) → `lexLineComment`
  - Code points 47+42 (`/*`) → `lexBlockComment`
  - `isIdentStart(cp)` → `lexIdent`
  - `isDigit(cp)` → `lexNumber`
  - Code point 46 (`.`) and next is digit → `lexNumber` (float starting with `.`)
  - Code point 34 (`"`) → `lexString`
  - Code point 39 (`'`) → `lexChar`
  - else → `lexOpOrPunct`
  - recurse (tail-recursive loop)
- [ ] Implement `export fun lex(src: String): List<Token.Token>` — create `LexState { src, len=Str.length(src), mut pos=0, mut line=1, mut col=1 }`; create `tokens: Array<Token.Token> = Arr.new()`; call `lexSkipBom`, `lexSkipShebang`, `lexLoop`; push EOF token `{ kind=Token.TkEof, text="", span={start=ls.pos,...} }`; return `Arr.toList(tokens)`
- [ ] Verify file compiles: `./kestrel build stdlib/kestrel/dev/parser/lexer.ks`
- [ ] Run: `./kestrel test stdlib/kestrel/dev/parser/lexer.test.ks` → confirm all tests pass (**green**)

### Phase G — Parser unit tests — *TDD red* (`stdlib/kestrel/dev/parser/parser.test.ks`)

- [ ] Create `stdlib/kestrel/dev/parser/parser.test.ks` with imports: test harness; `lex` from `kestrel:dev/parser/lexer`; `parse`, `parseExpr`, `ParseError` from `kestrel:dev/parser/parser`; all AST types from `kestrel:dev/parser/ast`
- [ ] Add `export fun run(): Unit` entry point
- [ ] Implement helper `fun pl(src: String): Program` — calls `parse(lex(src))`, asserts `Ok`, returns program
- [ ] Implement helper `fun pe(src: String): Expr` — calls `parseExpr(lex(src))`, asserts `Ok`, returns expr
- [ ] Implement helper `fun firstImport(src: String): ImportDecl` — `pl(src).imports.head`
- [ ] Implement helper `fun firstDecl(src: String): TopDecl` — `pl(src).body.head`

**Import tests:**
- [ ] `import { foo } from "m"` → `IDNamed("m", [{external="foo",local="foo"}])`
- [ ] `import { foo as bar } from "m"` → `IDNamed("m", [{external="foo",local="bar"}])`
- [ ] `import { a, b } from "m"` → `IDNamed` with 2 ImportSpec entries
- [ ] `import * as M from "m"` → `IDNamespace("m","M")`
- [ ] `import "m"` → `IDSideEffect("m")`
- [ ] Two import statements → `imports` list length is 2

**Function declaration tests:**
- [ ] `fun f(x: Int): Int = x` → `TDFun` with `name="f"`, `exported=False`, `async_=False`, params length 1, param name `"x"`
- [ ] `async fun f(): Task<Int> = 1` → `TDFun { async_=True }`
- [ ] `export fun f(): Unit = ()` → `TDFun { exported=True }`
- [ ] `fun f<A>(x: A): A = x` → `TDFun { typeParams=["A"] }`
- [ ] `fun f(x: Int, y: Bool): String = "z"` → `TDFun` with 2 params

**Value and variable declaration tests:**
- [ ] `val x = 42` → `TDSVal("x", ELit("int","42"))` (no type annotation)
- [ ] `var x = 42` → `TDSVar("x", ELit("int","42"))`
- [ ] `export val x: Int = 42` → `TDVal("x", Some(ATPrim("Int")), ELit("int","42"))`
- [ ] `export var x: Int = 0` → `TDVar("x", Some(ATPrim("Int")), ELit("int","0"))`

**Type declaration tests:**
- [ ] `type Alias = Int` → `TDType` with `visibility="local"`, `body=TBAlias(ATPrim("Int"))`
- [ ] `type Color = Red | Green | Blue` → `TDType { body=TBAdt(...) }` with 3 constructors
- [ ] `type Box<A> = Box(A)` → `TDType { typeParams=["A"] }`
- [ ] `opaque type T = Int` → `TDType { visibility="opaque" }`
- [ ] `exception MyError` → `TDException { exported=False, name="MyError", fields=None }`
- [ ] `exception E { msg: String }` → `TDException { fields=Some([{name="msg",...}]) }`
- [ ] `export exception E` → `TDException { exported=True }`
- [ ] `export * from "m"` → `TDExport(EIStar("m"))`
- [ ] `export { foo, bar } from "m"` → `TDExport(EINamed("m", ...))`

**Literal expression tests:**
- [ ] `pe "42"` equals `ELit("int","42")`
- [ ] `pe "0xff"` equals `ELit("int","0xff")`
- [ ] `pe "3.14"` equals `ELit("float","3.14")`
- [ ] `pe "\"hello\""` equals `ELit("string","hello")` (decoded, without quotes)
- [ ] `pe "'a'"` equals `ELit("char","a")` (decoded)
- [ ] `pe "()"` equals `ELit("unit","()")`
- [ ] `pe "True"` equals `ELit("true","True")`
- [ ] `pe "False"` equals `ELit("false","False")`

**Identifier, field access, and call tests:**
- [ ] `pe "x"` equals `EIdent("x")`
- [ ] `pe "Foo"` equals `EIdent("Foo")`
- [ ] `pe "f()"` equals `ECall(EIdent("f"), [])`
- [ ] `pe "f(1)"` equals `ECall(EIdent("f"), [ELit("int","1")])`
- [ ] `pe "f(1, 2)"` — args list has length 2
- [ ] `pe "a.b"` equals `EField(EIdent("a"), "b")`
- [ ] `pe "a.b.c"` equals `EField(EField(EIdent("a"),"b"), "c")`
- [ ] `pe "a.0"` equals `EField(EIdent("a"), "0")` (tuple index)
- [ ] `pe "f(1)(2)"` — outer is `ECall` of `ECall` (chained call)

**Operator precedence tests:**
- [ ] `pe "1 + 2"` → `EBinary("+", ELit("int","1"), ELit("int","2"))`
- [ ] `pe "1 + 2 * 3"` → `EBinary("+", 1, EBinary("*", 2, 3))` — mul before add
- [ ] `pe "1 * 2 + 3"` → `EBinary("+", EBinary("*",1,2), 3)` — mul before add, left side
- [ ] `pe "2 ** 3 ** 4"` → `EBinary("**", 2, EBinary("**",3,4))` — right-associative
- [ ] `pe "1 - 2 - 3"` → `EBinary("-", EBinary("-",1,2), 3)` — left-associative
- [ ] `pe "1 == 2"` → `EBinary("==", ELit, ELit)`
- [ ] `pe "1 != 2"` → `EBinary("!=", ...)`
- [ ] `pe "a < b"` → `EBinary("<", EIdent"a", EIdent"b")`
- [ ] `pe "a >= b"` → `EBinary(">=", ...)`
- [ ] `pe "a | b"` → `EBinary("|", EIdent"a", EIdent"b")`
- [ ] `pe "a & b"` → `EBinary("&", EIdent"a", EIdent"b")`
- [ ] `pe "x |> f"` → `EPipe("|>", EIdent"x", EIdent"f")`
- [ ] `pe "f <| x"` → `EPipe("<|", EIdent"f", EIdent"x")`
- [ ] `pe "x :: xs"` → `ECons(EIdent"x", EIdent"xs")`
- [ ] `pe "1 :: 2 :: []"` → `ECons(ELit, ECons(ELit, EList([])))` — right-associative
- [ ] `pe "-1"` → `EUnary("-", ELit("int","1"))`
- [ ] `pe "!x"` → `EUnary("!", EIdent"x")`
- [ ] `pe "x is Int"` → `EIs(EIdent"x", ATPrim("Int"))`

**Control flow tests:**
- [ ] `pe "if (x) y else z"` → `EIf(EIdent"x", EIdent"y", Some(EIdent"z"))`
- [ ] `pe "if (x) y"` → `EIf(EIdent"x", EIdent"y", None)`
- [ ] `pe "while (x) { y }"` → `EWhile(EIdent"x", Block{stmts=[], result=EIdent"y"})`
- [ ] `pe "await x"` → `EAwait(EIdent"x")`
- [ ] `pe "throw e"` → `EThrow(EIdent"e")`
- [ ] `pe "try { x } catch { E => 0 }"` → `ETry(Block{...}, None, [Case_{...}])`

**Lambda tests:**
- [ ] `pe "(x: Int) => x"` → `ELambda(False, [], [{name="x",type_=Some(ATPrim"Int")}], EIdent"x")`
- [ ] `pe "(x) => x"` → `ELambda(False, [], [{name="x",type_=None}], EIdent"x")`
- [ ] `pe "(x, y) => x"` → `ELambda` with 2 params
- [ ] `pe "async (x) => x"` → `ELambda(True, [], [{name="x",...}], EIdent"x")`
- [ ] Backtracking test — `pe "(x)"` should be `EIdent "x"` (grouping, not lambda — no `=>`)

**Match tests:**
- [ ] `pe "match (x) { 1 => 2 }"` → `EMatch(EIdent"x", [Case_{pattern=PLit("int","1"), body=ELit("int","2")}])`
- [ ] Match with multiple cases — two `=>` clauses → cases list length 2
- [ ] Match `_` arm → `Case_{ pattern=PWild }`
- [ ] Match variable arm `x` → `Case_{ pattern=PVar("x") }`
- [ ] Match constructor `Some(v)` → `Case_{ pattern=PCon("Some",[...]) }`

**Collection and record tests:**
- [ ] `pe "[1, 2, 3]"` → `EList([LElem(ELit), LElem(ELit), LElem(ELit)])`
- [ ] `pe "[...xs, 1]"` → `EList([LSpread(EIdent"xs"), LElem(ELit)])`
- [ ] `pe "[]"` → `EList([])`
- [ ] `pe "{x = 1, y = 2}"` → `ERecord(None, [field"x", field"y"])`
- [ ] `pe "{mut x = 1}"` → `ERecord(None, [{name="x",mut_=True,...}])`
- [ ] `pe "{...r, x = 1}"` → `ERecord(Some(EIdent"r"), [...])`
- [ ] `pe "{}"` → `ERecord(None, [])`
- [ ] `pe "(1, 2)"` → `ETuple([ELit("int","1"), ELit("int","2")])`
- [ ] `pe "(1, 2, 3)"` → `ETuple` with 3 elements
- [ ] `pe "(x)"` → `EIdent "x"` (grouping, not tuple)

**Block tests:**
- [ ] `pe "{x}"` → `EBlock({stmts=[], result=EIdent"x"})`
- [ ] `pe "{val x = 1; x}"` → `EBlock({stmts=[SVal("x",None,ELit("int","1"))], result=EIdent"x"})`
- [ ] `pe "{var x = 1; x := 2; x}"` → `EBlock` with `SVar`, `SAssign`, and `result=EIdent"x"`
- [ ] `pe "{1; 2}"` → `EBlock({stmts=[SExpr(ELit("int","1"))], result=ELit("int","2")})`
- [ ] `pe "{break}"` → `EBlock({stmts=[SBreak], result=ENever})`

**Template/string tests:**
- [ ] `pe "\"${x}\""` → `ETemplate([TmplExpr(EIdent"x")])`
- [ ] `pe "\"hello ${name}\""` → `ETemplate([TmplLit("hello "), TmplExpr(EIdent"name")])`
- [ ] `pe "\"$name\""` → `ETemplate([TmplExpr(EIdent"name")])`
- [ ] `pe "\"a ${1 + 2} b\""` → `ETemplate([TmplLit"a ", TmplExpr(EBinary("+",...)), TmplLit" b"])`

**Type annotation tests (parsed inside declarations):**
- [ ] `fun f(x: Int): Bool = True` — param type is `ATPrim("Int")`, return type is `ATPrim("Bool")`
- [ ] `fun f(x: List<Int>): Unit = ()` — param type is `ATApp("List", [ATPrim("Int")])`
- [ ] `fun f(x: Int -> Bool): Unit = ()` — param type is `ATArrow([ATPrim("Int")], ATPrim("Bool"))`
- [ ] `fun f(x: {a: Int}): Unit = ()` — param type is `ATRecord([{name="a",...}])`
- [ ] `fun f(x: A | B): Unit = ()` — param type is `ATUnion(ATIdent"A", ATIdent"B")`
- [ ] `fun f(x: A * B): Unit = ()` — param type is `ATTuple([ATIdent"A", ATIdent"B"])`

**Pattern tests (inside match expressions):**
- [ ] Wildcard `_` → `PWild`
- [ ] Variable `x` → `PVar("x")`
- [ ] Int literal `42` → `PLit("int","42")`
- [ ] Float literal `3.14` → `PLit("float","3.14")`
- [ ] String literal `"s"` → `PLit("string","s")`
- [ ] `True` → `PCon("True",[])`; `False` → `PCon("False",[])`
- [ ] Constructor no-arg `None` → `PCon("None",[])`
- [ ] Constructor positional `Some(x)` → `PCon("Some",[{name="__field_0",pattern=Some(PVar"x")}])`
- [ ] Constructor record `Con{x=p}` → `PCon("Con",[{name="x",pattern=Some(PVar"p")}])`
- [ ] Constructor record shorthand `Con{x}` → `PCon("Con",[{name="x",pattern=Some(PVar"x")}])`
- [ ] List pattern `[a, b]` → `PList([PVar"a",PVar"b"],None)`
- [ ] List with rest `[a, ...xs]` → `PList([PVar"a"],Some("xs"))`
- [ ] Empty list `[]` → `PList([],None)`
- [ ] Cons `h :: t` → `PCons(PVar"h",PVar"t")`
- [ ] Tuple `(a,b)` → `PTuple([PVar"a",PVar"b"])`
- [ ] Unit `()` → `PLit("unit","()")`

**Final verification:**
- [ ] Run: `./kestrel test stdlib/kestrel/dev/parser/parser.test.ks` → confirm compile error (`parser.ks` not yet written — **red phase**)

### Phase H — Parser — *TDD green* (`stdlib/kestrel/dev/parser/parser.ks`)

- [ ] Create `stdlib/kestrel/dev/parser/parser.ks` with all necessary imports (token types, all AST types, `lex` from lexer)

**ParseError and ParseState:**
- [ ] Define `export type ParseError = ParseError(String, Int, Int, Int)` — (message, offset, line, col)
- [ ] Define `ParseState` mutable record:
  ```
  type ParseState = {
    tokens: Array<Token.Token>,   // trivia-filtered (whitespace and comments removed)
    count: Int,             // Arr.length(tokens), cached
    mut pos: Int,           // current position in filtered array
    mut errors: List<ParseError>
  }
  ```

**ParseState construction and navigation helpers:**
- [ ] Implement `fun buildFiltered(toks: List<Token.Token>, arr: Array<Token.Token>): Unit` — append each non-trivia token to `arr` (match on kind, skip `Token.TkWs`, `Token.TkLineComment`, `Token.TkBlockComment`)
- [ ] Implement `fun makePs(allTokens: List<Token.Token>): ParseState` — create array, call `buildFiltered`, return `{ tokens=arr, count=Arr.length(arr), mut pos=0, mut errors=[] }`
- [ ] Implement `fun psCurrent(ps: ParseState): Token.Token` — `Arr.get(ps.tokens, min(ps.pos, ps.count - 1))`
- [ ] Implement `fun psPeek(ps: ParseState, offset: Int): Token.Token` — `Arr.get(ps.tokens, min(ps.pos + offset, ps.count - 1))`
- [ ] Implement `fun psAdvance(ps: ParseState): Token.Token` — return `psCurrent`; if not EOF increment `ps.pos`
- [ ] Implement `fun psAtKw(ps: ParseState, kw: String): Bool`
- [ ] Implement `fun psAtOp(ps: ParseState, op: String): Bool`
- [ ] Implement `fun psAtPunct(ps: ParseState, ch: String): Bool`
- [ ] Implement `fun psAtIdent(ps: ParseState): Bool`
- [ ] Implement `fun psAtUpper(ps: ParseState): Bool`
- [ ] Implement `fun psAtEof(ps: ParseState): Bool`
- [ ] Implement `fun psError(ps: ParseState, msg: String): ParseError` — construct `ParseError(msg, span.start, span.line, span.col)` from current token's span; prepend to `ps.errors`; return the error
- [ ] Implement `fun psExpectIdent(ps: ParseState): Result<String, ParseError>` — if `Token.TkIdent` advance and return `Ok(text)`, else `Err(psError(...))`
- [ ] Implement `fun psExpectUpper(ps: ParseState): Result<String, ParseError>`
- [ ] Implement `fun psExpectKw(ps: ParseState, kw: String): Result<Token.Token, ParseError>`
- [ ] Implement `fun psExpectOp(ps: ParseState, op: String): Result<Token.Token, ParseError>`
- [ ] Implement `fun psExpectPunct(ps: ParseState, ch: String): Result<Token.Token, ParseError>`
- [ ] Implement `fun psExpectStr(ps: ParseState): Result<String, ParseError>` — if `Token.TkStr` advance and return `Ok(rawText)`, else error
- [ ] Implement `fun isExprStart(ps: ParseState): Bool` — returns True if current token can start an expression: `Token.TkInt`, `Token.TkFloat`, `Token.TkStr`, `Token.TkTemplate`, `Token.TkChar`, `Token.TkIdent`, `Token.TkUpper`, or kw/punct `( [ { if while match try throw -` `+ ! await async`

**Entry points:**
- [ ] Implement `export fun parse(tokens: List<Token.Token>): Result<Program, ParseError>` — `makePs`, call `parseProgram`, return `Err(head errors)` if errors non-empty, else `Ok(prog)`
- [ ] Implement `export fun parseExpr(tokens: List<Token.Token>): Result<Expr, ParseError>` — `makePs`, call `parsePipeExpr(ps, "expr")`, return as above

**Program-level parsing:**
- [ ] Implement `fun parseProgram(ps: ParseState): Program` — call `parseImports`, then `parseTopBody`, return `{ imports, body }`
- [ ] Implement `fun parseImports(ps: ParseState): List<ImportDecl>` — loop while `psAtKw(ps, "import")`: advance past `import`, call `parseImport1`, collect results
- [ ] Implement `fun parseImport1(ps: ParseState): ImportDecl` — three forms:
  - `* as Name from "spec"` → advance `*`, `as`, ident (alias), `from`, str → `IDNamespace(spec, alias)`
  - `"spec"` (Token.TkStr immediately) → advance → `IDSideEffect(spec)`
  - `{ specs } from "spec"` → advance `{`, call `parseImportSpecList`, `from`, str → `IDNamed(spec, specs)`
- [ ] Implement `fun parseImportSpecList(ps: ParseState): List<ImportSpec>` — comma-separated `name` or `name as alias`; consume `}`
- [ ] Implement `fun parseTopBody(ps: ParseState): List<TopDecl>` — loop until EOF; dispatch:
  - `export` → `parseExport`
  - `async`/`fun`/`extern`/`type`/`opaque`/`exception` → `parseTopDecl(ps, False)`
  - `val`/`var` or `isExprStart` → `parseTopStmt`
  - else → advance and produce `TDSExpr(ELit("unit","()"))` (error recovery skip)
- [ ] Implement `fun parseExport(ps: ParseState): TopDecl` — consume `export`, then:
  - `*` op → consume, `from`, str → `TDExport(EIStar(spec))`
  - `{` → consume, `parseImportSpecList`, `from`, str → `TDExport(EINamed(spec, specs))`
  - `exception` → `parseExceptionDecl(ps, True)`
  - `async`/`fun`/`extern`/`type`/`opaque`/`val`/`var` → `parseTopDecl(ps, True)`
- [ ] Implement `fun parseTopDecl(ps: ParseState, exported: Bool): TopDecl` — dispatch on keyword:
  - `async`/`fun` → `parseFunDecl(ps, exported)` → `TDFun`
  - `extern fun` → `parseExternFun(ps, exported)` → `TDExternFun`
  - `extern type` → `parseExternType(ps)` → `TDExternType`
  - `extern import` → `parseExternImport(ps)` → `TDExternImport`
  - `type`/`opaque` → `parseTypeDecl(ps, exported)` → `TDType`
  - `exception` → `parseExceptionDecl(ps, exported)` → `TDException`
  - `val` → consume, `psExpectIdent`, optional `: T`, `=`, `parseTopExpr` → `TDVal`
  - `var` → same → `TDVar`
- [ ] Implement `fun parseTopStmt(ps: ParseState): TopDecl` — if `val`: consume, ident, `=`, expr → `TDSVal` (NO type); if `var`: same → `TDSVar`; else parse expr; if `:=` follows → consume, parse rhs → `TDSAssign`; else → `TDSExpr`

**Declaration helpers:**
- [ ] Implement `fun parseTypeParams(ps: ParseState): List<String>` — if `<` (op), consume, comma-separated Token.TkIdent names, consume `>`; else return `[]`
- [ ] Implement `fun parseSingleParam(ps: ParseState): Param` — `psExpectIdent`; if `:` (punct) follows, consume and parse type → `{ name, type_=Some(t) }`; else `{ name, type_=None }`
- [ ] Implement `fun parseParamList(ps: ParseState): List<Param>` — consume `(`; comma-separated `parseSingleParam`; consume `)`
- [ ] Implement `fun parseFunDecl(ps: ParseState, exported: Bool): TopDecl` — consume optional `async` (record flag), consume `fun`, `psExpectIdent` (name), `parseTypeParams`, `parseParamList`, consume `:`, `parseTypeExpr` (retType), consume `=`, `parsePipeExpr` (body) → `TDFun(FunDecl{exported, async_, name, typeParams, params, retType, body})`
- [ ] Implement `fun parseSingleCtor(ps: ParseState): CtorDef` — `psExpectUpper` (name); if `(` optionally parse comma-separated types until `)` → `{ name, params=types }`; else `{ name, params=[] }`
- [ ] Implement `fun parseCtorList(ps: ParseState): List<CtorDef>` — parse `parseSingleCtor`; while `|` (op) follows consume and parse another; return list
- [ ] Implement `fun parseTypeDecl(ps: ParseState, exported: Bool): TopDecl` — consume `opaque`? then `type`; name; `parseTypeParams`; consume `=`; decide body: peek — if `Token.TkUpper` and next peek is `(` or `|` → `TBAdt(parseCtorList(ps))`; else `TBAlias(parseTypeExpr(ps))` → `TDType(TypeDecl{visibility, name, typeParams, body})`
- [ ] Implement `fun parseExceptionDecl(ps: ParseState, exported: Bool): TopDecl` — consume `exception`; name; if `{` follows parse comma-separated `mut? name: T` fields until `}`; return `TDException(ExceptionDecl{exported, name, fields})`
- [ ] Implement `fun parseExternFun(ps: ParseState, exported: Bool): TopDecl` — consume `extern fun`; name; typeParams; paramList; `:` retType; `=` `jvm("desc")` → `TDExternFun`
- [ ] Implement `fun parseExternType(ps: ParseState): TopDecl` — handle `extern opaque export type` / `extern opaque type` / `extern type`; name; typeParams; `=` `jvm("class")` → `TDExternType`
- [ ] Implement `fun parseExternImport(ps: ParseState): TopDecl` — consume `extern import`; target str; `as`; alias ident; optional `{ name(params): retType, ... }` overrides → `TDExternImport`

**Type expression parsing:**
- [ ] Implement `fun parseTypeExpr(ps: ParseState): AstType` — entry point; call `parseOrType`
- [ ] Implement `fun parseOrType(ps: ParseState): AstType` — parse `parseAndType`; while `|` (op, but NOT `||`) left-associate into `ATUnion`
- [ ] Implement `fun parseAndType(ps: ParseState): AstType` — parse `parseArrowType`; while `&` left-associate into `ATInter`
- [ ] Implement `fun parseArrowType(ps: ParseState): AstType` — parse `parseAppType`; if `->` (op) right-associate into `ATArrow([lhs], rhs)` (if lhs was a tuple product, use its list as param types)
- [ ] Implement `fun parseAppType(ps: ParseState): AstType` — parse `parseAtomType`; if `<` try consuming generic args list → `ATApp(name, args)`; while `*` (op) left-associate into `ATTuple`
- [ ] Implement `fun parseAtomType(ps: ParseState): AstType` — dispatch: `(` `)` → `ATPrim "Unit"`; `(T)` → `T` (grouping); `{ }` → `ATRecord([])`; `{ ...r }` → `ATRowVar(r)`; `{ fields }` → `ATRecord(parseRecordTypeFields)`; `Token.TkIdent`/`Token.TkUpper` → `ATPrim` or `ATIdent`; `Token.TkIdent` `.` `Token.TkUpper` (qualified) → `ATQualified`
- [ ] Implement `fun parseRecordTypeFields(ps: ParseState): List<TypeField>` — comma-separated `mut? name: T` fields until `}`; consume `}`

**Expression parsing — precedence levels:**
- [ ] Implement `fun parsePipeExpr(ps: ParseState, ctx: String): Expr` — call `parseConsExpr`; while `|>` or `<|` (op) left-associate into `EPipe(op, l, r)`
- [ ] Implement `fun parseConsExpr(ps: ParseState, ctx: String): Expr` — call `parseOrExpr`; if `::` right-associate into `ECons(lhs, parseConsExpr(ps, ctx))`
- [ ] Implement `fun parseOrExpr(ps: ParseState, ctx: String): Expr` — call `parseAndExpr`; while `|` (single `|`, NOT `|>`) left-associate into `EBinary("|", l, r)`
- [ ] Implement `fun parseAndExpr(ps: ParseState, ctx: String): Expr` — call `parseIsExpr`; while `&` left-associate into `EBinary("&", l, r)`
- [ ] Implement `fun parseIsExpr(ps: ParseState, ctx: String): Expr` — call `parseRelExpr`; if `is` kw consume and parse type → `EIs(expr, t)` (no chaining)
- [ ] Implement `fun parseRelExpr(ps: ParseState, ctx: String): Expr` — call `parseAddExpr`; while op is `==`,`!=`,`<`,`>`,`<=`,`>=` left-associate → `EBinary`
- [ ] Implement `fun parseAddExpr(ps: ParseState, ctx: String): Expr` — call `parseMulExpr`; while `+` or `-` left-associate → `EBinary`
- [ ] Implement `fun parseMulExpr(ps: ParseState, ctx: String): Expr` — call `parsePowExpr`; while `*`,`/`,`%` left-associate → `EBinary`
- [ ] Implement `fun parsePowExpr(ps: ParseState, ctx: String): Expr` — call `parseUnary`; if `**` right-associate `EBinary("**", lhs, parsePowExpr(ps, ctx))`
- [ ] Implement `fun parseUnary(ps: ParseState, ctx: String): Expr` — if op is `-`,`+`,`!` consume and wrap `EUnary(op, parseUnary)`; if `async` and next is `(` → `tryParseParenLambda(ps, True)`; if `<` try `isGenericLambdaHead` → `parseGenericLambda`; else delegate to `parsePrimary`
- [ ] Implement `fun exprMayBeCallCallee(e: Expr): Bool` — returns `True` for `EIdent`, `EField`, `ECall`, `ELambda`, `EAwait(inner)` where `exprMayBeCallCallee(inner)` is also True; returns `False` for all literal/collection/block forms
- [ ] Implement `fun parsePrimary(ps: ParseState, ctx: String): Expr` — check for `await` prefix (consume if present); call `parseAtom`; postfix loop:
  - `(` and `exprMayBeCallCallee(expr)` → consume `(`; `parseArgList`; consume `)` → `ECall(expr, args)`; loop
  - `.` punct → consume; if `Token.TkIdent` consume field name → `EField(expr, name)`; if `Token.TkInt` consume index → `EField(expr, text)`; loop
  - `Token.TkFloat` where text starts with `.` (tuple index `.0`) → extract decimal part; `EField(expr, idx)`; loop
  - wrap in `EAwait` if prefix was set; return
- [ ] Implement `fun parseArgList(ps: ParseState): List<Expr>` — comma-separated `parsePipeExpr` until `)`; do NOT consume `)`
- [ ] Implement `fun parseAtom(ps: ParseState, ctx: String): Expr` — dispatch on current token:
  - `Token.TkInt` → `ELit("int", text)`, advance
  - `Token.TkFloat` → `ELit("float", text)`, advance
  - `Token.TkStr` → `ELit("string", decodeString(rawText))`, advance
  - `Token.TkChar` → `ELit("char", decodeChar(rawText))`, advance
  - `Token.TkTemplate(parts)` → call `parseTemplateExpr(ps, parts)`, advance
  - `Token.TkUpper "True"` → `ELit("true","True")`, advance
  - `Token.TkUpper "False"` → `ELit("false","False")`, advance
  - `Token.TkUpper` (other) → `EIdent(text)`, advance
  - `Token.TkIdent` → `EIdent(text)`, advance
  - `(` → try `tryParseParenLambda(ps, False)`; if `None`: if `)` → `ELit("unit","()")`, else parse expr; if `,` → collect more → `ETuple`
  - `[` → `parseListLiteral`
  - `{` → `parseRecordOrBlock`
  - `if` kw → `parseIfExpr`
  - `while` kw → `parseWhileExpr`
  - `match` kw → `parseMatchExpr`
  - `try` kw → `parseTryExpr`
  - `throw` kw → consume, parse expr, return `EThrow`
  - else → `psError`, return `ELit("unit","()")`

**String/char decoding:**
- [ ] Implement `fun decodeString(raw: String): String` — strip surrounding `"` delimiters (`Str.slice(raw, 1, Str.length(raw) - 1)`); process escape sequences: scan char by char; on `\` decode escape; accumulate to result string
- [ ] Implement `fun decodeChar(raw: String): String` — strip `'` delimiters; decode single escape or return the single character

**Template parsing:**
- [ ] Implement `fun parseTemplateExpr(ps: ParseState, parts: List<Token.TemplatePart>): Expr` — map over parts: `Token.TPLiteral(s)` → `TmplLit(s)`; `Token.TPInterp(src)` → call `lex(src)` then `parseExpr` from this file, extract expr → `TmplExpr(expr)`; return `ETemplate(mappedParts)`

**Lambda backtracking:**
- [ ] Implement `fun tryParseParamListOnly(ps: ParseState): Option<List<Param>>` — speculative parse: save `ps.pos` and `ps.errors`; attempt to parse comma-separated params where each is `Token.TkIdent` optionally followed by `: type`; if any element fails or unexpected token found, restore `ps.pos := savedPos` and `ps.errors := savedErrors`, return `None`; on success return `Some(params)`
- [ ] Implement `fun tryParseParenLambda(ps: ParseState, async_: Bool): Option<Expr>` — save `ps.pos` and `ps.errors`; advance past `(`; if immediately `)` restore and return `None`; call `tryParseParamListOnly`; on `None` restore and return `None`; if not `)` restore and return `None`; advance past `)`; if not `=>` restore and return `None`; advance past `=>`; parse body with `parsePipeExpr`; return `Some(ELambda(async_, [], params, body))`
- [ ] Implement `fun isGenericLambdaHead(ps: ParseState): Bool` — save pos; try consuming `<`, comma-separated Token.TkIdent, `>`; check for `(`; restore pos; return whether all steps matched
- [ ] Implement `fun parseGenericLambda(ps: ParseState, async_: Bool): Expr` — consume `<`, typeParams, `>`, `(`, paramList, `)`, `=>`, body; return `ELambda(async_, typeParams, params, body)`

**Block parsing:**
- [ ] Implement `fun parseRecordOrBlock(ps: ParseState, ctx: String): Expr` — look at token after `{` (using `psPeek(ps, 1)`):
  - `}` → empty record `ERecord(None, [])`
  - kw `val`/`var`/`fun`/`async` → `EBlock(parseBlock(ps, ctx))`
  - op `...` → `ERecord(parseRecordExpr(ps))`... actually: parse as record
  - kw `mut` → record
  - `Token.TkIdent` and psPeek+2 is op `=` → record
  - else → block
- [ ] Implement `fun parseRecordExpr(ps: ParseState): Expr` — consume `{`; optional `...expr ,`; comma-separated `mut? name = expr` fields; consume `}`; return `ERecord(spread, fields)`
- [ ] Implement `fun parseBlock(ps: ParseState, ctx: String): Block` — consume `{`; accumulate stmts:
  - `val` → name, optional `: T`, `=`, expr → `SVal`
  - `var` → name, optional `: T`, `=`, expr → `SVar`
  - `fun`/`async fun` → name, typeParams, paramList, `:` retType, `=`, expr → `SFun`
  - `break` → consume → `SBreak`
  - `continue` → consume → `SContinue`
  - else: parse expr; if `:=` → consume, parse rhs → `SAssign`; else → `SExpr`
  - after each stmt: consume optional `;`
  - last stmt that is `SExpr(e)` becomes `result = e`; remove from stmts
  - if no trailing `SExpr`: `result = ELit("unit","()")`; `break`/`continue` as last stmt → `result = ENever`
  - consume `}`

**Control flow parsing:**
- [ ] Implement `fun parseIfExpr(ps: ParseState, ctx: String): Expr` — consume `if`, `(`, condition, `)`; parse then-expr; if `else` kw follows consume and parse else-expr; return `EIf(cond, then, maybeElse)`
- [ ] Implement `fun parseWhileExpr(ps: ParseState): Expr` — consume `while`, `(`, condition, `)`; parse block; return `EWhile(cond, block)`
- [ ] Implement `fun parseMatchExpr(ps: ParseState, ctx: String): Expr` — consume `match`, `(`, scrutinee, `)`; `{`; comma-separated `pattern => expr` cases; consume `}`; return `EMatch(scrutinee, cases)`
- [ ] Implement `fun parseTryExpr(ps: ParseState, ctx: String): Expr` — consume `try`; parse block body; consume `catch`; optional `(` `var`? ident `)` for catch variable; `{`; comma-separated cases; consume `}`; return `ETry(body, optVar, cases)`
- [ ] Implement `fun parseListLiteral(ps: ParseState, ctx: String): Expr` — consume `[`; comma-separated: `...expr` → `LSpread`; else → `LElem`; consume `]`; return `EList`

**Pattern parsing:**
- [ ] Implement `fun parsePattern(ps: ParseState): Pattern` — call `parsePatternPrimary`; if `::` (op) follows consume and recurse → `PCons(lhs, parsePattern(ps))`
- [ ] Implement `fun parseConPatternFields(ps: ParseState): List<ConField>` — consume `(`; comma-separated patterns, naming them `"__field_0"`, `"__field_1"`, …; consume `)`; return list
- [ ] Implement `fun parseConRecordFields(ps: ParseState): List<ConField>` — consume `{`; comma-separated: `name = pattern` → `{name, pattern=Some(p)}`; bare `name` → `{name, pattern=Some(PVar(name))}` (shorthand binding); consume `}`; return list
- [ ] Implement `fun parseListPattern(ps: ParseState): Pattern` — consume `[`; comma-separated patterns; optional `...rest` at end (Token.TkIdent after `...` op); consume `]`; return `PList(patterns, optRest)`
- [ ] Implement `fun parsePatternPrimary(ps: ParseState): Pattern` — dispatch:
  - `Token.TkIdent "_"` → `PWild`, advance
  - `Token.TkIdent` (other) → `PVar(name)`, advance
  - `Token.TkUpper "True"` → `PCon("True",[])`, advance
  - `Token.TkUpper "False"` → `PCon("False",[])`, advance
  - `Token.TkUpper` → advance; if `(` → `PCon(name, parseConPatternFields)`; if `{` → `PCon(name, parseConRecordFields)`; else `PCon(name, [])`
  - `[` → `parseListPattern`
  - `(` `)` → `PLit("unit","()")`, advance twice
  - `(` → consume; parse first pattern; if `,` → collect more → `PTuple`; else that pattern (drop parens)
  - `Token.TkInt` → `PLit("int", text)`, advance
  - `Token.TkFloat` → `PLit("float", text)`, advance
  - `Token.TkStr` → `PLit("string", decodeString(text))`, advance
  - `Token.TkChar` → `PLit("char", decodeChar(text))`, advance
  - else → `psError`, return `PWild`

- [ ] Verify file compiles: `./kestrel build stdlib/kestrel/dev/parser/parser.ks`
- [ ] Run: `./kestrel test stdlib/kestrel/dev/parser/parser.test.ks` → confirm all parser tests pass (**green**)
- [ ] Run all stdlib tests: `./kestrel test --summary`
- [ ] Run compiler tests: `cd compiler && npm test`

---

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel unit harness | `stdlib/kestrel/dev/parser/token.test.ks` | Token type construction and `Token.isTrivia`/`Token.spanZero` |
| Kestrel unit harness | `stdlib/kestrel/dev/parser/ast.test.ks` | AST type construction and matching for all variants |
| Kestrel unit harness | `stdlib/kestrel/dev/parser/lexer.test.ks` | Round-trip, all token kinds, spans, operator longest-match |
| Kestrel unit harness | `stdlib/kestrel/dev/parser/parser.test.ks` | Full parse coverage: imports, decls, exprs, patterns, types |

---

## Documentation and specs to update

- [ ] `docs/specs/02-stdlib.md` — add `kestrel:dev/parser/token`, `kestrel:dev/parser/ast`, `kestrel:dev/parser/lexer`, and `kestrel:dev/parser/parser` module entries documenting their public APIs.

---

## Build notes

- 2026-04-06: Started implementation. TDD structure: test file written and red-confirmed before each impl phase. Story restructured so test phases (A/C/E/G) precede their matching impl phases (B/D/F/H).
- 2026-04-06: Phases A+B complete. token.ks and token.test.ks created; 13/13 tests green.
- 2026-04-06: **Compiler bug discovered and fixed (Phase C/D).** When a `RecordExpr` (which has `spread?: Expr` in its TypeScript interface) appeared as an element of a list literal `[{...}]`, the JVM codegen incorrectly classified it as a *list spread element* due to checking `'spread' in el` (which is `true` for any object with the key present, even if `undefined`). The fix: changed the check in `compiler/src/jvm-codegen/codegen.ts` (ListExpr handler) from `'spread' in el` to `(el as { spread?: unknown }).spread === true`, so only genuine spread-list elements (`{ spread: true, expr: Expr }`) take the spread code path. All 420 compiler tests still pass after the fix.
- 2026-04-06: Phases C+D complete. ast.ks and ast.test.ks created; 51/51 tests green.
