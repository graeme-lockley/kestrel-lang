# 01 – Core Language Specification

Version: 1.0 (Compiler + Zig VM Target)

---

## 1. Philosophy and Design Goals

Kestrel is a statically typed, scripting, and server-oriented programming language with:

- Hindley–Milner type inference
- Structural records with row polymorphism
- Algebraic data types
- Union (`|`) and intersection (`&`) types
- Pattern-based exception handling
- Async/await (`Task<T>`)
- Pipeline operator (`|>`)
- No member-call syntax (`x.f(y)` is invalid)
- Bytecode compilation targeting a Zig-based VM

Kestrel prioritizes:

1. Predictable semantics
2. Mechanical simplicity
3. Strong static typing
4. Clean separation between compiler (TypeScript) and VM (Zig)
5. Deterministic module resolution

---

## 2. Lexical Structure

Tokens are the maximal sequence of characters that form a keyword, identifier, literal, or operator/delimiter. **Longest match** applies: the lexer takes the longest possible token at each step (e.g. `>=` is one token if supported; otherwise `>` and `=`). **Keywords are reserved**: they are not valid as identifiers. Whitespace and comments are not retained except to separate tokens.

### 2.1 Whitespace and Comments

- **Whitespace:** Space (U+0020), tab (U+0009), carriage return (U+000D), line feed (U+000A). Allowed between any two tokens; required only when omitting it would merge two tokens (e.g. `if` and `(`).
- **Line comment:** `//` to end of line. The rest of the line is ignored.
- **Block comment:** `/*` … `*/`. Block comments do not nest. A block comment is closed by the first `*/`.

### 2.2 Shebang (script entry point)

If the **first line** of the source file (after an optional UTF-8 BOM) begins with the two characters `#!`, that entire line is a **shebang line**. The shebang is not parsed as tokens: the lexer skips from `#!` to the end of the line (including the newline), then continues tokenizing from the next line. This allows a file to be used as an executable script (e.g. `#!/usr/bin/env kestrel`).

- Only the **first** line of the file may be a shebang. A line starting with `#!` elsewhere is not special (and `#` is not a comment in Kestrel; it would be a lexical error unless the language later adds `#`-based syntax).
- If the first line does not start with `#!`, the file is parsed from the first character (after optional BOM) with no shebang.

### 2.3 Identifiers

```
LOWER_IDENT   ::= [a-z_][A-Za-z0-9_]*
UPPER_IDENT   ::= [A-Z][A-Za-z0-9_]*
IDENT         ::= LOWER_IDENT | UPPER_IDENT
```

Identifiers must not be keywords (§2.4). **Naming rules** (enforced statically):

- **Uppercase (must use `UPPER_IDENT`):** type names, constructor names (ADT variants), exception names, module namespace aliases (e.g. `import * as M`).
- **Lowercase (must use `LOWER_IDENT`):** all other declaration names (function names, `val`/`var` bindings, parameter names), and all field names (record fields, exception payload fields, pattern fields).

So: types, constructors, and exceptions start with an uppercase letter; functions, bindings, parameters, and fields start with a lowercase letter. In contexts where a name may refer to either (e.g. in expressions, or in import/export lists), either form is allowed and the grammar uses `IDENT`.

### 2.4 Keywords and Reserved Words

The following are **reserved** and may not be used as identifiers:

```
fun type val var mut if else match try catch throw async await
export import from exception is opaque True False
```

`True` and `False` are boolean literals; the rest are syntactic keywords.

### 2.5 Operators and Delimiters

Single- and multi-character tokens the lexer must recognize (longest match):

- **Assignment:** `:=`. The left-hand side may be an identifier bound by a named import of an **export var** (07); semantics are as in 07 §9 (assignment to imported var).
- **Comparison:** `==`, `!=`, `>=`, `<=`, `<`, `>`
- **Arithmetic / logic:** `+`, `-`, `*`, `/`, `%`, `**`, `|`, `&`, `|>`, `<|`, `::`
- **Case / lambda arrow:** `=>` — single token (used in match cases and lambdas); must not be lexed as `=` followed by `>`.
- **Delimiters:** `(`, `)`, `{`, `}`, `[`, `]`, `,`, `:`, `.`, `;`

