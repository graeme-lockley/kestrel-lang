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

**Language coverage:** Literals (Int, Float, Bool, Unit, Char, String), `val`/`var` bindings, parameters.

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

**Language coverage:** Record literals `{ x = e, y = f }`, field access `e.x`, mutable field assignment `r.x := e` (01 §3.6). Tuples `(a, b)` may be compiled as records with an anonymous shape (field indices 0, 1, …).

### 1.9 Exceptions and Async

| Instruction | Operands | Effect |
|-------------|----------|--------|
| `THROW` | — | Pop exception value and throw (unwind to nearest handler). |
| `TRY` | `handler_offset` (byte offset) | Push try scope; on throw, jump to handler at `handler_offset`. |
| `END_TRY` | — | Pop try scope (reached when try block completes normally). |
| `AWAIT` | — | Pop `Task<T>`; if complete, push result; else suspend current frame (01 §5). |

**Language coverage:** `throw e`, `try { ... } catch (e) { ... }`, `await e`.

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

**Reserved:** 0x00, 0x1E–0xFF. Decoder must reject reserved or unknown opcodes.

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

Instruction boundaries are thus deterministic: a decoder can always compute the start of the next instruction from the current opcode and operands.

---

## 5. Relation to Language (01) and Stdlib (02)

- **Literals and locals:** LOAD_CONST, LOAD_LOCAL, STORE_LOCAL cover literals and val/var (01 §3.2, §3.3).
- **Arithmetic and comparison:** ADD, SUB, MUL, DIV, MOD, POW and EQ, NE, LT, LE, GT, GE cover all arithmetic and comparison operators (01 §3.2).
- **Logic:** Short-circuit `&` and `|` are compiled using JUMP_IF_FALSE and JUMP (no AND/OR instructions).
- **If/else, match, try/catch:** JUMP, JUMP_IF_FALSE, MATCH, TRY, END_TRY (01 §3.2, §4).
- **Functions and calls:** CALL (function table index), RET (01 §3.1).
- **Lists and ADTs:** CONSTRUCT with list ADT and Nil/Cons (and Option, Result, Value from 02); MATCH for pattern matching on constructors and list patterns (01 §3.2, 02 List/Option/Result/Value).
- **Records and tuples:** ALLOC_RECORD, GET_FIELD, SET_FIELD, SPREAD (01 §3.2, §3.6). Tuples as records with positional shape.
- **Exceptions:** CONSTRUCT for exception payload, THROW, TRY/END_TRY (01 §4). Stack traces via stdlib (02 kestrel:stack).
- **Async:** AWAIT; async functions compiled to functions returning Task (01 §5, 02 Task<T>).

### 5.1 Anonymous functions and closures

The instruction set **is sufficient** for both anonymous functions and closures; no dedicated closure instructions (e.g. MAKE_CLOSURE, CALL_CLOSURE) are required.

- **Anonymous functions without capture** (e.g. `(x, y) => x + y`): The compiler assigns a function table entry (03 §6.1) and emits a normal function body. Calls use **CALL** with that function index. The function has no name in source but is a normal entry in the function table.

- **Closures** (lambdas that capture variables from an enclosing scope): The compiler uses **closure conversion** (lambda lifting):
  - Allocate an **environment**: a record (or tuple) holding the captured values, built with **ALLOC_RECORD** and stores/pushes at the point where the closure is created.
  - Compile the lambda body as a **top-level function** whose first parameter (or a dedicated parameter block) is the environment; it reads captures via **GET_FIELD** (or LOAD_LOCAL for the env parameter).
  - At every **call site** of the closure: push the environment (the record), then the normal arguments, then **CALL** the lifted function with arity = 1 + number of lambda parameters. The closure value at runtime can be represented as the environment record only; the call site knows the lifted function index at compile time.

So first-class closures (e.g. passing a lambda to `createServer`) are supported using existing instructions: **CALL**, **ALLOC_RECORD**, **GET_FIELD**, **LOAD_LOCAL**, **STORE_LOCAL**. No additional opcodes are needed. A future extension could add MAKE_CLOSURE / CALL_CLOSURE for a single heap-allocated closure value and one indirect call, but it would be an optimization, not a requirement for correctness.

---

## 6. Execution Efficiency

- **Constant pool:** All literal loads go through LOAD_CONST; the constant pool (03 §5) avoids embedding large immediates in the instruction stream and allows deduplication.
- **Direct indices:** CALL, CONSTRUCT, ALLOC_RECORD, SPREAD use direct table indices (function, ADT, shape) so the VM does a single table lookup to get code address or layout.
- **Byte offsets:** Fixed byte-offset jumps allow compact relative branches (e.g. 16-bit signed offset from current PC) and deterministic interpretation.
- **Stack discipline:** Single stack for operands and clear call convention minimize register pressure and keep the VM simple.
- **No redundant work:** Comparison and arithmetic are single-pop/push; MATCH is a single dispatch. No hidden allocations except where the runtime model requires (e.g. boxed Float, heap records).

---

## 7. Relation to Other Specs

- Bytecode file layout and sections: [03-bytecode-format.md](03-bytecode-format.md)
- Runtime representation of values (tagged words, heap objects): [05-runtime-model.md](05-runtime-model.md)
- Type system and inference: [06-typesystem.md](06-typesystem.md)
