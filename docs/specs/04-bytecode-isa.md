# 04 – Bytecode Instruction Set

Version: 1.0

---

The Kestrel VM is **stack-based**. Instructions operate on an operand stack and on local slots. This document specifies the instruction set, how it maps to the bytecode format [03](03-bytecode-format.md), and how it executes all language constructs in [01](01-language.md).

---

## 1. Core Instructions

All jump **offsets** are **byte offsets** (signed or unsigned, see §4) relative to a defined base (e.g. current instruction or start of current function) so that the same .kbc file is interpreted identically by every implementation. All **indices** refer to the tables defined in [03-bytecode-format.md](03-bytecode-format.md) as stated below. References to constants, locals, functions, and types are **by index/offset only**; name-based resolution is not used at load or runtime (03 §0, 07 §9).

### 1.1 Constants and Locals

| Instruction | Operands | Effect |
|-------------|----------|--------|
| `LOAD_CONST` | `idx` (u32) | Push constant at index `idx` from the **constant pool** (03 §5). `idx` must be in [0, constant_pool_count). |
| `LOAD_LOCAL` | `idx` (u32) | Push value in local slot `idx`. |
| `STORE_LOCAL` | `idx` (u32) | Pop value and store in local slot `idx`. |
| `LOAD_GLOBAL` | `idx` (u32) | Push value in module global slot `idx` (03 §6, 05). Used by export var getters. |
| `STORE_GLOBAL` | `idx` (u32) | Pop value and store in module global slot `idx`. Used by export var setters. |

**Language coverage:** Literals (Int, Float, Bool, Unit, Char, String), `val`/`var` bindings, parameters. Module globals (export var) use LOAD_GLOBAL / STORE_GLOBAL (03, 05).

### 1.2 Arithmetic

| Instruction | Operands | Effect |
|-------------|----------|--------|
| `ADD` | — | Pop two values (L, R), push L + R. |
| `SUB` | — | Pop two values (L, R), push L - R. |
| `MUL` | — | Pop two values, push product. |
| `DIV` | — | Pop two values, push quotient; divide-by-zero throws. |
| `MOD` | — | Pop two values (L, R), push L % R; divide-by-zero throws. |
| `POW` | — | Pop two values (base, exponent), push base ** exponent (right-associative in source). |

**Language coverage:** `+`, `-`, `*`, `/`, `%`, `**` (01 §3.2).

### 1.3 Comparison

| Instruction | Operands | Effect |
|-------------|----------|--------|
| `EQ` | — | Pop two values, push True if equal else False. |
| `NE` | — | Pop two values, push True if not equal else False. |
| `LT` | — | Pop two values (L, R), push True if L < R else False. |
| `LE` | — | Pop two values, push True if L <= R else False. |
| `GT` | — | Pop two values, push True if L > R else False. |
| `GE` | — | Pop two values, push True if L >= R else False. |

**Language coverage:** `==`, `!=`, `<`, `>`, `>=`, `<=` (01 §3.2). Result is Bool; used with `JUMP_IF_FALSE` / `JUMP` for conditionals and short-circuit logic.

### 1.4 Logical (short-circuit)

Logical `&` and `|` in the language are short-circuit; the compiler emits branches (e.g. evaluate left, `JUMP_IF_FALSE` to skip right for `&`, or `JUMP_IF_FALSE` to result for `|`) rather than dedicated AND/OR instructions. No separate `AND`/`OR` stack instructions are required.

### 1.5 Calls and Returns

| Instruction | Operands | Effect |
|-------------|----------|--------|
| `CALL` | `fn_id` (u32), `arity` (u32) | Pop `arity` arguments (left-to-right: first arg at lowest stack position). **Local call:** if `fn_id` in [0, function_count), call the function at that index in **this** module’s function table (03 §6.1). **Cross-package call:** if `fn_id` in [function_count, function_count + imported_function_count), the VM uses the **imported function table** (03 §6.6): entry index `k` = `fn_id` - function_count gives (import_index, function_index); resolve the module for that import (load on first use, 07 §9), then call function at `function_index` in that module’s function table. Push return value. |
| `RET` | — | Pop the top value as the return value and return to the caller (caller’s frame receives that value). Used for both function exit and module initializer exit (03 §7). |