`::` is the list **cons** operator (literal expression and pattern). The lexer must use **longest match** so that `>=`, `<=`, `!=`, `**`, `<|`, `::`, and `=>` are single tokens. The character `=` appears only as part of `==`, `:=`, or `=>`.

### 2.6 Integer Literals

```
INTEGER       ::= DECIMAL | HEX | BINARY | OCTAL
DECIMAL       ::= [0-9] ([0-9]_*)* [0-9] | [0-9]
HEX           ::= "0" [xX] [0-9a-fA-F] ([0-9a-fA-F]_*)* [0-9a-fA-F]?
BINARY        ::= "0" [bB] [01] ([01]_*)* [01]?
OCTAL         ::= "0" [oO] [0-7] ([0-7]_*)* [0-7]?
```

Underscores may appear only **between** digits; leading/trailing underscores are not allowed. Value must fit in a **61-bit signed integer** at runtime (overflow throws). The 61-bit width is required by the runtime tagged-value layout: a 64-bit word uses 3 bits for the tag, leaving 61 bits for the integer payload so that Int can be stored inline without boxing; see [05-runtime-model.md](05-runtime-model.md).

### 2.7 Float Literals

64-bit IEEE 754 floating-point. Literal forms:

- **Decimal:** `1.0`, `0.5`, `.5`, `5.`
- **Exponent:** `1e10`, `2.5e-3`, `1E+0`
- **Underscores:** Allowed between digits (e.g. `1_000.5`)

```
FLOAT         ::= DECIMAL_FLOAT | EXPONENT_FLOAT
DECIMAL_FLOAT ::= [0-9] { [0-9] } "." { [0-9] }
                | "." [0-9] { [0-9] }
                | [0-9] { [0-9] } "."
EXPONENT_FLOAT::= (DECIMAL_FLOAT | [0-9] { [0-9] }) [eE] ["+" | "-"] [0-9] { [0-9] }
```

Lexer must not treat `1.` or `.5` as integer plus dot; the longest valid float token wins. Runtime type is **Float** (64-bit). Unlike Int, Float cannot be stored inline in the 64-bit tagged word and is **boxed** (heap-allocated) at runtime; see [05-runtime-model.md](05-runtime-model.md).

### 2.8 String Literals (Template Strings)

Strings are delimited by `"` (U+0022). All strings support interpolation; there are no raw string literals.

**Inside a string:**

- **Escape sequences:** `\\` (backslash), `\"` (quote), `\n` (line feed), `\r` (carriage return), `\t` (tab), `\u{` HEX_DIGITS `}` (Unicode code point, one to six hex digits).
- **Interpolation:** `$` IDENT (single identifier) or `${` Expr `}` (expression). The closing `}` for `${` is determined by **brace balancing**: count `{` and `}`; the first `}` that brings the nesting count back to zero (matching the `${`) closes the interpolation. The expression inside `${ ... }` may contain nested `{` and `}` (e.g. record literals); unescaped `"` is not allowed inside the expression. Interpolation uses implicit `toString()` on the value. The content within `${ }` must be parsed as an expression; the lexer and parser must work together (e.g. lexer yields a string token with interpolation markers, or the parser handles quoted regions and `${ ... }` in a coordinated pass).

String token grammar (conceptual):

```
STRING        ::= '"' (INTERP | ESCAPE | CHAR)* '"'
INTERP        ::= '$' IDENT | '${' Expr '}'
ESCAPE        ::= '\\' | '\"' | '\n' | '\r' | '\t' | '\u{' HEX+ '}'
CHAR          ::= any character except '"' '\' '$' or newline
```

### 2.9 Character and Rune Literals

Delimited by `'` (U+0027).

- **Escapes:** Same as in strings: `\\`, `\'`, `\n`, `\r`, `\t`, `\u{` HEX+ `}`.
- **Content:** Exactly one code point (one character or one `\u{...}` rune). Multi-byte UTF-8 sequences in single quotes denote one character.

**Char and Rune:** The type names `Char` and `Rune` denote the **same** type (a single Unicode code point). Both are valid in type annotations and have the same runtime representation; see [05-runtime-model.md](05-runtime-model.md) and [06-typesystem.md](06-typesystem.md).

