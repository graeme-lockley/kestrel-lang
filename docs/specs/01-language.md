# 01 – Core Language Specification

Version: 1.0 (Compiler + JVM Target)

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
- Bytecode compilation targeting the JVM (Java Virtual Machine)

Kestrel prioritizes:

1. Predictable semantics
2. Mechanical simplicity
3. Strong static typing
4. Clean separation between compiler (TypeScript) and runtime (Java)
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
fun type val var mut if else while break continue match try catch throw async await
export import from exception is opaque True False
```

`True` and `False` are boolean literals; the rest are syntactic keywords.

### 2.5 Operators and Delimiters

Single- and multi-character tokens the lexer must recognize (longest match):

- **Assignment:** `:=`. The left-hand side may be an identifier bound by a named import of an **export var** (07); semantics are as in 07 §9 (assignment to imported var).
- **Comparison:** `==`, `!=`, `>=`, `<=`, `<`, `>` — see §3.2.1 for `==` / `!=` semantics
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

Underscores may appear only **between** digits; leading/trailing underscores are not allowed. Value must fit in a **61-bit signed integer** at runtime (overflow throws). The JVM runtime preserves this 61-bit Int bound for language-level compatibility.

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

Lexer must not treat `1.` or `.5` as integer plus dot; the longest valid float token wins. Runtime type is **Float** (64-bit).

### 2.8 String Literals (Template Strings)

Strings are delimited by `"` (U+0022). String content is **UTF-8**. All strings support interpolation; there are no raw string literals.

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

**Char and Rune:** The type names `Char` and `Rune` denote the **same** type (a single Unicode code point). Both are valid in type annotations and have the same runtime representation; see [06-typesystem.md](06-typesystem.md).

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

TopLevelDecl   ::= FunDecl | TypeDecl | ExceptionDecl | ValDecl | VarDecl

FunDecl        ::= [ "async" ] "fun" LOWER_IDENT [ "<" TypeParamList ">" ] "(" ParamList ")" ":" Type "=" Expr
ParamList      ::= [ Param { "," Param } ]
Param          ::= LOWER_IDENT [ ":" Type ]

TypeDecl       ::= [ "opaque" ] "type" UPPER_IDENT [ "<" TypeParamList ">" ] "=" TypeBody
TypeBody       ::= Type                                         /* type alias */
                 | Constructor { "|" Constructor }              /* ADT definition */