**Language coverage:** Function application `f(args)`, constructor application (when compiled as call to constructor), pipeline `|>` / `<|` (compiled to calls). **Alias:** `RETURN` may be used as a synonym for `RET`; 03 refers to `RET`.

### 1.10 Indirect Calls and Closures

| Instruction | Operands | Effect |
|-------------|----------|--------|
| `CALL_INDIRECT` | `arity` (u32) | Pop `arity` arguments, then one callee value. **If callee is fn_ref** (tag fn_ref): call with (module_index, fn_index) and the given `arity`; push return value. **If callee is PTR to CLOSURE** (05 §2): load (module_index, fn_index, env) from the CLOSURE object; push env onto the stack, then the `arity` argument values (so the lifted function receives env as first param); CALL with (module_index, fn_index) and arity = 1 + `arity`; push return value. |
| `LOAD_FN` | `fn_index` (u32) | Push **fn_ref** (current module index, `fn_index`). Used for non-capturing lambdas and nested functions. |
| `LOAD_IMPORTED_FN` | `imported_fn_index` (u32) | Push **fn_ref** for an imported function identifier used as a first-class value. The VM resolves `imported_fn_index` via this module’s `imported_functions` table and uses the referenced import specifier to find the dependency module index and the dependency function table index. |
| `MAKE_CLOSURE` | `fn_index` (u32) | Pop one value (must be PTR to RECORD = environment). Allocate a **CLOSURE** heap object (05 §2) containing (current module_index, fn_index, env); push PTR to it. Used when creating a capturing lambda or nested function. |

**Language coverage:** First-class function values (lambdas, nested fun), closure creation, calls through a value (e.g. `f(args)` when `f` is a local or parameter). Non-capturing lambdas use `LOAD_FN` only; imported function identifiers used as values compile to `LOAD_IMPORTED_FN`; capturing lambdas use `ALLOC_RECORD` (env) then `MAKE_CLOSURE`. See §5.1.

### 1.6 Control Flow

| Instruction | Operands | Effect |
|-------------|----------|--------|
| `JUMP` | `offset` | Unconditional jump. `offset` is a **byte offset** (see §4) from the base (e.g. start of current instruction or of function). |
| `JUMP_IF_FALSE` | `offset` | Pop one value; if it is False (or falsy per runtime model), jump by `offset`; else fall through. |

**Language coverage:** `if`/`else`, short-circuit `&`/`|`, loops (if added), pattern-match fall-through.

### 1.7 Algebraic Data Types

| Instruction | Operands | Effect |
|-------------|----------|--------|
| `CONSTRUCT` | `adt_id` (u32), `ctor` (u32), `arity` (u32) | Pop `arity` values (constructor payload, left-to-right). Build an ADT value for the constructor at index `ctor` of the ADT at index `adt_id` (03 §10: ADT table, constructor order = 0-based tag). Push the value. For no-payload constructors, `arity` is 0. |
| `MATCH` | — | Pop one value (ADT or list cons). Dispatch by runtime tag to one of the following **inline** targets: the next instruction encodes a **jump table** (e.g. count + offsets per tag). Exact encoding of the jump table is part of the instruction format (§4). Used for `match (e) { Ctor1 => ... ; Ctor2 => ... }`, list cons pattern, etc. |

**Language coverage:** ADT construction (including List cons `::`, Option, Result, exceptions), pattern matching on constructors and list patterns. **Note:** List is an ADT (e.g. Nil, Cons); `[a,b,c]` and `a::b` compile to CONSTRUCT with the list ADT and appropriate constructor.

### 1.8 Records

