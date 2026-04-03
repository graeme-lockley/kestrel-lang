# 06 – Type System Specification

Version: 1.0

---

Kestrel’s type system provides Hindley–Milner inference, structural records with row polymorphism, and union/intersection types. This document specifies the type language and typing rules.

---

## 1. Types (Grammar)

```
Type ::=
    Int
  | Float
  | Bool
  | String
  | Unit
  | Char
  | Rune
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
```

- **Product:** `Type "*" Type` (e.g. pair).
- **Function:** `(TypeList) -> Type`.
- **Record:** `{ FieldList }`; see §2 for row syntax. A field may be **mutable:** `ident : mut Type`. Values of that record type may have the field updated by assignment (e.g. `r.age := 42`) on any binding (val or var). Fields without `mut` are immutable.
- **Row variable:** `{ ...R }` binds `R` in the signature.
- **Union / intersection:** `A | B`, `A & B`. Precedence: `&` binds tighter than `|`.
- **Built-in generics:** `Array<T>` and `Task<T>` are part of the runtime; each takes one type argument. `Array<T>` denotes a mutable sequence of values of type `T`. `Task<T>` denotes an asynchronous computation that yields a value of type `T` (see async/await in the language spec).
- **Library types:** `Option<T>`, `Result<T,E>`, and `List<T>` are provided by the standard library (see [02-stdlib.md](02-stdlib.md)). `Option<T>`: optional value; `Result<T,E>`: success `T` or error `E`; `List<T>`: immutable list with special syntax `[a, b, ...c]` and `::` (expression and pattern). In the bytecode type table (03 §6.3), `Result<T,E>` is encoded as **ADT** (tag 8) with the Result adt_index and two type arguments; there is no dedicated Result type tag.
- **IDENT:** Named types (e.g. type aliases, ADTs) from the current scope. **FieldList** is defined in 01 §3.6 (TypeFieldList): `ident : [mut] Type` comma-separated; use the same for record types in 06. **Char** and **Rune** denote the same type (one Unicode code point); both names are valid in types and have the same runtime representation (05).

### 1.1 Structural types (summary)

Kestrel supports the following **structural types** (in addition to built-in primitives and generics):

| Kind         | Syntax / form              | Description |
|--------------|----------------------------|-------------|
| **Tuple**    | `A * B`, `(A, B, C)`       | Product type; fixed-length sequence of types (grammar: `AppType` with `*`). |
| **Record**   | `{ x: T, y: U }`           | Structural record with named fields; row polymorphism (`...R`, `...,`) for extension. |
| **Function** | `(T1, T2) -> R`            | Function type; argument list and return type. |
| **ADT**      | `IDENT` (e.g. `Option`, `List`) | Algebraic data type; user-defined via `type` with constructors (UPPER_IDENT); pattern-matched. |
| **Union**    | `A | B`                    | Value has type A or B; `is` narrows (01: keyword `is`). |
| **Intersection** | `A & B`                | Value satisfies both A and B; used in narrowing. |

---

## 2. Row Polymorphism

### Row syntax

```
{ a: Int, ...R }
```

- `{ ..., }`: anonymous row remainder (universally quantified).
- `{ ...R }`: binds row variable `R` within the type signature.
- Rows are universally quantified at function boundaries.

### Spread and extension

Record expression form:

```
{ ...r, x = v }
```

**Typing:**

- If `r` already has field `x`: types must unify; result row is the same as `r`’s row.
- If `r` does not have `x`: result row is `r`’s row extended with `x`.
- If `x` is present in `r` with a different type than `v`, or typing otherwise conflicts → **compile error**.

---

## 3. Hindley–Milner Inference