```
CHAR_LITERAL  ::= '\'' (ESCAPE | [^\'\\]) '\''
```

### 2.10 Boolean and Unit Literals

- **Boolean:** `True` | `False` (reserved words).
- **Unit:** `()` — the two tokens `(` and `)` with nothing between them (no space required), used where the grammar expects a unit value.

---

## 3. Grammar (EBNF)

Notation: **`[ X ]`** = optional (zero or one occurrence of X). **`{ X }`** = zero or more occurrences of X. One or more is written as **`X { X }`**.

The grammar is intended to be unambiguous for a production parser. Precedence and associativity of expressions are given in §3.2.

### 3.1 Programs and Declarations

```
Program        ::= [ Shebang ] { ImportDecl } { ModuleDecl | TopLevelStmt }

Shebang        ::= "#!" { any character except newline } (NL | end of file)

ModuleDecl     ::= ExportDecl | TopLevelDecl

TopLevelStmt   ::= Stmt [ ";" | NL ]

ImportDecl     ::= "import" ImportClause "from" STRING
                 | "import" "*" "as" UPPER_IDENT "from" STRING
                 | "import" STRING

ImportClause   ::= "{" ImportSpec { "," ImportSpec } "}"
ImportSpec     ::= IDENT [ "as" IDENT ]

ExportDecl     ::= "export" (TopLevelDecl
                     | "*" "from" STRING
                     | "{" ExportSpec { "," ExportSpec } "}" "from" STRING)
                 | "opaque" TypeDecl
ExportSpec     ::= IDENT [ "as" IDENT ]

TopLevelDecl   ::= FunDecl | TypeDecl | ExceptionDecl

FunDecl        ::= [ "async" ] "fun" LOWER_IDENT [ "<" TypeParamList ">" ] "(" ParamList ")" ":" Type "=" Expr
ParamList      ::= [ Param { "," Param } ]
Param          ::= LOWER_IDENT [ ":" Type ]

TypeDecl       ::= [ "opaque" ] "type" UPPER_IDENT [ "<" TypeParamList ">" ] "=" TypeBody
TypeBody       ::= Type                                         /* type alias */
                 | Constructor { "|" Constructor }              /* ADT definition */
Constructor    ::= UPPER_IDENT [ "(" TypeList ")" ]             /* 0 or more positional payload types */
TypeParamList  ::= UPPER_IDENT { "," UPPER_IDENT }
ExceptionDecl  ::= "export" "exception" UPPER_IDENT [ "{" TypeFieldList "}" ]
```

**Program order:** **Imports** must appear first (after an optional shebang). All `ImportDecl` are parsed before any declaration or statement. Thereafter **declarations** (exports, functions, types, exceptions) and **top-level statements** may be interleaved in any order. Declarations are visible for the whole module (hoisted). Top-level statements are executed **serially** in source order when the module is run—e.g. as the body of a script. A file that begins with a shebang is typically executed as the entry point. An empty program (shebang only, or no imports, declarations, or statements) is valid and denotes a module that does nothing when run.

**Type visibility:** Type declarations have three visibility levels:

- **Local** (no qualifier): `type Foo = ...` — the type and its constructors are visible only within the declaring module.
- **Opaque** (`opaque type`): `opaque type Foo = ...` — the type **name** is exported (importers can use `Foo` in type signatures and hold values), but the **structure** is hidden. Importers cannot construct values, destructure, or pattern-match on the type. The declaring module has full access.
- **Exported** (`export type`): `export type Foo = ...` — both the type name and constructors/structure are fully exported. Importers can construct, destructure, and pattern-match.

**ADT definitions:** A type body is an ADT definition when the right-hand side of `=` is one or more UPPER_IDENT constructors separated by `|`. Each constructor may take zero or more positional payload types in parentheses. Constructors are functions: a nullary constructor `Red` has type `Color`; a constructor `Some(T)` has type `(T) -> Option<T>`; a constructor `Node(Tree, Tree)` has type `(Tree, Tree) -> Tree`. Constructor application uses the standard call syntax: `Some(10)`, `Node(left, right)`. Pattern matching uses the same syntax: `Some(x) => ...`, `Node(l, r) => ...`. If named fields are desired, use a record type as the payload: `MkPerson({ name: String, age: Int })`.