| Instruction | Operands | Effect |
|-------------|----------|--------|
| `ALLOC_RECORD` | `shape_id` (u32) | Allocate a record with **shape** from the shape table (03 §9). `shape_id` in [0, shape_count). Field slots are filled from the stack in **shape field order** (same order as in the shape table). Pop that many values, push the record. |
| `GET_FIELD` | `slot` (u32) | Pop record, push the value in field at index `slot` (0-based within the record’s shape). |
| `SET_FIELD` | `slot` (u32) | Pop value then record; set field `slot` to the value (only valid for `mut` fields); push unit or the updated record (see [05-runtime-model.md](05-runtime-model.md)). |
| `SPREAD` | `shape_id` (u32) | Row extension: pop a record and additional values; produce a new record with the extended shape (03 §9). Used for record literals `{ ...r, x = e }`. |

**Implementor note (SPREAD):** The extended shape’s field count must be ≥ the base record’s field count. The VM pops the record first to read its field count from the header, then pops (extended_count − base_count) additional values in extended-shape field order (top of stack = last new field). The **compiler** emits: (1) code for each additional field value in extended-shape field order (so they are on the stack below the record), (2) code for the spread expression (base record), (3) SPREAD with the extended shape_id.

**Language coverage:** Record literals `{ x = e, y = f }`, field access `e.x`, mutable field assignment `r.x := e` (01 §3.6). Tuples `(a, b)` may be compiled as records with an anonymous shape (field indices 0, 1, …).

### 1.9 Exceptions and Async

| Instruction | Operands | Effect |
|-------------|----------|--------|
| `THROW` | — | Pop exception value and throw (unwind to nearest handler). |
| `TRY` | `handler_offset` (byte offset) | Push try scope; on throw, jump to handler at `handler_offset`. |
| `END_TRY` | — | Pop try scope (reached when try block completes normally). |
| `AWAIT` | — | Pop `Task<T>`; if complete, push result; else suspend current frame (01 §5). |

**Language coverage:** `throw e`, `try { ... } catch (e) { ... }` or `try { ... } catch { ... }` (01 §4), `await e`.

**Node-style async I/O:** No extra instructions are required. Async I/O (e.g. stdlib `readText`, `get`, `listen`) is expressed as **CALL** to a function that returns `Task<T>` (often a native/runtime function that starts non-blocking I/O and returns a suspended TASK), followed by **AWAIT** to suspend the current frame until the task completes. The runtime (05) completes the task when I/O finishes and resumes the frame. The ISA does not define how I/O or the event loop work—only that AWAIT suspends and the runtime later resumes.

---

## 2. Calling Convention

- **Argument order:** Arguments are pushed **left-to-right** (first argument at the bottom of the call frame’s stack segment).
- **Return value:** The callee leaves a single value on the stack (or in a designated return slot); the caller pops it after `CALL` completes. `RET` pops that value and returns it to the caller.
- **Locals:** Each function has a fixed number of local slots. Parameters are assigned to consecutive local slots (e.g. 0, 1, …); then other locals (val/var in block scope). `LOAD_LOCAL` / `STORE_LOCAL` use these indices. Exact mapping (parameter index → local index) is compiler-defined; the VM only sees indices.

---

## 3. Relation to Bytecode Format (03)

The code section (03 §7) contains a sequence of instructions. Every operand that refers to module data uses the indices and tables defined in 03:

| Operand | Meaning | 03 reference |
|---------|---------|----------------|
| `idx` (LOAD_CONST) | Constant pool index | Section 1 (Constant pool); [0, constant_pool_count) |
| `fn_id` (CALL) | Local or imported function index | **Local:** [0, function_count) → 03 §6.1 (this module’s function table); code address = code section start + function_entry.code_offset. **Imported:** [function_count, function_count + imported_function_count) → 03 §6.6 (imported function table) yields (import_index, function_index); VM resolves module for import, then calls that function in that module. |
| `adt_id`, `ctor` (CONSTRUCT) | ADT index and constructor index | Section 6 (ADT table); constructor order = runtime tag. |
| `shape_id` (ALLOC_RECORD, SPREAD) | Shape table index | Section 5 (Shape table); [0, shape_count) |
| `slot` (GET_FIELD, SET_FIELD) | Field index within the record’s shape | Shape’s field order (03 §9) |
| `offset`, `handler_offset` | Byte offset within the code section (or within current function) | Code section (03 §7); see §4 |