Constructor    ::= UPPER_IDENT [ "(" TypeList ")" ]             /* 0 or more positional payload types */
TypeParamList  ::= UPPER_IDENT { "," UPPER_IDENT }
ExceptionDecl  ::= "export" "exception" UPPER_IDENT [ "{" TypeFieldList "}" ]
ValDecl        ::= "val" LOWER_IDENT [ ":" Type ] "=" Expr
VarDecl        ::= "var" LOWER_IDENT [ ":" Type ] "=" Expr
```

**Program order:** **Imports** must appear first (after an optional shebang). All `ImportDecl` are parsed before any declaration or statement. Thereafter **declarations** (exports, functions, types, exceptions) and **top-level statements** may be interleaved in any order. Declarations are visible for the whole module (hoisted). Top-level statements are executed **serially** in source order when the module is run—e.g. as the body of a script. A file that begins with a shebang is typically executed as the entry point. An empty program (shebang only, or no imports, declarations, or statements) is valid and denotes a module that does nothing when run.

**Type visibility:** Type declarations have three visibility levels:

- **Local** (no qualifier): `type Foo = ...` — the type and its constructors are visible only within the declaring module.
- **Opaque** (`opaque type`): `opaque type Foo = ...` — the type **name** is exported (importers can use `Foo` in type signatures and hold values), but the **structure** is hidden. Importers cannot construct values, destructure, or pattern-match on the type. The declaring module has full access.
- **Exported** (`export type`): `export type Foo = ...` — both the type name and constructors/structure are fully exported. Importers can construct, destructure, and pattern-match.

**ADT definitions:** A type body is an ADT definition when the right-hand side of `=` is one or more UPPER_IDENT constructors separated by `|`. Each constructor may take zero or more positional payload types in parentheses. Constructors are functions: a nullary constructor `Red` has type `Color`; a constructor `Some(T)` has type `(T) -> Option<T>`; a constructor `Node(Tree, Tree)` has type `(Tree, Tree) -> Tree`. Constructor application uses the standard call syntax: `Some(10)`, `Node(left, right)`. With **`import * as M from "…"`** (07 §2.3), **qualified** constructor use is **`M.C`** (nullary, a value of the ADT type) and **`M.C(e1,…,en)`** (n-ary), when `C` is an exported constructor of an exported non-opaque ADT in that module (06 §5.1). Pattern matching uses the same syntax: `Some(x) => ...`, `Node(l, r) => ...`. If named fields are desired, use a record type as the payload: `MkPerson({ name: String, age: Int })`.

**Type alias vs ADT disambiguation:** If the right-hand side of `=` starts with an UPPER_IDENT followed by `|` or `(`, or is a `|`-separated list of UPPER_IDENTs (possibly with parenthesized payloads), it is parsed as an ADT definition. Otherwise it is a type alias. Examples: `type Color = Red | Green | Blue` (ADT), `type Pair = { x: Int, y: Int }` (type alias), `type Id = Int` (type alias).

**Top-level recursion (types):** Every top-level type name is in scope in the body of every top-level type declaration. Thus a type may reference itself (self-recursion, e.g. `type Tree = Leaf(Int) | Node(Tree, Tree)`) or reference any other top-level type (mutual recursion, e.g. `type Expr = ... | IfExpr(BoolExpr, Expr, Expr)` where `BoolExpr` is another type in the same module). Declaration order does not affect name resolution for type references.

**Top-level recursion:** Every top-level function name is in scope in the body of every top-level function. Thus a function may call itself (self-recursion) or call any other top-level function (mutual recursion); declaration order does not affect name resolution for function calls.

**Tail-position calls to top-level functions:** The reference implementation may compile a direct call from **tail position** to the enclosing **top-level** function (**self** tail recursion) or to **another top-level function in the same module** (**mutual** tail recursion) without growing the call stack, when the call matches the compiler’s lowering rules (04 §1.5, 05 §1.2). Tail positions are the same as the value returned from the function: `if`/`match` branch bodies, block result, etc. Short-circuit subexpressions are not tail positions for this purpose.

### 3.2 Expressions (Precedence and Associativity)

Expression precedence from **lowest** to **highest** (same row = same precedence):

| Level | Operators | Associativity |
|-------|-----------|---------------|
| 1     | `\|>` `<\|` | Left        |
| 2     | `::`      | Right         |
| 3     | `\|`      | Left          |
| 4     | `&`       | Left          |
| 5     | `is`      | —             |
| 6     | `==` `!=` `<` `>` `>=` `<=` | Left |
| 7     | `+` `-`   | Left          |
| 8     | `*` `/` `%` | Left        |
| 9     | `**`      | Right         |

**`is` (level 5)** is the **type test** operator `e is T` (see below): it is **not** an associative chain of the same kind as `+` or `&`. The grammar allows at most one `is Type` suffix per `IsExpr` (after relational operands). **`T`** is the **type** nonterminal (§3.6). Because `is` binds **tighter** than expression-level `|` (level 3) and **looser** than `&` (level 4), a form like `f() is Int | String` parses as `f() is (Int | String)` — the RHS is a **union type**, not `(f() is Int) | …`.

All binary operators are left-associative unless stated otherwise. `**` (exponentiation) and `::` (list cons) are **right-associative**. The grammar reflects this by splitting expression levels (PipeExpr through PowExpr). **Unary operators** are not specified in this version; add a UnaryExpr level if introduced.

#### 3.2.1 Equality and inequality (`==`, `!=`)

Both operators require operands of the **same** type (after inference); the type checker unifies the left and right operand types for the whole relational chain.

**`==` — semantic (deep) equality**

`==` compares values by meaning, not by object identity (where a heap representation exists). The JVM runtime implements it with structural deep-equality via `KRuntime.equals` (there is no separate user-callable `__equals`; use `==` / `!=`).

| Kind | `==` is true when |
|------|-------------------|
| `Int`, `Bool` | Same numeric / boolean value |
| `Float` | Same IEEE-754 value; **NaN** is never equal to itself (and never equal to any other value), consistent with IEEE |
| `Char` / `Rune` | Same code point |
| `Unit` | Both are `()` |
| `String` | Same sequence of Unicode code points (UTF-8 content); same as `kestrel:string` `equals` |
| `List` | Same length and each element is `==` (recursive) |
| Tuple | Same arity and each component is `==` (tuples use the same structural representation as records with positional fields) |
| Record | Same field count, same field names in the same order, and each field value is `==` (recursive) |
| `Option` | Both `None`, or both `Some` with equal payloads |
| `Result` | Both `Ok` with equal payloads, or both `Err` with equal payloads |
| User-defined ADT | Same constructor tag and each payload field is `==` (recursive) |

If the dynamic types of the operands differ (e.g. after an unsound cast), the implementation may treat `==` as false or report an error; well-typed programs use `==` only on a single unified type.

**`!=`**

`a != b` is **always** the Boolean negation of `a == b` for the same operands: it must yield `True` iff `a == b` yields `False`, and vice versa. In particular, for floats, two NaNs compare unequal under `==`, so `!=` is true for `NaN` vs `NaN`.

**Ordering (`<`, `>`, `<=`, `>=`)**

These operators are defined for numeric types and, where the implementation specifies, for other totally ordered types (e.g. lexicographic order on strings). For combinations where ordering is not defined, the implementation may yield `False` or reject the program at compile time; the language does not require a total order on every type.

#### 3.2.2 Type test (`e is T`)

- **Syntax:** `IsExpr` in the grammar above: `RelExpr` optionally followed by **`is`** and a **Type** (§3.6).
- **Typing:** The expression has type **Bool** (06 §8). The type checker must ensure **`T`** can **narrow** the type of **`e`** (structural overlap with **`e`**’s type); otherwise it is a compile-time error (06 §4, 10 §4 `type:narrow_impossible`). **Opaque** ADT rules from importing modules apply as for pattern matching (06 §5.3, 07 §5.3; `type:narrow_opaque` when violated).
- **Narrowing:** When `e` is a **simple identifier** `x`, the type of `x` is refined in **`if`**’s **then**-branch and **`while`**’s **body** to **`original_type & T`** (06 §4). The **`else`** branch (if any) keeps **`x`** at the **unrefined** type. Standalone **`x is T`** does not change the binding’s type outside the boolean result.
- **Runtime truth (summary):** **`T`** is checked **structurally** against the value of **`e`**: primitives and heap **kind** (e.g. Int vs String); **ADT** variants by constructor **tag** (and payload where needed); **records** by presence and type of required fields. The JVM backend must correctly implement these checks for all well-typed programs.

```
Expr           ::= IfExpr
                 | WhileExpr
                 | MatchExpr
                 | TryExpr
                 | Lambda
                 | PipeExpr

PipeExpr       ::= ConsExpr { ("|>" | "<|") ConsExpr }
ConsExpr       ::= OrExpr [ "::" ConsExpr ]
OrExpr         ::= AndExpr { "|" AndExpr }
AndExpr        ::= IsExpr { "&" IsExpr }
IsExpr         ::= RelExpr [ "is" Type ]
RelExpr        ::= AddExpr { ("==" | "!=" | "<" | ">" | ">=" | "<=") AddExpr }
AddExpr        ::= MulExpr { ("+" | "-") MulExpr }
MulExpr        ::= PowExpr { ("*" | "/" | "%") PowExpr }
PowExpr        ::= Primary [ "**" PowExpr ]

IfExpr         ::= "if" "(" Expr ")" Expr [ "else" Expr ]
WhileExpr      ::= "while" "(" Expr ")" Block
MatchExpr      ::= "match" "(" Expr ")" "{" Case { Case } "}"   /* match must be exhaustive (see type system) */
Case           ::= Pattern "=>" Expr
Pattern        ::= ConsPattern | NonConsPattern
ConsPattern    ::= NonConsPattern "::" Pattern                                     /* list cons; right-associative */
NonConsPattern ::= "_"
                 | UPPER_IDENT [ "(" Pattern { "," Pattern } ")" ]                   /* constructor with positional args */
                 | ListPattern
                 | LOWER_IDENT                                                       /* variable binding */
                 | INTEGER
                 | FLOAT
                 | STRING
                 | CHAR_LITERAL
                 | Unit
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

Record spread `{ ...expr, field = value }` is implemented by compiling to the SPREAD instruction (04 §1.8) with an extended shape; the JVM runtime pops the base record and additional field values and produces a new record.

Application and field access are **postfix** on an atom: parse one Atom, then zero or more Suffix (call or field). So `f(x).y` is Atom `f`, Suffix `(x)`, Suffix `.y`. **Await:** A primary expression may be prefixed with `await` (e.g. `await f()`); valid only in async context (see §5).

**If expression:** `if (cond) thenBranch [ else elseBranch ]`. **cond** must be **Bool**. When **cond** is **`x is T`** with **`x`** an identifier, the **then**-branch is type-checked with **`x`** narrowed per 06 §4; the **else** branch uses the **unrefined** type of **`x`**. If **else** is omitted, the whole `if` has type **Unit** and **thenBranch** must have type **Unit** (06). If **else** is present, the two branches must unify to a common type. **thenBranch** and **elseBranch** are parsed in the same **statement vs expression** context as the `if` itself (§3.3): in statement context, a branch `{ ... }` may end with `:=` / `val` / `var` / `fun` and no trailing expression (implicit **Unit**); in expression context, a branch block still needs a value-producing tail unless the last line is promoted from an expression statement (§3.3).

**Pipeline semantics:** `e1 |> e2` passes `e1` as the **first** argument when `e2` is a call `f(a, b, …)` — i.e. `x |> f(y)` ≡ `f(x, y)` (and longer argument lists prepend `x` similarly). If `e2` is not a call, it must denote a unary function: `x |> f` ≡ `f(x)`. **Backward pipe:** `f <| x` ≡ `f(x)`; `f(y) <| x` ≡ `f(y, x)` (the piped value is the **last** argument when the left side is a call).

**While loop:** `while (cond) block` evaluates `cond` (which must be **Bool**) before each iteration; while it is `True`, `block` runs. When **cond** is **`x is T`** with **`x`** an identifier, **`block`** is type-checked with **`x`** narrowed to **`original_type & T`** (06 §4), like the **then** branch of **`if`**. The **block** is always parsed in **statement-oriented** form (§3.3): it may end with `:=` / `val` / `var` / `fun` / `break` / `continue` and no trailing expression (implicit **Unit**). The block’s value each iteration is still evaluated and discarded on the stack; the `while` expression has type **Unit** (06). Lowering uses conditional and backward branches (04 §1.6).

**`break` and `continue`:** These are **statements** (not general expressions) and may appear only as **BlockItem**s inside a **block** that is nested (lexically) within a `while` body (including nested blocks and `if`/`match` branch blocks inside the loop). **`break`** exits the **nearest** enclosing `while` loop (skipping the rest of the current iteration and any further iterations of that loop). **`continue`** skips the remainder of the current iteration of that same loop and jumps to the next **condition** test. In nested loops, both target the innermost enclosing `while`. Using `break` or `continue` outside any loop is a **compile-time error** (06, 10).

### 3.3 Blocks and Statements

```
Block          ::= "{" { BlockItem } Expr "}"
BlockItem      ::= Stmt [ ";" | NL ]
Stmt           ::= "val" LOWER_IDENT "=" Expr
                 | "var" LOWER_IDENT "=" Expr
                 | "fun" LOWER_IDENT [ "<" TypeParamList ">" ] "(" ParamList ")" ":" Type "=" Expr
                 | Expr ":=" Expr
                 | "break"
                 | "continue"
```

The production above is the **expression-oriented** shape: a trailing **Expr** is the block’s value. In **statement-oriented** positions (see prose below), the same `{` … `}` block may end with **`}`** immediately after the last **Stmt** (no trailing **Expr**); that is equivalent to a trailing **`()`** (type **Unit**, 06). The parser distinguishes positions per §3.3; the typechecker still sees a block with a normal **result** expression after this desugar.

A block-local **`fun`** declaration is **desugared** to `val name = (params) => body`; see §3.8 for closures. When the nested `fun` has a **full type signature** (all parameter types and return type), the name is in scope for the body so the function may call itself recursively. Every such block-local `fun` is also in scope in the body of every other such `fun` in the same block, so they may call each other (mutual recursion); declaration order does not affect name resolution.

**Trailing expression vs implicit Unit:** In **expression** context (e.g. the right-hand side of top-level or block `val`/`var`, a function’s `= body` when the body is a block, a function argument, the trailing expression of a block that is itself in expression context, a `match` case body, a `try` body, etc.), the block must end with a **trailing Expr** (the block’s value), or the last `BlockItem` may be an `ExprStmt` that is promoted to that value—same as before. Alternatively, in expression context, the block may end immediately after **`break`** or **`continue`** as the last statement: the implementation treats the block’s formal value as a **synthetic never** (a fresh type variable in inference, 06), so the block’s type **unifies with any expected type** (e.g. a function return type) even though control never reaches that tail. In **statement** context (top-level expression statement; each `ExprStmt` line inside a block that is itself in statement context; **`while` bodies**, which are always statement-oriented), the block may instead end immediately after a **`val`**, **`var`**, **`fun`**, **`break`**, **`continue`**, or **`:=`** statement; the block’s value is then **Unit** (`()`), and you need not write a trailing `()`.

**`if` branches:** The **then** and **else** subexpressions inherit the same context as the `if` itself. So in statement context (e.g. `if (c) { x := 1 }` as a top-level statement or inside a `while` body), a branch block may end with an assignment or binding without a trailing value. In expression context (e.g. `val y = if (c) a else b`, or `if` nested inside a function body’s trailing block expression), each branch must still be a full expression; a branch block cannot end with only `:=` / `val` / `var` / `fun` without an explicit trailing expression (such as `()` when the branch must have type **Unit**).

Each statement is followed by a **statement terminator**: `;`, newline, or `}` (when the next token starts the block’s final expression, or when `}` closes a statement-oriented block as above). `NL` denotes a newline token (or newline codepoint) used as terminator. See §3.5.

### 3.4 Literals (Expression-Level)

```
Literal        ::= INTEGER | FLOAT | STRING | CHAR_LITERAL | "True" | "False" | Unit
Unit           ::= "(" ")"
```

**Tuples:** Syntactically, grouping and constant tuples share the same parenthesized comma-separated form `"(" Expr { "," Expr } ")"` (and the same for patterns). A single expression or pattern `(e)` or `(p)` is treated as **grouping** (same as `e` or `p`). Two or more `(e1, e2, …)` form a **constant tuple** with product type (e.g. `(Int, String)` has type `Int * String`). Tuple patterns match the same shape: `(p1, p2)` or `(p1, p2, p3, …)`. The parser disambiguates by the presence of a comma after the first element. `()` is always the **Unit** literal (expression or pattern), not a tuple.

At runtime, tuple values use the same representation as **records** with **positional field names** `"0"`, `"1"`, … in the JVM runtime. In `match`, tuple patterns destructure by those indices (06 exhaustiveness for tuple `match`).

For float literal patterns, matching uses pattern semantics (not plain `==`): a float NaN pattern matches a NaN scrutinee.

**No member calls:** The grammar does not allow `e.M(args)` (method call). Function and constructor calls use `e(args)`; field read uses the postfix `e.fieldName` (Suffix `"." LOWER_IDENT`).

### 3.5 Optional Semicolons and Line Boundaries

- **Statement/expression boundaries:** A newline (or `;`) may be used to separate statements and to separate the last statement from the trailing block expression. Concretely: after `Expr` in a Stmt, and after the last Stmt before the block Expr, a newline or `;` is allowed. In a **statement-oriented** block (§3.3), `}` may close the block immediately after a complete Stmt with no further expression. A newline is **not** treated as a terminator when it would break a valid expression: e.g. there must be no newline between `Expr` and `=>` in a lambda or case, or between a function and `(` in an application. Implementations may treat newline as terminator only after a complete Stmt (e.g. after `val x = e`, `var x = e`, or `e := e`) or allow semicolons everywhere as explicit terminators.
- **Newlines are not tokens in the reference lexer:** Physical line breaks are skipped like other whitespace. A line break alone does **not** separate `val`/`var` initializers from a following expression that starts with `(`. If the initializer ends with `)` (e.g. `f(a)`) and the next line begins with `(…)`, the parser will treat that `(` as **another** postfix call (currying) unless you end the statement with **`;`**. Example: use `val cp = codePoint(c);` before a line `(cp >= 48 & …) | …`. Literals cannot be call targets, so `val n = 1` followed by `(expr)` on the next line is not fused into `1(expr)`.
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

**Union / intersection at use sites:** Where a type is **expected** (function parameter, declared return, assignment target, annotated binding when supported by the parser), a **value** whose type is a **member** of a union (e.g. `Int` where `Int | Bool` is expected) is allowed; the full rules are in [06-typesystem.md](06-typesystem.md) §3 (subtyping) and §4 (narrowing with `is`). Values at runtime do not gain a separate “union tag”.

### 3.7 Parser and Lexer Disambiguation

- **Shebang:** Before tokenizing, if the source starts with `#!` (after optional BOM), skip the entire first line (including the newline); tokenization begins on the second line. Do not treat `#` as a token elsewhere.
- **Longest match:** The lexer always takes the longest possible token (e.g. `identifier` not `ident` + `ifier`; `0xFF` as one integer). **Arrow:** `=>` is a single token (lambda and case arrow); it must be matched as one token, not `=` followed by `>`.
- **Keywords:** Keyword tokens are matched before generic IDENT (e.g. `if` is keyword, not identifier). Match fixed keyword strings as tokens first.
- **Statement termination:** After a Stmt, the parser must see one of `;`, newline, or `}`. The lexer may emit a **newline token** (e.g. on `\n` or `\r\n`) so the parser can treat it as a terminator; or the parser may use a different rule (e.g. require `;` and ignore newlines, or use the next token’s line number). The choice is implementation-defined; the grammar assumes some notion of statement end.
- **Ambiguous prefixes:** `( ParamList )` appears in Lambda and in parenthesized Expr. Use context: after `=>` expect Expr; after `(` at expression position expect Expr; after `fun` IDENT `(` expect ParamList. Type versus expression after `(`: if the first token is IDENT followed by `:` or `,` or `)`, parse as ParamList; otherwise parse as Expr.
- **Record vs block:** `{` can start Block or RecordLit. After `{`, if the next token is `}` (empty record literal) or a label (IDENT `=` or `...`), parse as RecordLit; if the next token is `val`, `var`, `fun`, `break`, `continue`, or an expression start, parse as Block. (Expression start: Literal, IDENT, `(`, `[`, `throw`, `if`, `while`, `match`, `try`, `await`, etc.) Whether a Block may end after the last **Stmt** without a trailing **Expr** depends on **statement vs expression context** (§3.3), not on this disambiguation.
- **Parenthesized type:** `"(" Type ")"` vs `"(" TypeList ")" "->" Type`: after parsing `"("` and one or more types, if the next token is `"->"`, treat as function type and parse the rest of the arrow type; otherwise treat as a single grouped type `"(" Type ")"`.
- **Paren vs tuple:** After `"("` at expression or pattern position, parse one Expr or Pattern. If the next token is `","`, parse as tuple (two or more elements) and require the matching closing `")"`; otherwise parse as grouping (single `Expr` or `Pattern` and `")"`).
- **List literal vs pattern:** `"["` at expression position (in Atom) starts `ListLiteral`. `"["` at pattern position starts `ListPattern`. In a list pattern, at most one `"..." LOWER_IDENT` is allowed and only as the **last** component (e.g. `[a, b, ...rest]` or `[...rest]`); the grammar enforces this via `ListPatInner`.

### 3.8 Closures and Capture

Lambdas `(params) => body` and nested functions (block-local `fun`, desugared to `val name = (params) => body`) may **capture** variables from the enclosing block or function scope (lexical/static scope). The **capture set** of a lambda is the set of free variables: identifiers used in `body` that are not in the lambda's own `params` (and not introduced by an inner lambda's params). Enclosing scope includes: earlier `val`/`var`/`fun` bindings in the same block, and (when the block is inside a function) that function's parameters and outer blocks.

