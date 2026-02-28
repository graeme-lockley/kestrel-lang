# Kestrel v1 Language Specification

Version: 1.0 (Compiler + Zig VM Target)

This document is a concise overview of the Kestrel language and runtime. For full, implementor-level detail (grammar, bytecode layout, instruction encoding, type rules, modules), see the split specifications in **`docs/specs/`** (01–08).

------------------------------------------------------------------------

# 1. Philosophy and Design Goals

Kestrel is a statically typed, scripting and server-oriented programming language with:

-   Hindley–Milner type inference
-   Structural records with row polymorphism
-   Algebraic data types
-   Union (`|`) and intersection (`&`) types
-   Pattern-based exception handling
-   Async/await (`Task<T>`)
-   Pipeline operator (`|>`)
-   No member-call syntax (`x.f(y)` is invalid)
-   Bytecode compilation targeting a Zig-based VM

Kestrel prioritizes:

1.  Predictable semantics
2.  Mechanical simplicity
3.  Strong static typing
4.  Clean separation between compiler (TypeScript) and VM (Zig)
5.  Deterministic module resolution

------------------------------------------------------------------------

# 2. Lexical Structure

## 2.1 Identifiers

    LOWER_IDENT   ::= [a-z_][A-Za-z0-9_]*
    UPPER_IDENT   ::= [A-Z][A-Za-z0-9_]*
    IDENT         ::= LOWER_IDENT | UPPER_IDENT

**Naming rules:** Types, constructors, exception names, and module namespace aliases use **UPPER_IDENT**. Functions, `val`/`var` bindings, parameters, and record/exception field names use **LOWER_IDENT**. Keywords are reserved.

## 2.2 Operators and Delimiters

The lexer uses **longest match**. Multi-character tokens: `:=`, `==`, `!=`, `>=`, `<=`, `**`, `|>`, `<|`, `::`, and **`=>`** (case/lambda arrow; single token). Delimiters: `( ) { } [ ] , : . ;`. The character `=` appears only in `==`, `:=`, or `=>`.

## 2.3 Keywords

    fun type val var mut if else match try catch throw async await
    export import from exception is True False

`True` and `False` are boolean literals; the rest are syntactic keywords.

## 2.4 Literals

### Integers

    123  0xFF  0b1010  0o77  1_000_000

Underscores only between digits. 61-bit signed at runtime; overflow throws.

### Floats

    1.0  0.5  .5  5.  1e10  2.5e-3

64-bit IEEE 754. Float is boxed at runtime.

### Strings

All strings are template strings. Interpolation: `$name` or `${ Expr }`. The closing `}` for `${` is found by **brace balancing** (count `{` and `}`; first `}` that brings the count to zero). Interpolation uses implicit `toString()`.

### Characters and Runes

    'x'   '\u{1F600}'

**Char** and **Rune** denote the same type (one Unicode code point).

### Boolean and Unit

    True   False   ()

------------------------------------------------------------------------

# 3. Grammar (Simplified EBNF)

    Program        ::= [ Shebang ] { ImportDecl } { ModuleDecl | TopLevelStmt }
    ModuleDecl     ::= ExportDecl | TopLevelDecl

Imports first; then declarations and top-level statements (executed in order when the module runs).

    ImportDecl     ::= "import" ImportClause "from" STRING
                     | "import" "*" "as" UPPER_IDENT "from" STRING
                     | "import" STRING

    ExportDecl     ::= "export" (TopLevelDecl | "*" "from" STRING
                                 | "{" ExportSpec { "," ExportSpec } "}" "from" STRING)

    TopLevelDecl   ::= FunDecl | TypeDecl | ExceptionDecl

    FunDecl        ::= [ "async" ] "fun" LOWER_IDENT "(" ParamList ")" ":" Type "=" Expr
    TypeDecl       ::= "type" UPPER_IDENT "=" Type
    ExceptionDecl  ::= "export" "exception" UPPER_IDENT [ "{" FieldList "}" ]

    Expr           ::= IfExpr | MatchExpr | TryExpr | Lambda | PipeExpr | ...