- **Generalisation:** Types are generalised (closed over with universal quantification over type and row variables) at **let-bound** and **function** definitions: at each `val x = e` and `fun f(...) = e`, the inferred type of `e` (or the function body) is generalised so that `x` and `f` are polymorphic. Top-level and block-level `val` and `fun` both generalise; parameters are not generalised (they are monomorphic in the function body unless introduced by a nested let).
- **Instantiation:** At each use of a polymorphic value, its type is instantiated to fresh type variables before unification with the expected type.
- **Unification:** Standard unification algorithm for types, extended with row unification below. Unification may **fail** (e.g. Int vs Bool); the compiler reports a type error and the offending types. The algorithm must include an **occurs check**: when unifying a type variable α with a type S, if α occurs in S then unification fails (prevents infinite types, e.g. α = List<α>).
- **Subtyping (assignability) for `|` / `&`:** At annotations, assignment, and function return checking, the compiler uses **subtyping** (`unifySubtype`) where an **actual** type **A** must match an **expected** type **E**: if **E** is a **union**, **A** must be assignable to **at least one** arm; if **A** is a **union**, **every** arm of **A** must be assignable to **E**; if **E** is an **intersection**, **A** must be assignable to **each** conjunct; if **A** is an **intersection**, **A** is assignable to **E** when **each** conjunct is assignable to **E**. For **function** types used as **values** (higher-order), subtyping is **contravariant** in parameters and **covariant** in the return type (`unifySubtype` on two arrow types). **Direct calls** first attempt ordinary **unification** between each argument type and the corresponding parameter type (so polymorphic calls such as `eq(..., x, y)` with a shared type variable still work); if unification fails, the compiler retries with **subtyping** on that parameter so e.g. **Int** can match **Int | Bool**. For the call’s **result** type, it unifies callee return with the inferred result; on failure it uses **subtyping**, and when the callee’s return is a **union** or **intersection** and the inferred result is a fresh type variable, the compiler binds that variable to the **whole** callee return type (avoiding an unsound single-arm collapse).

### Row unification

```
unify({ a:T1 | R1 }, { a:T2 | R2 })
  => unify(T1, T2)
  => unify(R1, R2)
```

(Here `|` is the row “cons” in the type grammar, not the union type.)

---

## 4. Unions and Intersections

- **Union:** `A | B` – value has type `A` or type `B`.
- **Intersection:** `A & B` – value satisfies both `A` and `B`.
- **Conformance:** `is` checks structural conformance (e.g. shape of record, tag of ADT).

### Narrowing

The expression **`e is T`** is defined in [01-language.md](01-language.md) §3.2.2. Its type is **Bool** (see §8).

**Refinement sites:** When **`e`** is an identifier **`x`**:

- In **`if (x is T) { then } [else { else }] `**, the type of **`x`** in **`then`** is **`original_type & T`**. In **`else`**, **`x`** keeps the **unrefined** **`original_type`** (the implementation does **not** exclude **`T`** from a union in the else branch).
- In **`while (x is T) { body }`**, the type of **`x`** in **`body`** is **`original_type & T`** (same refinement as **`if`**’s then-branch).

**Validity:** The type checker must reject **`e is T`** when there is **no structural overlap** between the type of **`e`** and **`T`** (after the usual rules for unions, records, ADTs, and primitives). Report **`type:narrow_impossible`** (10 §4). For **imported opaque ADTs**, **`T`** may only be the **exported type name** itself, analogously to pattern matching — **`type:narrow_opaque`** when violated (§5.3, 07 §5.3).

```
if (x is T) { ... }
```

Inside the **then** branch above, the type of `x` is narrowed to:

```
original_type & T
```

So `x` is treated as both its original type and `T` in that block. For **standalone** **`e is T`** (e.g. as a boolean operand), there is no refinement of bindings beyond the **Bool** value of the expression.

---

## 5. Match Exhaustiveness

**Match** expressions (01 §3.2: `match (e) { case1 => e1 ; ... }`) must be **exhaustive** with respect to the type of `e`. The type system enforces:

- If `e` has type an **ADT** (e.g. Option, List, or a user ADT), every **constructor** of that ADT must be covered by at least one case (constructor pattern or list pattern for List), or a **catch-all** pattern (`_` or a variable) must appear that covers the remainder. If a constructor is missing and there is no catch-all → **type error**.
- If `e` has primitive type **Int**, **Float**, **String**, or **Char** and the match contains one or more primitive literal patterns, a catch-all (`_` or variable) is required (the domain is not finitely enumerable for exhaustiveness).
- If `e` has primitive type **Unit**, the literal pattern `()` is exhaustive by itself; otherwise a catch-all is required.
- If `e` has a **union** type `A | B`, each branch of the union must be covered (e.g. by constructor patterns for each ADT in the union, or by `_`).
- The type of the whole match expression is the **unification** (or least upper bound) of the types of all case right-hand sides; if they do not unify, it is a type error.