**Type alias vs ADT disambiguation:** If the right-hand side of `=` starts with an UPPER_IDENT followed by `|` or `(`, or is a `|`-separated list of UPPER_IDENTs (possibly with parenthesized payloads), it is parsed as an ADT definition. Otherwise it is a type alias. Examples: `type Color = Red | Green | Blue` (ADT), `type Pair = { x: Int, y: Int }` (type alias), `type Id = Int` (type alias).

**Top-level recursion (types):** Every top-level type name is in scope in the body of every top-level type declaration. Thus a type may reference itself (self-recursion, e.g. `type Tree = Leaf(Int) | Node(Tree, Tree)`) or reference any other top-level type (mutual recursion, e.g. `type Expr = ... | IfExpr(BoolExpr, Expr, Expr)` where `BoolExpr` is another type in the same module). Declaration order does not affect name resolution for type references.

**Top-level recursion:** Every top-level function name is in scope in the body of every top-level function. Thus a function may call itself (self-recursion) or call any other top-level function (mutual recursion); declaration order does not affect name resolution for function calls.

### 3.2 Expressions (Precedence and Associativity)

Expression precedence from **lowest** to **highest** (same row = same precedence):

| Level | Operators | Associativity |
|-------|-----------|---------------|
| 1     | `\|>` `<\|` | Left        |
| 2     | `::`      | Right         |
| 3     | `\|`      | Left          |
| 4     | `&`       | Left          |
| 5     | `==` `!=` `<` `>` `>=` `<=` | Left |
| 6     | `+` `-`   | Left          |
| 7     | `*` `/` `%` | Left        |
| 8     | `**`      | Right         |

All binary operators are left-associative unless stated otherwise. `**` (exponentiation) and `::` (list cons) are **right-associative**. The grammar reflects this by splitting expression levels (PipeExpr through PowExpr). **Unary operators** are not specified in this version; add a UnaryExpr level if introduced.

```
Expr           ::= IfExpr
                 | MatchExpr
                 | TryExpr
                 | Lambda
                 | PipeExpr

PipeExpr       ::= ConsExpr { ("|>" | "<|") ConsExpr }
ConsExpr       ::= OrExpr [ "::" ConsExpr ]
OrExpr         ::= AndExpr { "|" AndExpr }
AndExpr        ::= RelExpr { "&" RelExpr }
RelExpr        ::= AddExpr { ("==" | "!=" | "<" | ">" | ">=" | "<=") AddExpr }
AddExpr        ::= MulExpr { ("+" | "-") MulExpr }
MulExpr        ::= PowExpr { ("*" | "/" | "%") PowExpr }
PowExpr        ::= Primary [ "**" PowExpr ]

IfExpr         ::= "if" "(" Expr ")" Expr "else" Expr
MatchExpr      ::= "match" "(" Expr ")" "{" Case { Case } "}"   /* match must be exhaustive (see type system) */
Case           ::= Pattern "=>" Expr
Pattern        ::= ConsPattern | NonConsPattern
ConsPattern    ::= NonConsPattern "::" Pattern                                     /* list cons; right-associative */
NonConsPattern ::= "_"
                 | UPPER_IDENT [ "(" Pattern { "," Pattern } ")" ]                   /* constructor with positional args */
                 | ListPattern
                 | LOWER_IDENT                                                       /* variable binding */
                 | INTEGER
                 | STRING
                 | "True" | "False"
                 | "(" Pattern { "," Pattern } ")"                     /* tuple or grouping; 1+ elements, comma disambiguates */
ListPattern    ::= "[" [ ListPatInner ] "]"                                         /* list; rest only as last */
ListPatInner   ::= "..." LOWER_IDENT                                                /* bind whole list to rest */
                 | Pattern { "," Pattern } [ "," "..." LOWER_IDENT ]                 /* elements, optional rest last */

TryExpr        ::= "try" Block "catch" "(" LOWER_IDENT ")" "{" Case { Case } "}"
Lambda         ::= [ "<" IDENT { "," IDENT } ">" ] "(" ParamList ")" "=>" Expr

Primary        ::= [ "await" ] Atom { Suffix }
Atom           ::= Literal
                 | ListLiteral
                 | IDENT
                 | "(" Expr { "," Expr } ")"                            /* constant tuple or grouping; comma disambiguates */
                 | RecordLit
                 | "throw" Expr
ListLiteral    ::= "[" [ ListElem { "," ListElem } ] "]"                            /* [a, b, ...c, d] */
ListElem       ::= Expr | "..." Expr
Suffix         ::= "(" ExprList ")"   /* application */
                 | "." LOWER_IDENT   /* field access */
ExprList       ::= [ Expr { "," Expr } ]

RecordLit      ::= "{" [ (RecordSpread | RecordField) { "," (RecordSpread | RecordField) } ] "}"
RecordSpread   ::= "..." Expr
RecordField    ::= LOWER_IDENT "=" Expr
```