Expression precedence (low to high): `|>` `<|` (pipe); `::` (cons); `|` `&` (logic); `==` `!=` `<` `>` `>=` `<=`; `+` `-`; `*` `/` `%`; `**`. List literal: `[ e1, e2, ...e3 ]`. Cons: `e1 :: e2`.

    IfExpr         ::= "if" "(" Expr ")" Expr "else" Expr
    MatchExpr      ::= "match" "(" Expr ")" "{" Case+ "}"   /* exhaustive */
    TryExpr        ::= "try" Block "catch" "(" LOWER_IDENT ")" "{" Case+ "}"
    Lambda         ::= "(" ParamList ")" "=>" Expr

**Pipeline:** `e1 |> e2` passes the left-hand value as the first argument to the right-hand call: `x |> f` ≡ `f(x)`; `x |> f(y)` ≡ `f(x, y)`. Similarly `<|` passes the right-hand value as the last argument.

    Block          ::= "{" { Stmt } Expr "}"
    Stmt           ::= "val" LOWER_IDENT "=" Expr
                     | "var" LOWER_IDENT "=" Expr
                     | Expr ":=" Expr

The block’s trailing expression is the block value. Match must be exhaustive (all constructors or catch-all covered).

**Top-level recursion:** Every top-level function is in scope in the body of every top-level function. A function may call itself (self-recursion) or any other top-level function (mutual recursion); declaration order does not affect name resolution.

**Nested functions and closures:** A block may contain a local function declaration: `fun name(params): Type = body`, which is desugared to `val name = (params) => body`. When the nested `fun` has a **full type signature** (all parameter types and return type), the name is in scope for the body so it may call itself recursively. The declared return type is **checked** against the body's type; a mismatch is a type error. `var` bindings are captured **by reference** (shared mutable cell). Lambdas and nested functions may **capture** variables from the enclosing block or function scope (lexical scope). The implementation uses closure conversion: an environment record holds captured values, and a closure value pairs that environment with a function index. Non-capturing lambdas are represented as a function reference only. See [01-language.md](specs/01-language.md) §3.8 and [04-bytecode-isa.md](specs/04-bytecode-isa.md) §5.1.

------------------------------------------------------------------------

# 4. Type System

## 4.1 Types

    Type ::=
        Int | Float | Bool | String | Unit | Char | Rune
      | "Array" "<" Type ">"
      | "Task" "<" Type ">"
      | "Option" "<" Type ">"
      | "Result" "<" Type "," Type ">"
      | "List" "<" Type ">"
      | Type "*" Type
      | "(" TypeList ")" "->" Type
      | "{" FieldList "}"
      | "{" "...R" "}"
      | Type "|" Type
      | Type "&" Type
      | IDENT

`Array<T>` and `Task<T>` are runtime built-ins. `Option<T>`, `Result<T,E>`, and `List<T>` are standard library types. Record fields may be **mut** (e.g. `age: mut Int`); only those may be updated by assignment. `&` binds tighter than `|`.

## 4.2 Row Polymorphism

Row syntax:

    { a: Int, ...R }

Rules:

-   `{ ..., }` means anonymous row remainder (universally quantified).
-   `{ ...R }` binds row variable R within signature.
-   Rows are universally quantified at function boundaries.

Spread rule:

    { ...r, x = v }

Typing:

-   If `r` contains field `x`:
    -   Types must unify
    -   Result retains same row
-   If not:
    -   Result extends row

Conflict of differing types → compile error.

------------------------------------------------------------------------

## 4.3 Hindley–Milner Inference

-   Let-polymorphism
-   Generalization at `val` bindings
-   Instantiation at usage
-   Standard unification algorithm extended with row unification

Row unification:

    unify({ a:T1 | R1 }, { a:T2 | R2 })
    => unify(T1, T2)
    => unify(R1, R2)

------------------------------------------------------------------------

## 4.4 Unions and Intersections

-   `A | B` represents union
-   `A & B` represents intersection
-   `is` means structural conformance

Narrowing:

    if (x is T) { ... }

Within branch:

    x : original_type & T

------------------------------------------------------------------------

# 5. Exceptions

Declare:

    export exception DivideByZero
    export exception FileNotFound { name: String }

Throw:

    throw FileNotFound { name = path }

Catch:

    try { ... }
    catch (e) {
      FileNotFound { name } => ...
      _ => ...
    }

If no catch case matches the thrown value, the exception is **rethrown**. Stack trace via `Stack` module (e.g. `trace`).

------------------------------------------------------------------------

# 6. Async and Task Model

`async` functions return `Task<T>`.

    async fun f(): Task<Int> = { ... }
    val x = await f()

`await` only valid in async context.