Exhaustiveness is decidable for finite ADTs and union types; the compiler must check it so that no runtime tag is left unhandled (04 MATCH, 05 ADT).

### 5.1 User-defined ADTs

**ADT definition** (01 §3.1): `type T = C1(T1,...) | C2(T1,...) | ...` introduces a new type `T` with named constructors. Each constructor is a function:

- **Nullary** constructor `C` has type `T` (a constant value of type `T`).
- **Unary** constructor `C(A)` has type `(A) -> T`.
- **N-ary** constructor `C(A1, ..., An)` has type `(A1, ..., An) -> T`.

Constructors are in scope wherever the type name is in scope (module-level or imported; see opaque rules in §5.3).

**Constructor application** uses standard call syntax: `Some(42)`, `Node(left, right)`. For nullary constructors, no parentheses: `None`, `Red`.

**Qualified constructors (namespace import):** When `M` is bound by `import * as M from "…"` (07 §2.3), each exported constructor `C` of an exported **non-opaque** ADT in that module is available as **`M.C`**: nullary `M.C` has the same type **`T`** as unqualified `C`; k-ary **`M.C(e1,…,ek)`** has the same type rules as **`C(e1,…,ek)`** (payload types and return type `T`). Opaque ADT constructors are not members of `M`. Arity and argument-type errors are the same as for unqualified constructor application.

**Pattern matching** on user-defined ADTs uses the same constructor syntax: `Some(x) => ...`, `Node(l, r) => ...`, `Red => ...`. Pattern variables bind to the positional payload values.

**Exhaustiveness** for user-defined ADTs: the compiler builds a **constructor registry** from type declarations mapping each ADT name to the set of its constructors. When `match (e) { ... }` has `e` of a user-defined ADT type, every constructor must be covered by at least one case, or a catch-all (`_` or variable) must be present.

**Tuple patterns in `match`:** The scrutinee must have a **tuple** type whose arity matches the tuple pattern. A tuple pattern with **literal** (or otherwise non–variable-only) subpatterns is **not** exhaustive by itself: a catch-all case (`_` or a variable pattern) is required unless there is an arm that matches all tuple values with only variables and wildcards in every slot (including nested tuple patterns), e.g. a single arm `(x, y) => …` for a pair type. Arity mismatch or a tuple pattern against a non-tuple scrutinee is a **type error**.

### 5.2 Recursive and mutually recursive types

All type names declared at the same scope level (top-level or within a block) are in scope for all type bodies at that level, regardless of declaration order. This enables:

- **Self-recursive types**: `type Tree = Leaf(Int) | Node(Tree, Tree)` — the reference to `Tree` in `Node(Tree, Tree)` resolves to the type being defined.
- **Mutually recursive types**: `type Expr = Lit(Int) | Add(Expr, Expr) | IfExpr(BoolExpr, Expr, Expr)` and `type BoolExpr = BTrue | BFalse | Eq(Expr, Expr)` — each references the other.

The implementation uses a two-pass approach: (1) forward-declare all type names, (2) process all type bodies. Standard unification occurs-check is relaxed for named ADT self-references (the recursion is guarded by constructors and structurally well-founded). Infinite type aliases (e.g., `type Bad = Bad` or `type Loop = List<Loop>`) are rejected.

### 5.3 Opaque types

**Opaque type** (01 §3.1): `opaque type T = ...` exports the type name `T` but hides the internal structure from importers.

**Within the declaring module:** Full access. Constructors are in scope, pattern matching is allowed, the underlying type (for aliases) is visible. No restrictions.

**For importing modules:**