The VM resolves `fn_id` to code address using the function table’s `code_offset` (relative to code section start). String table and type table are not used at runtime by the ISA; they are for compilation and tooling.

---

## 4. Instruction Encoding and Offsets

All multi-byte operands and offsets in the code section are **little-endian** (consistent with 03 §1).

**Offset base:** All jump and branch offsets are **signed 32-bit byte offsets** relative to the **first byte of the instruction** that contains the offset. So the target address = (address of that first byte) + offset. This applies to: `JUMP`, `JUMP_IF_FALSE`, `TRY` handler_offset, and each entry in the `MATCH` jump table. Using the instruction start as base ensures the same .kbc file is executed identically by every VM.

### 4.1 Opcode assignment

Each instruction has a single-byte opcode. Opcodes 0x00–0x1E are assigned as below; 0x1F–0xFF are reserved.

| Opcode | Instruction     | Operands (after opcode, in order) |
|--------|-----------------|------------------------------------|
| 0x01   | LOAD_CONST      | idx (u32) |
| 0x02   | LOAD_LOCAL      | idx (u32) |
| 0x03   | STORE_LOCAL     | idx (u32) |
| 0x04   | ADD             | (none) |
| 0x05   | SUB             | (none) |
| 0x06   | MUL             | (none) |
| 0x07   | DIV             | (none) |
| 0x08   | MOD             | (none) |
| 0x09   | POW             | (none) |
| 0x0A   | EQ              | (none) |
| 0x0B   | NE              | (none) |
| 0x0C   | LT              | (none) |
| 0x0D   | LE              | (none) |
| 0x0E   | GT              | (none) |
| 0x0F   | GE              | (none) |
| 0x10   | CALL            | fn_id (u32), arity (u32) |
| 0x11   | RET             | (none) |
| 0x12   | JUMP            | offset (i32) |
| 0x13   | JUMP_IF_FALSE   | offset (i32) |
| 0x14   | CONSTRUCT       | adt_id (u32), ctor (u32), arity (u32) |
| 0x15   | MATCH           | see §4.2 (jump table) |
| 0x16   | ALLOC_RECORD    | shape_id (u32) |
| 0x17   | GET_FIELD       | slot (u32) |
| 0x18   | SET_FIELD       | slot (u32) |
| 0x19   | SPREAD          | shape_id (u32) |
| 0x1A   | THROW           | (none) |
| 0x1B   | TRY             | handler_offset (i32) |
| 0x1C   | END_TRY         | (none) |
| 0x1D   | AWAIT           | (none) |
| 0x1E   | LOAD_GLOBAL     | idx (u32) |
| 0x1F   | STORE_GLOBAL    | idx (u32) |
| 0x20   | CALL_INDIRECT   | arity (u32) |
| 0x21   | LOAD_FN         | fn_index (u32) |
| 0x22   | MAKE_CLOSURE    | fn_index (u32) |
| 0x23   | LOAD_IMPORTED_FN | imported_fn_index (u32) |

**Reserved:** 0x00, 0x24–0xFF. Decoder must reject reserved or unknown opcodes.

### 4.2 MATCH instruction layout

`MATCH` pops one value (ADT or list), dispatches by runtime constructor tag to a target, and jumps there. The instruction layout is:

1. **Opcode:** 1 byte (0x15).
2. **count** (u32): number of cases (number of offsets in the jump table). Must equal the number of constructors for the ADT being matched (or the number of case arms the compiler emits); typically 1–255.
3. **Jump table:** `count` × **i32** (4 bytes each). Entry at index **k** is the byte offset (relative to the **first byte of this MATCH** opcode) to jump to when the popped value has constructor tag **k**. The VM computes: target_pc = (address of this MATCH’s opcode byte) + table[k].

So the total size of a MATCH instruction is **1 + 4 + 4×count** bytes. The next instruction follows immediately after the last i32 in the table. If the popped value’s tag is not in [0, count), behaviour is undefined (the type system and exhaustiveness ensure all tags are covered).

### 4.3 Instruction size summary