The implementation uses **closure conversion**: each capturing lambda is compiled as a **lifted** function that takes an **environment** (a record of captured values) as its first parameter; the environment is built at the point where the lambda is created and stored in a **closure** value. Non-capturing lambdas are represented as a function reference only (no environment).

**Capture semantics:** `val` bindings are captured **by value** (the value at creation time is stored in the environment). `var` bindings are captured **by reference** via a mutable cell (e.g. a one-field record) so that assignments to the variable inside the closure are visible outside and vice versa; both the closure and the enclosing scope operate on the same storage.

**Return type:** The declared return type of a block-local `fun name(...): ReturnType = body` is **checked**: the body's inferred type must unify with `ReturnType`; if not, the implementation reports a type error.


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

Test harness note: `./scripts/kestrel test` generates suite calls as `await runN(root)` inside `async fun main(): Task<Unit>`, so harness execution obeys the same async-context rule and does not require top-level `await` support.

Runtime behaviour:

- On the JVM backend, `Task<T>` values are runtime `kestrel.runtime.KTask` objects.
- Async function calls submit their bodies to the runtime virtual-thread executor and immediately return `KTask` backed by a `CompletableFuture<Object>`.
- `await e` lowers to `KTask.get()`: completed tasks return immediately; pending tasks block the current virtual thread until completion; exceptional completion rethrows the original failure so surrounding `try/catch` can handle it normally.
- Runtime stdlib I/O/process tasks use `Result` payloads for expected operational failures. For example, `await Fs.readText(path)` produces `Result<String, FsError>`, `await Fs.listDir(path)` produces `Result<List<String>, FsError>`, and `await Process.runProcess(program, args)` produces `Result<Int, ProcessError>`; callers pattern-match on `Ok` / `Err`.
- Process lifetime at top-level return is controlled by the CLI run mode (09 §2.1): default `kestrel run` / `--exit-wait` waits for pending async tasks to quiesce before exit; `--exit-no-wait` exits when `main` returns and may interrupt in-flight virtual-thread work.

---

## 6. Related Specifications

- [06-typesystem.md](06-typesystem.md) – Types, row polymorphism, inference
- [07-modules.md](07-modules.md) – Imports and exports
- [02-stdlib.md](02-stdlib.md) – Standard library (e.g. `Stack`)