- **Opaque ADT** (e.g., `opaque type Token = Num(Int) | Op(String)`): The type name `Token` is available for use in type annotations and function signatures. The constructors `Num` and `Op` are **not** in scope. Attempting to construct (`Num(42)`) or pattern-match (`Num(n) => ...`) is a **compile error**: "constructor `Num` is not accessible; type `Token` is opaque".
- **Opaque type alias** (e.g., `opaque type UserId = Int`): The type name `UserId` is available but the underlying type `Int` is not visible. A `UserId` value cannot be implicitly used as an `Int`. The declaring module must provide explicit conversion functions.
- **Opaque record alias** (e.g., `opaque type Config = { host: String, port: Int }`): The type name is available but field access is not allowed from outside.

The types file (07 §5) represents opaque types with a placeholder (the name and arity, but not the structure) so that consuming compilers cannot bypass the restriction.

---

## 6. Async and Await

- **Async functions (01 §5):** A function declared with `async` must have a return type of the form **Task<T>**. The body is type-checked in an **async context**.
- **Async context:** The body of an `async fun` and the body of an `async` lambda are async contexts. Only in an async context may **await** be used.
- **Await:** The expression `await e` is well-typed only if (1) **e** has type **Task<A>** for some type **A**, and (2) the expression appears in an **async context**. The type of `await e` is **A**. Use of `await` outside an async context (e.g. in a non-async function or at top level) is a **type or context error** (01 §5).
- **Result-typed async stdlib:** For stdlib operations that encode failure as data, `A` may itself be a `Result<T, E>`. Example: `await Fs.readText(path)` has type `Result<String, FsError>`, `await Fs.listDir(path)` has type `Result<List<String>, FsError>`, and `await Process.runProcess(program, args)` has type `Result<Int, ProcessError>`.
- **Task<T>** is a built-in type (01 §3.6, 02); its values are created by calling async functions or by runtime primitives. On the JVM backend these values are represented by `kestrel.runtime.KTask` (wrapping `CompletableFuture<Object>`). The type system does not distinguish “suspended” vs “completed” tasks; both have type Task<T>.
- **JVM async runtime model:** Async JVM function calls create pending `KTask` values by submitting function bodies to the runtime virtual-thread executor. `await` invokes `KTask.get()`, which blocks until the task completes and then returns the payload or rethrows the original failure. These runtime details do not affect the static typing rules: both pending and completed tasks have the same type `Task<T>`.

---

## 7. Exceptions

- **Exception types (01 §4):** Exceptions are declared with `export exception Name { ... }` and are represented as **ADTs** with one constructor (03 §10, 05). The type of an exception value is that ADT (e.g. `FileNotFound`).
- **Throw:** The expression `throw e` is well-typed only if **e** has an **exception type** (an ADT that is declared as an exception in the current module or an imported one). The type of `throw e` can be taken as **bottom** (no return) or a special type so that it unifies with any expected type in the surrounding context.
- **Try/catch:** `try block catch (x) { cases }` or `try block catch { cases }` — the **block** has some type **T**. The **catch** may optionally bind a variable **x** to the thrown value (type is the union of possible exception types that might be thrown, or a generic exception type); if omitted, the exception is only used for pattern matching. Each **case** is a pattern (including exception constructor patterns) and a right-hand side; the types of all case right-hand sides must unify with **T** (the type of the try block), and that is the type of the whole try expression. Exhaustiveness of catch cases is not required (01 §4). If no case matches the thrown value, the exception is **rethrown** (01); the type system does not require the catch to be exhaustive.

---

## 8. Expression Typing (Summary)

The following table summarises the main typing constraints so that implementors can ensure all language constructs (01) are covered. Inference proceeds by generating constraints and solving them with unification (and row unification).