| Instruction       | Size (bytes) |
|-------------------|--------------|
| LOAD_CONST        | 1 + 4 = 5    |
| LOAD_LOCAL        | 1 + 4 = 5    |
| STORE_LOCAL       | 1 + 4 = 5    |
| LOAD_GLOBAL       | 1 + 4 = 5    |
| STORE_GLOBAL      | 1 + 4 = 5    |
| ADD, SUB, MUL, DIV, MOD, POW | 1 |
| EQ, NE, LT, LE, GT, GE       | 1 |
| CALL              | 1 + 4 + 4 = 9 |
| RET               | 1 |
| JUMP              | 1 + 4 = 5    |
| JUMP_IF_FALSE     | 1 + 4 = 5    |
| CONSTRUCT         | 1 + 4 + 4 + 4 = 13 |
| MATCH             | 1 + 4 + 4×count |
| ALLOC_RECORD      | 1 + 4 = 5    |
| GET_FIELD, SET_FIELD | 1 + 4 = 5  |
| SPREAD            | 1 + 4 = 5    |
| THROW, END_TRY, AWAIT | 1 |
| TRY               | 1 + 4 = 5    |
| CALL_INDIRECT     | 1 + 4 = 5    |
| LOAD_FN           | 1 + 4 = 5    |
| LOAD_IMPORTED_FN  | 1 + 4 = 5    |
| MAKE_CLOSURE      | 1 + 4 = 5    |

Instruction boundaries are thus deterministic: a decoder can always compute the start of the next instruction from the current opcode and operands.

---

## 5. Relation to Language (01) and Stdlib (02)

- **Literals and locals:** LOAD_CONST, LOAD_LOCAL, STORE_LOCAL cover literals and val/var (01 §3.2, §3.3).
- **Arithmetic and comparison:** ADD, SUB, MUL, DIV, MOD, POW and EQ, NE, LT, LE, GT, GE cover all arithmetic and comparison operators (01 §3.2).
- **Logic:** Short-circuit `&` and `|` are compiled using JUMP_IF_FALSE and JUMP (no AND/OR instructions).
- **If/else, match, try/catch:** JUMP, JUMP_IF_FALSE, MATCH, TRY, END_TRY (01 §3.2, §4).
- **Functions and calls:** CALL (function table index), RET (01 §3.1).
- **Lists and ADTs:** CONSTRUCT with list ADT and Nil/Cons (and Option, Result, Value from 02); MATCH for pattern matching on constructors and list patterns (01 §3.2, 02 List/Option/Result/Value).
- **Primitive literal match patterns:** For `Int`/`Float`/`String`/`Char`/`Unit` literal pattern chains, compilers emit sequential tests using `LOAD_LOCAL` (scrutinee), `LOAD_CONST` (literal), comparison (`EQ` or equivalent predicate), and `JUMP_IF_FALSE` to the next arm, with `JUMP` to the common end after a successful arm. ADT/list constructor matches continue to use `MATCH`.
- **Records and tuples:** ALLOC_RECORD, GET_FIELD, SET_FIELD, SPREAD (01 §3.2, §3.6). Tuples as records with positional shape.
- **Exceptions:** CONSTRUCT for exception payload, THROW, TRY/END_TRY (01 §4). Stack traces via stdlib (02 kestrel:stack).
- **Async:** AWAIT; async functions compiled to functions returning Task (01 §5, 02 Task<T>).

### 5.1 Anonymous functions and closures

The instruction set supports anonymous functions and closures via **LOAD_FN**, **MAKE_CLOSURE**, and **CALL_INDIRECT** (§1.10).

- **Non-capturing lambdas** (e.g. `(x, y) => x + y` with no free variables): The compiler assigns a function table entry (03 §6.1) and emits the lambda body. At the creation site it emits **LOAD_FN** `fn_index`, producing a **fn_ref** value. At call sites it emits **CALL_INDIRECT**; the VM calls the function with the given arity and pushes the return value.