Record spread `{ ...expr, field = value }` is implemented by compiling to the SPREAD instruction (04 §1.8) with an extended shape; the VM pops the base record and additional field values and produces a new record.

Application and field access are **postfix** on an atom: parse one Atom, then zero or more Suffix (call or field). So `f(x).y` is Atom `f`, Suffix `(x)`, Suffix `.y`. **Await:** A primary expression may be prefixed with `await` (e.g. `await f()`); valid only in async context (see §5).

**Pipeline semantics:** `e1 |> e2` passes the left-hand value as the **first** argument to the right-hand call: `x |> f` is equivalent to `f(x)`; `x |> f(y)` is equivalent to `f(x, y)`. Similarly, `<|` passes the right-hand value as the last argument: `f <| x` is `f(x)`; `f(y) <| x` is `f(y, x)`. The right-hand side must be an expression that denotes a function call (application).

### 3.3 Blocks and Statements

```
Block          ::= "{" { BlockItem } Expr "}"
BlockItem      ::= Stmt [ ";" | NL ]
Stmt           ::= "val" LOWER_IDENT "=" Expr
                 | "var" LOWER_IDENT "=" Expr
                 | "fun" LOWER_IDENT [ "<" TypeParamList ">" ] "(" ParamList ")" ":" Type "=" Expr
                 | Expr ":=" Expr
```

A block-local **`fun`** declaration is **desugared** to `val name = (params) => body`; see §3.8 for closures. When the nested `fun` has a **full type signature** (all parameter types and return type), the name is in scope for the body so the function may call itself recursively. Every such block-local `fun` is also in scope in the body of every other such `fun` in the same block, so they may call each other (mutual recursion); declaration order does not affect name resolution. The trailing **Expr** in a block is the block’s value; it is required. Each statement is followed by a **statement terminator**: `;`, newline, or `}` (when the next token starts the block’s final expression). `NL` denotes a newline token (or newline codepoint) used as terminator. See §3.5.

### 3.4 Literals (Expression-Level)

```
Literal        ::= INTEGER | FLOAT | STRING | CHAR_LITERAL | "True" | "False" | Unit
Unit           ::= "(" ")"
```

**Tuples:** Syntactically, grouping and constant tuples share the same parenthesized comma-separated form `"(" Expr { "," Expr } ")"` (and the same for patterns). A single expression or pattern `(e)` or `(p)` is treated as **grouping** (same as `e` or `p`). Two or more `(e1, e2, …)` form a **constant tuple** with product type (e.g. `(Int, String)` has type `Int * String`). Tuple patterns match the same shape: `(p1, p2)` or `(p1, p2, p3, …)`. The parser disambiguates by the presence of a comma after the first element.

**No member calls:** The grammar does not allow `e.M(args)` (method call). Function and constructor calls use `e(args)`; field read uses the postfix `e.fieldName` (Suffix `"." LOWER_IDENT`).

### 3.5 Optional Semicolons and Line Boundaries