| Construct | Constraint / rule |
|-----------|-------------------|
| **Literals** (Int, Float, Bool, Unit, Char, String) | Fixed types: Int, Float, Bool, Unit, Char, String. |
| **Tuple** `(e1, e2)` | e1 : T1, e2 : T2 ⇒ type is T1 * T2. |
| **Record** `{ x = e, ... }` | Row typing; see §2. Spread: if `...r` then r’s row extended or unified with new fields. |
| **List** `[e1, ...]`, `[]` | Elements unify to T ⇒ type is List<T>. Empty list has type List<α> for fresh α. |
| **Cons** `e1 :: e2` | e2 : List<T>, e1 : T ⇒ type is List<T>. |
| **Application** `f(e1,...,en)` | f : (T1,...,Tn) -> R, ei : Ti ⇒ type is R. Includes constructor application: `Some(42)` where `Some : (Int) -> Option<Int>`. |
| **Field access** `e.x` | e : { x: T, ... } ⇒ type is T. |
| **If** `if (e1) e2` (no else) | e1 : Bool; e2 : **Unit** ⇒ type is **Unit** (01 §3). |
| **If/else** `if (e1) e2 else e3` | e1 : Bool; e2 : T, e3 : T′, T and T′ unify ⇒ type is the unified type. |
| **Block** `{ stmts… ; result }` | Statements are typed for effect; **result** (or implicit **Unit** when the parser closed the block in statement-oriented mode per 01 §3.3) gives the block’s type. |
| **While** `while (e1) block` | e1 : Bool; **block** is typed as a block (01 §3.3: **while** bodies use statement-oriented parsing, so the block may end with implicit **Unit** after `:=` / `val` / `var` / `fun` / `break` / `continue`); the value of `while` is **Unit** (each iteration’s block value is discarded). |
| **`break` / `continue`** | Valid only when lexically inside a **while** body (01 §3.3, loop statements). Each statement has type **Unit**. Outside any loop: errors `type:break_outside_loop` and `type:continue_outside_loop` (10 §4). When a block in **expression** context (01 §3.3) ends with `break` or `continue` as its last statement, the block’s synthetic tail infers as a **fresh type variable**, so the block unifies with any expected type (same idea as a polymorphic “bottom” / never-returns tail). |
| **Match** `match (e) { cases }` | e : S; each case pattern is typed against S (pattern produces bindings; constructor/list patterns constrain S); case RHSs unify to T; exhaustiveness (§5) ⇒ type is T. |
| **Lambda** `(p1,...,pn) => e`, `async (p1,...,pn) => e` | Parameter types from annotation or inference. For a sync lambda, `e : R` ⇒ type is `(T1,...,Tn) -> R`. For an async lambda, `e : R` in async context ⇒ type is `(T1,...,Tn) -> Task<R>`. Lambdas and nested functions may capture enclosing variables (01 §3.8); closure conversion is a codegen concern and does not change the inferred function type. For a **block-local** `fun name(...): ReturnType = body`, when a return type is declared, the body's inferred type is unified with that return type and the binding gets the declared arrow type (params → ReturnType). |
| **Throw** `throw e` | e : exception type (§7) ⇒ type is bottom (or compatible with context). |
| **Await** `await e` | e : Task<A>, in async context (§6) ⇒ type is A. |
| **`e is T` (type test)** | **`e : S`**, **`T`** a type; **`S`** must **overlap** **`T`** structurally or compile error (**§4**, `type:narrow_impossible`). Result type **Bool**. |
| **Narrowing** `if (x is T) { ... }` | In **then**-branch, **`x`** has type **original & T**; in **else**, **`x`** unrefined (**§4**). |
| **Narrowing** `while (x is T) { ... }` | In **body**, **`x`** has type **original & T** (**§4**). |

Additional constraints: **SET_FIELD** (04) applies only to records with a **mut** field at that slot; the type system must ensure that assignment to a field is only for `mut` fields (01 §3.6). **Assignment** `x := e` (01): the type of `e` must be **assignable** to the type of `x` (subtyping as in §3 when `|` / `&` are involved; equality otherwise), and `x` must be a `var` or a mutable field. **Binary operators:** Arithmetic (+, -, *, /, %, **): both operands must have the same numeric type (**Int** or **Float**); result has that type (01 §2.6, §2.7). Comparison (==, !=, <, >, <=, >=): both operands have the same type; result is **Bool**. **Value** semantics of `==` and `!=` (deep equality, `!=` as negation of `==`) are defined in **01 §3.2.1**. Logical (&, |): both operands **Bool**; result **Bool**. The compiler emits typed bytecode (03 type table, 04) so the VM (05) receives values of the expected shapes.