VM instruction `AWAIT`:

-   If task complete → push result
-   Else suspend frame

------------------------------------------------------------------------

# 7. Standard Library and Built-in Primitives

## 7.1 Built-in print and println

The language provides two variadic built-in primitives for stdout:

- **`print(a, b, ...)`** — Print each value separated by spaces; **no** trailing newline.
- **`println(a, b, ...)`** — Print each value separated by spaces; **with** trailing newline.

Both accept one or more arguments of any type; each value is formatted (e.g. as in string conversion) and output with a single space between values. These are distinct from the **kestrel:stack** module’s `print(T): Unit` (see 02-stdlib), which is for stack-trace and stdlib use.

## 7.2 Standard Library modules

Contract: implementations must provide these modules with the listed signatures. See **`docs/specs/02-stdlib.md`** for the full contract.

### kestrel:string

-   length(String): Int
-   slice(String, Int, Int): String
-   indexOf(String, String): Int
-   equals(String, String): Bool
-   toUpperCase(String): String

### kestrel:stack

-   trace(T): StackTrace\<T\>
-   print(T): Unit
-   format(T): String

### kestrel:http

-   createServer((Request) -> Task\<Response\>): Server
-   listen(Server, { host: String, port: Int }): Task\<Unit\>
-   get(String): Task\<Response\>
-   bodyText(Request): Task\<String\>
-   queryParam(Request, String): Option\<String\>
-   requestId(Request): String
-   nowMs(): Int

### kestrel:json

-   parse(String): Value
-   stringify(Value): String

### kestrel:fs

-   readText(String): Task\<String\>

------------------------------------------------------------------------

# 8. Bytecode Format (.kbc)

One `.kbc` file per module. See **`docs/specs/03-bytecode-format.md`** for full layout.

Header: magic `KBC1`, u32 version, u32 section offsets (7 sections). All multi-byte integers **little-endian**, **4-byte aligned**.

Sections (index 0–6): (0) String table; (1) Constant pool; (2) Function table (includes type table, exported type aliases, import table); (3) Code section (entry point); (4) Debug section; (5) Shape table; (6) ADT table.

------------------------------------------------------------------------

# 9. Bytecode Instruction Set

Stack-based VM. Full opcode and operand layout: **`docs/specs/04-bytecode-isa.md`**.

Core instructions: LOAD_CONST, LOAD_LOCAL, STORE_LOCAL; ADD, SUB, MUL, DIV, MOD, POW; EQ, NE, LT, LE, GT, GE; CALL (fn_id, arity), RET; JUMP (i32 offset), JUMP_IF_FALSE (i32 offset); CONSTRUCT (adt_id, ctor, arity); MATCH (u32 count + count×i32 jump table); ALLOC_RECORD, GET_FIELD, SET_FIELD, SPREAD; THROW; TRY (handler_offset), END_TRY; AWAIT. All branch offsets are i32 relative to the **first byte of the instruction** containing the offset.

Calling convention: arguments pushed left-to-right; single return value.

------------------------------------------------------------------------

# 10. Runtime Value Model

64-bit tagged word: 3-bit tag + 61-bit payload. Tags: INT, BOOL, UNIT, CHAR, PTR. Float and String are **boxed** (PTR to heap). See **`docs/specs/05-runtime-model.md`**.

Heap object kinds: FLOAT (boxed double), STRING (UTF-8), ARRAY (built-in), RECORD (shape + slots), ADT (constructor tag + payload), TASK (suspended or completed). Closures use **closure conversion**: environment is a RECORD; no dedicated CLOSURE kind required.

GC: Mark-sweep (v1). Roots: stack, locals, globals.

------------------------------------------------------------------------

# 11. Module Resolution

Deterministic resolution. Specifier = exact string in `from "..."` (no normalisation). Kinds: **stdlib** (`kestrel:string`, `kestrel:stack`, `kestrel:http`, `kestrel:json`, `kestrel:fs`), **URL**, **path**. See **`docs/specs/07-modules.md`**.

Import forms: `import { x } from "./m.ks"`, `import * as M from "./m.ks"`, `import "./m.ks"`. Re-export: `export * from "./m.ks"`, `export { x as y } from "./m.ks"`. Same name from different sources (export or import) → compile error unless renamed. Lockfile: `kestrel.lock` (project root); format and behaviour implementation-defined.

------------------------------------------------------------------------

# End of Specification