- **Capturing lambdas and nested functions** (lambdas that capture variables from enclosing block or function scope): The compiler uses **closure conversion** (lambda lifting):
  - Compute the **free variables** of the lambda (01 §3.8). Build an **environment** record at the creation site: push each captured value in a fixed order, then **ALLOC_RECORD** with a shape that has one field per capture (and optionally a “self” slot for recursive nested fun). Then emit **MAKE_CLOSURE** `fn_index`, which pops the env and pushes a **closure value** (PTR to a CLOSURE heap object containing module_index, fn_index, env); see 05 §2.
  - Compile the lambda body as a **lifted function** whose first parameter is the environment (local 0); the body reads captures via **GET_FIELD** on that env. Add this function to the module’s function table.
  - At **call sites**, the callee is a value (either fn_ref or closure). The compiler emits **CALL_INDIRECT** `arity`. The VM pops the callee and the arguments; if the callee is a CLOSURE, it pushes the env as the first argument and CALLs the lifted function with arity 1 + `arity`.

First-class closures (e.g. passing a lambda to a higher-order function) are thus supported: the closure value is either a fn_ref (no env) or a CLOSURE object (env + function index), and **CALL_INDIRECT** handles both.

---

## 6. Execution Efficiency

- **Constant pool:** All literal loads go through LOAD_CONST; the constant pool (03 §5) avoids embedding large immediates in the instruction stream and allows deduplication.
- **Direct indices:** CALL, CONSTRUCT, ALLOC_RECORD, SPREAD use direct table indices (function, ADT, shape) so the VM does a single table lookup to get code address or layout.
- **Byte offsets:** Fixed byte-offset jumps allow compact relative branches (e.g. 16-bit signed offset from current PC) and deterministic interpretation.
- **Stack discipline:** Single stack for operands and clear call convention minimize register pressure and keep the VM simple.
- **No redundant work:** Comparison and arithmetic are single-pop/push; MATCH is a single dispatch. No hidden allocations except where the runtime model requires (e.g. boxed Float, heap records).

For float literal patterns, NaN is a special case: a NaN pattern must match NaN scrutinee values even though plain equality treats NaN as unequal to itself. Backends may implement this with a dedicated float-NaN predicate path instead of `EQ`.

---

## 7. Built-in primitive `CALL` ids (0xFFFFFF00 range)

When **`fn_id`** in **CALL** is in **`0xFFFFFF00` … `0xFFFFFF25`** (inclusive), the VM treats the call as a **host primitive** rather than a function-table index. Arity and behaviour are fixed per id. (Existing ids `0xFFFFFF00`–`0xFFFFFF1B` cover I/O, strings, process, etc.; the reference VM extends the range through **`0xFFFFFF25`**.)

| `fn_id` | Builtin (compiler name) | Arity | Result (summary) |
|---------|-------------------------|-------|------------------|
| `0xFFFFFF1C` | `__int_to_float` | 1 | `(Int) -> Float` (boxed float) |
| `0xFFFFFF1D` | `__float_to_int` | 1 | `(Float) -> Int` (truncate toward zero) |
| `0xFFFFFF1E` | `__float_floor` | 1 | `(Float) -> Int` |
| `0xFFFFFF1F` | `__float_ceil` | 1 | `(Float) -> Int` |
| `0xFFFFFF20` | `__float_round` | 1 | `(Float) -> Int` (IEEE round, ties to even) |
| `0xFFFFFF21` | `__float_sqrt` | 1 | `(Float) -> Float` |
| `0xFFFFFF22` | `__float_is_nan` | 1 | `(Float) -> Bool` |
| `0xFFFFFF23` | `__float_is_infinite` | 1 | `(Float) -> Bool` |
| `0xFFFFFF24` | `__float_abs` | 1 | `(Float) -> Float` |
| `0xFFFFFF25` | `__char_from_code` | 1 | `(Int) -> Char` (invalid / surrogate → `U+0000`) |

The JVM backend maps these to `KRuntime` static methods with the same semantics.

---

## 8. Relation to Other Specs

- Bytecode file layout and sections: [03-bytecode-format.md](03-bytecode-format.md)
- Runtime representation of values (tagged words, heap objects): [05-runtime-model.md](05-runtime-model.md)
- Type system and inference: [06-typesystem.md](06-typesystem.md)