Pattern typing for primitive literal patterns: `INTEGER : Int`, `FLOAT : Float`, `STRING : String`, `CHAR_LITERAL : Char`, and `Unit` (`()`) : `Unit`. A literal pattern must unify with the scrutinee type. Float NaN patterns use pattern semantics: NaN literal patterns match NaN scrutinee values.

---

## 9. Relation to Other Specs

| Spec | Relation |
|------|----------|
| **01** | Type grammar (01 §3.6), expressions, blocks (statement- vs expression-oriented endings, 01 §3.3), `if`/`while`, match exhaustiveness, async/await context, exceptions, mut fields. All types and constructs in 01 must have typing rules in this document. |
| **02** | Option, Result, List, Task are library types; JSON `Value` / `JsonParseError` and other stdlib ADTs are ordinary exported types (e.g. from `kestrel:json`); their constructors and signatures constrain inference. |
| **03** | Inferred types are serialised into the bytecode type table (03 §6.2–6.3). The type encoding supports Arrow, Record (shape_index), ADT, Option, List, TypeVar, and primitives. The reference toolchain does **not** encode union/intersection in the `.kbc` blob (03 §6.3); **`.kti`** may still carry them (07 §5). |
| **04** | Type-checked programs satisfy the ISA: e.g. ADD gets Int; CONSTRUCT gets correct adt_id, ctor, arity; CALL gets correct arity and function type. The type system does not define bytecode; it ensures source-level correctness so the compiler can emit valid 04. |
| **05** | Runtime values (tagged vs heap) correspond to types: Int, Bool, Unit, Char inline; Float, String, RECORD, ADT, TASK heap. Type safety at compile time implies the VM (05) will not see invalid operand types. |

---

## 10. Implementor Checklist

An implementation of the type system should provide at least the following:

1. **Type grammar and AST** — Parse types per 01 §3.6; build an internal representation (AST or equivalent) that supports all forms in §1, including row variables and union/intersection.
2. **Unification** — Implement standard unification with an **occurs check** (§3); extend with **row unification** for records (§3). On failure, report a type error and the two types that could not be unified.
3. **Generalisation and instantiation** — At each `val` and `fun`, generalise the inferred type (quantify type and row variables that are not free in the environment). At each use, instantiate with fresh variables before unifying.
4. **Constraint generation** — For every expression form in 01, generate typing constraints as in §8 (and §2 for records). Solve constraints by unification; infer types for let-bound and function definitions.
5. **Pattern typing** — For match and catch cases, type each pattern against the scrutinee type: constructor patterns require the scrutinee to be that ADT (or union containing it) and bind payload types; variable patterns bind the scrutinee type; literal patterns require the scrutinee to unify with the literal type. Ensure exhaustiveness per §5.
6. **Async context and exceptions** — Track whether the current scope is inside an `async fun`; reject `await` outside async context (§6). For `throw e`, require `e` to have an exception type (§7). For try/catch, type the block and unify catch case RHSs with the block type.
7. **Operators and assignment** — Enforce operand and result types for arithmetic, comparison, and logical operators (§8); ensure assignment and SET_FIELD only apply to mutable targets.
8. **Output** — Emit inferred types into the bytecode type table (03 §6.2–6.3) so that the VM and tooling can use them. The reference emitter keeps a **minimal** type blob; union/intersection are checked statically and are **not** written as distinct tags in `.kbc` (03 §6.3); **`.kti`** remains the cross-module carrier for rich signatures.
9. **Narrowing (`is`)** — Implement **`e is T`** (01 §3.2.2) with result type **Bool**; refine **`x`** in **`if`**/**`while`** branches per §4; reject impossible or opaque-violating **`T`** with stable codes (10 §4).

**Tail-call optimization** (self and mutual top-level calls; 04 §1.5, 05 §1.2) is a codegen/runtime framing detail only: it does not change typing rules or inferred types.