- **Statement/expression boundaries:** A newline (or `;`) may be used to separate statements and to separate the last statement from the trailing block expression. Concretely: after `Expr` in a Stmt, and after the last Stmt before the block Expr, a newline or `;` is allowed. A newline is **not** treated as a terminator when it would break a valid expression: e.g. there must be no newline between `Expr` and `=>` in a lambda or case, or between a function and `(` in an application. Implementations may treat newline as terminator only after a complete Stmt (e.g. after `val x = e`, `var x = e`, or `e := e`) or allow semicolons everywhere as explicit terminators.
- **Conformance:** Implementations must accept any program in which every statement is terminated by an explicit `;` (and the grammar is otherwise satisfied). When newline is used as terminator, the exact rule is implementation-defined as long as the same set of programs is accepted as with the grammar that allows optional `;` or newline after each Stmt.

### 3.6 Type Grammar (Parsing Only)

Types are parsed as follows; typing rules are in [06-typesystem.md](06-typesystem.md).

```
Type           ::= OrType
OrType         ::= AndType { "|" AndType }
AndType        ::= ArrowType { "&" ArrowType }
ArrowType      ::= AppType [ "->" Type ]
AppType        ::= AtomType { "*" AtomType }
AtomType       ::= "Int" | "Float" | "Bool" | "String" | "Unit" | "Char" | "Rune"
                 | "Array" "<" Type ">"
                 | "Task" "<" Type ">"
                 | "Option" "<" Type ">"
                 | "Result" "<" Type "," Type ">"
                 | "List" "<" Type ">"
                 | "(" Type ")"
                 | "(" TypeList ")" "->" Type
                 | "{" TypeFieldList "}"
                 | "{" "..." IDENT "}"
                 | UPPER_IDENT

TypeList       ::= [ Type { "," Type } ]
TypeFieldList  ::= [ TypeField { "," TypeField } ]
TypeField      ::= LOWER_IDENT ":" [ "mut" ] Type
```

**Mutable record fields:** A field may be marked **`mut`** in the type (e.g. `age: mut Int`). For any variable (val or var) of that record type, a mutable field may be updated by assignment: `r.age := 42`. Fields without `mut` are immutable.

Precedence: `&` tighter than `|`; `->` groups to the right; `*` (product) tighter than `->`. Record and function types use parentheses when nested (e.g. `(Int -> Bool) -> String`). **Built-in generics:** `Array<T>` and `Task<T>` are runtime built-ins. **Library types:** `Option<T>`, `Result<T,E>`, and `List<T>` are provided by the standard library; see [02-stdlib.md](02-stdlib.md). List has special syntax: `[a, b, ...c]` and `::` (expression and pattern).

### 3.7 Parser and Lexer Disambiguation

- **Shebang:** Before tokenizing, if the source starts with `#!` (after optional BOM), skip the entire first line (including the newline); tokenization begins on the second line. Do not treat `#` as a token elsewhere.
- **Longest match:** The lexer always takes the longest possible token (e.g. `identifier` not `ident` + `ifier`; `0xFF` as one integer). **Arrow:** `=>` is a single token (lambda and case arrow); it must be matched as one token, not `=` followed by `>`.
- **Keywords:** Keyword tokens are matched before generic IDENT (e.g. `if` is keyword, not identifier). Match fixed keyword strings as tokens first.
- **Statement termination:** After a Stmt, the parser must see one of `;`, newline, or `}`. The lexer may emit a **newline token** (e.g. on `\n` or `\r\n`) so the parser can treat it as a terminator; or the parser may use a different rule (e.g. require `;` and ignore newlines, or use the next token’s line number). The choice is implementation-defined; the grammar assumes some notion of statement end.
- **Ambiguous prefixes:** `( ParamList )` appears in Lambda and in parenthesized Expr. Use context: after `=>` expect Expr; after `(` at expression position expect Expr; after `fun` IDENT `(` expect ParamList. Type versus expression after `(`: if the first token is IDENT followed by `:` or `,` or `)`, parse as ParamList; otherwise parse as Expr.
- **Record vs block:** `{` can start Block or RecordLit. After `{`, if the next token is `}` (empty record literal) or a label (IDENT `=` or `...`), parse as RecordLit; if the next token is `val`, `var`, `fun`, or an expression start, parse as Block. (Expression start: Literal, IDENT, `(`, `[`, `throw`, etc.)
- **Parenthesized type:** `"(" Type ")"` vs `"(" TypeList ")" "->" Type`: after parsing `"("` and one or more types, if the next token is `"->"`, treat as function type and parse the rest of the arrow type; otherwise treat as a single grouped type `"(" Type ")"`.
- **Paren vs tuple:** After `"("` at expression or pattern position, parse one Expr or Pattern. If the next token is `","`, parse as tuple (two or more elements) and require the matching closing `")"`; otherwise parse as grouping (single `Expr` or `Pattern` and `")"`).
- **List literal vs pattern:** `"["` at expression position (in Atom) starts `ListLiteral`. `"["` at pattern position starts `ListPattern`. In a list pattern, at most one `"..." LOWER_IDENT` is allowed and only as the **last** component (e.g. `[a, b, ...rest]` or `[...rest]`); the grammar enforces this via `ListPatInner`.

### 3.8 Closures and Capture

Lambdas `(params) => body` and nested functions (block-local `fun`, desugared to `val name = (params) => body`) may **capture** variables from the enclosing block or function scope (lexical/static scope). The **capture set** of a lambda is the set of free variables: identifiers used in `body` that are not in the lambda's own `params` (and not introduced by an inner lambda's params). Enclosing scope includes: earlier `val`/`var`/`fun` bindings in the same block, and (when the block is inside a function) that function's parameters and outer blocks.

The implementation uses **closure conversion**: each capturing lambda is compiled as a **lifted** function that takes an **environment** (a record of captured values) as its first parameter; the environment is built at the point where the lambda is created and stored in a **closure** value. Non-capturing lambdas are represented as a function reference only (no environment). Details are in [04-bytecode-isa.md](04-bytecode-isa.md) §5.1 and [05-runtime-model.md](05-runtime-model.md).

**Capture semantics:** `val` bindings are captured **by value** (the value at creation time is stored in the environment). `var` bindings are captured **by reference** via a mutable cell (e.g. a one-field record) so that assignments to the variable inside the closure are visible outside and vice versa; both the closure and the enclosing scope operate on the same storage.

**Return type:** The declared return type of a block-local `fun name(...): ReturnType = body` is **checked**: the body's inferred type must unify with `ReturnType`; if not, the implementation reports a type error.

**Known limitations (current implementation):**

1. **Recursive nested function in test-runner context:** A nested `fun` with a full type signature may call itself by name and works correctly in normal execution (inline blocks, if branches, returned closures, top-level fun bodies). When the same code is run inside the test runner’s closure context, the VM may hit a bus error; this path is under investigation. For automated tests that exercise recursive nested functions, run the code via `./kestrel run` or a top-level entry point until the VM issue is fixed.

---

## 4. Exceptions

### Declare

```
export exception DivideByZero
export exception FileNotFound { name: String }
```

### Throw

```
throw FileNotFound { name = path }
```

### Catch

```
try { ... }
catch (e) {
  FileNotFound { name } => ...
  _ => ...
}
```

The catch variable is **optional**. You may write `catch { ... }` when the exception value is only used for pattern matching and not referred to by name:

```
try { risky() }
catch {
  DivideByZero => 0
  ArithmeticOverflow => 0
  _ => 1
}
```

If no catch case matches the thrown value (e.g. no catch-all `_` or variable and no matching constructor pattern), the exception is **rethrown**: control leaves the catch block and the same exception propagates to the next enclosing handler (or terminates the program if none). Stack trace is accessed via the `Stack` module; see [02-stdlib.md](02-stdlib.md).

---

## 5. Async and Task Model

`async` functions return `Task<T>`.

```
async fun f(): Task<Int> = { ... }
val x = await f()
```

**Await expression:** The grammar allows `await` as an optional prefix on a primary expression: `await` *expr* (e.g. `await f()`). `await` is only valid in an **async context** (inside an `async fun`); use outside async is a semantic (type/context) error.

VM behaviour (see [04-bytecode-isa.md](04-bytecode-isa.md)):

- Instruction `AWAIT`: if task complete → push result; else suspend frame.

---

## 6. Related Specifications

- [06-typesystem.md](06-typesystem.md) – Types, row polymorphism, inference
- [07-modules.md](07-modules.md) – Imports and exports
- [02-stdlib.md](02-stdlib.md) – Standard library (e.g. `Stack`)
