# 05 – Runtime Value and Heap Model

Version: 1.0

---

This document describes how the Kestrel VM represents values at runtime. It must align with the types and literals in [01-language.md](01-language.md), the standard types in [02-stdlib.md](02-stdlib.md), the bytecode layout in [03-bytecode-format.md](03-bytecode-format.md), and the instructions in [04-bytecode-isa.md](04-bytecode-isa.md). The reference implementation is in Zig; the model may be adapted for other hosts as long as the semantics in 04 and the type system in [06-typesystem.md](06-typesystem.md) are preserved.

---

## 1. Tagged Value (Stack and Local Representation)

Values that fit in a single **64-bit word** are represented as **tagged values**. **Three bits** of the word are used for the tag; the remaining **61 bits** hold the payload where possible. This allows most scalar values to be stored inline without heap allocation.

**Tag enumeration (3 bits; 8 values):** At least the following are required. Exact encoding (which bit pattern corresponds to which tag) is implementation-defined.

| Tag   | Description | Payload | Inline |
|-------|-------------|---------|--------|
| **INT**  | 61-bit signed integer (01 §2.6) | Signed integer in remaining 61 bits. **Overflow:** arithmetic that overflows 61-bit range must throw (e.g. an exception or VM trap) so the program cannot observe undefined behaviour. | Yes |
| **BOOL** | Boolean True / False (01 §2.10) | Encoded in tag or payload (e.g. two tag values or one bit in payload) | Yes |
| **UNIT** | Unit value `()` (01 §2.10) | No payload | Yes |
| **CHAR** | Character / rune (01 §2.9, 3.6: Char, Rune) | Unicode code point (e.g. 32 bits in payload; 61 bits sufficient) | Yes |
| **PTR**  | Pointer to a heap object | Heap address in payload (e.g. 61 bits; alignment allows low bits to be zero) | Yes (the word is the pointer) |

- **FLOAT** is **not** stored inline: a 64-bit IEEE 754 double requires the full word for the value. **Float is always boxed** — the VM allocates a heap object of kind FLOAT and the tagged value is **PTR** to that object (01 §2.7, 03 constant pool tag 1).
- **STRING** literals and values are heap-allocated (kind STRING); the tagged value is **PTR** to that object. The constant pool (03 §5) holds string table indices; at runtime, loading a string constant yields a PTR to a STRING heap object (interned or created at load time).

Tag and payload layout for inline values (e.g. how INT/BOOL/UNIT/CHAR use the 61 bits, and how PTR encodes the address) is implementation-defined. The VM must distinguish all tags so that type-safe operation (e.g. ADD pops two INT, EQ compares compatible types) is preserved.

**Implementor notes:** At least five tag values are needed (INT, BOOL, UNIT, CHAR, PTR). FLOAT and STRING are represented as PTR to heap objects. Common choices: use the low 3 bits of the word for the tag and the high 61 bits for the payload; or use NaN boxing (float bit pattern in 64 bits, pointers in 48-bit space with tag bits). Heap pointers in PTR must be **aligned** (e.g. 4- or 8-byte) so the low bits are zero; the VM may use those bits for tagging. All heap object addresses must be traceable by the GC (§4).

---

## 2. Heap Object Kinds

Objects referenced by **PTR** are allocated on the heap and have one of the following **kinds**. The GC (§3) traces all reachable heap objects.

| Kind     | Description | Created by (04) | References |
|----------|-------------|------------------|------------|
| **FLOAT**  | Boxed 64-bit IEEE 754 double (Float cannot fit in the tagged word) | LOAD_CONST (constant pool Float → allocates FLOAT); arithmetic that produces Float | 01 §2.7, 03 §5 |
| **STRING** | UTF-8 byte sequence; length and exact layout implementation-defined | LOAD_CONST (string constant); string operations; interpolation (01 §2.8) | 03 §0, §5 |
| **ARRAY**  | Runtime built-in: contiguous elements, length; element type fixed per array (`Array<T>`, 01 §3.6) | Implementation-defined (e.g. VM intrinsic or stdlib); no instruction in 04 | 01, 02 |
| **RECORD** | Structural record: shape identifier plus array of field slots (tagged values). Field order matches the shape table (03 §9). Used for record literals, tuples (anonymous shape), **closure environments**, and **stdlib dictionary values** (`kestrel:dict` / `kestrel:set`: at runtime a RECORD holding `hash`, `eq`, and `entries` in that order — not a separate heap kind). In source code, `Dict<K, V>` and `Set<E>` (kestrel:set; opaque alias of `Dict<E, Unit>`) are **opaque** exported types in the stdlib contract ([02-stdlib.md](02-stdlib.md)); that opacity is a module-boundary / typing rule, not a different heap representation. | ALLOC_RECORD, SPREAD (04 §1.8) | 03 §9, 04 §1.8, §5.1 |
| **ADT**    | Algebraic data type: constructor tag (0-based within the ADT) plus payload (fixed number of fields, or none). Tag and shape match the ADT table (03 §10). Covers List (Nil, Cons), Option, Result, Value, and **exception values**. | CONSTRUCT (04 §1.7) | 03 §10, 04 §1.7, 02 |
| **TASK**   | Async computation: suspended continuation, or completed result. Corresponds to `Task<T>` (01 §5, 02). | Async function call; AWAIT consumes it (04 §1.9) | 01 §5, 04 AWAIT |
| **CLOSURE** | Capturing lambda or nested function: (module_index, function_index, env). **env** is PTR to a RECORD holding captured values. | MAKE_CLOSURE (04 §1.10) | 01 §3.8, 04 §5.1 |

A one-field RECORD may be used as a **mutable cell** for by-reference capture of `var` (01 §3.8): both the closure and the enclosing scope refer to the same record, and assignments update the single field.

**Closures (04 §5.1):** A **closure value** is either (1) a **fn_ref** (tagged value: module_index + function_index) for non-capturing lambdas, or (2) a **PTR** to a **CLOSURE** heap object for capturing lambdas. The CLOSURE object stores (module_index, function_index, env); the GC must trace **env** (the RECORD) so that captured values remain live. CALL_INDIRECT (04 §1.10) accepts either: for fn_ref it calls the function directly; for CLOSURE it pushes env as the first argument and calls the lifted function with arity 1 + n.

**Implementor notes — heap object header:** Every heap object must have a **header** that identifies its **kind** (FLOAT, STRING, ARRAY, RECORD, ADT, TASK, CLOSURE) so the GC and the VM can interpret the rest of the object. Kind-specific layout: **RECORD** stores module index, shape_id, and field count, then N tagged values (field slots in shape order). **ADT** stores module index, adt_id, constructor tag (0-based), arity, then payload slots (0 or more tagged values). **TASK** stores state (suspended vs completed) and either continuation data or the result value. **CLOSURE** stores kind, mark, then module_index (u32), function_index (u32), and env (PTR to RECORD); the GC traces env. **STRING** and **FLOAT** store only the payload (bytes or f64). **ARRAY** stores length and element slots. Exact header size and alignment are implementation-defined; the GC must be able to skip or trace every object given its kind. The loader resolves shape field names and ADT/constructor names (string table indices in sections 5 and 6) for human-readable output (e.g. print/format).

---

## 3. Record Mutation (SET_FIELD)

For a record with **mut** fields (01 §3.6), **SET_FIELD** (04 §1.8) mutates the field in place. After SET_FIELD, the VM may either (a) leave the **updated record** on the stack (same PTR, mutated object), or (b) leave **unit** on the stack. Both semantics are valid; the compiler must not rely on the record remaining on the stack. The important guarantee is that the heap object is updated so that subsequent GET_FIELD or use of that record sees the new value.

---

## 4. Garbage Collection

- **v1:** A **mark-sweep** (or equivalent) collector is required. All heap objects are GC-managed.
- **Roots:** The collector must treat as roots: the **operand stack**, all **local slots** of every active frame, and any **global or static** references (e.g. module-level data). No reference to a heap object may be stored in a place invisible to the GC (e.g. raw pointers in C that the collector does not trace).
- **Safety:** The VM must ensure that a heap object is not freed while any tagged value (on the stack, in a local, or in another heap object) still holds a PTR to it.

**Implementor note (mark phase):** The constant pool may hold **PTR** to loader-allocated string/float blobs that share the same header layout as GC heap objects but are **not** managed by the collector. Roots may therefore contain **PTR** values that do not refer to GC object starts. The mark phase must only treat an address as a GC object header if it is a **known GC allocation**; it must **bound** RECORD field walks and ADT payload walks by the object’s allocation size. Otherwise an interior pointer, or a constant-pool address mis-read as RECORD/ADT (bogus `field_count` / `arity`), can walk arbitrary memory and crash.

---

## 5. Exception Handling (Throw / Try-Catch)

Exceptions (01 §4) are **values**: they are **ADT** heap objects (constructor tag and optional payload, per 03 §10 exported exceptions). **THROW** (04) pops that value and **unwinds** the stack: the VM pops frames until it reaches a **TRY** scope, then jumps to the handler at the associated `handler_offset`. The exception value is made available to the handler (e.g. in a local slot or on the stack) so that pattern matching in the catch block can inspect it. **END_TRY** is reached when the try block completes normally and pops the try scope.

**Stack traces:** The stdlib (02 kestrel:stack) provides `trace` to obtain a `StackTrace<T>` for a thrown value. The runtime may capture a backtrace at throw time (list of (module, function, code offset) or similar) and attach it to the exception or provide it when `trace` is called; the exact mechanism is implementation-defined. Debug section (03 §8) maps code offsets to (file, line) for human-readable stack traces. A **conforming** implementation must provide some representation of the call stack (e.g. sequence of (module, function, code offset) or (file, line)) when `Stack.trace` is used, so that stack traces are observable as specified in 02; when the debug section is present, file and line information must be derived from it. On an **uncaught exception**, the VM must print the exception value and a stack trace (one ` at file:line` per frame) to stderr using the debug section, then exit with a non-zero status.

---

## 6. Task and Async Runtime

**TASK** heap objects represent an async computation (01 §5, 02 Task<T>). A task is either **suspended** (not yet complete; may hold a continuation: saved frame, PC, and any scheduler handle) or **completed** (holds the result value of type T). **AWAIT** (04): pop the TASK; if completed, push the result; if suspended, suspend the current frame and (when the task completes) the runtime will resume appropriately. Task scheduling (which suspended task runs when) is implementation-defined. The VM must preserve the single-threaded semantics of the language: only one frame executes at a time unless the implementation explicitly defines concurrency.

**Node-style async I/O:** This model supports **non-blocking, event-loop-driven I/O** as in Node.js or libuv. When an async function performs I/O (e.g. via stdlib `readText`, `get`, `listen`), the runtime can create a TASK that stays suspended until the OS or I/O layer signals completion. The main thread never blocks: it can run other ready tasks or the event loop. When the I/O completes, the runtime marks the TASK completed and resumes the suspended frame. Implementations may use an event loop, thread pool, or other mechanism to integrate with non-blocking I/O; the spec only requires suspend/resume and single-threaded execution of frames.

---

## 7. Relation to Other Specs

| Spec | Relation |
|------|----------|
| **01** | Int (61-bit), Float (boxed), Bool, Unit, Char/Rune (inline), String (heap); records, ADTs, Task, exceptions (ADT values). |
| **02** | Option, Result, List, Value are ADT heap objects; Task is TASK heap object; StackTrace from kestrel:stack. |
| **03** | Constant pool tags (Int, Float, Bool, Unit, Char, String) map to tagged or heap representation; shape table defines RECORD layout; ADT table defines constructor tags and payload; debug section for stack trace mapping. |
| **04** | LOAD_CONST → tagged or PTR; ALLOC_RECORD / GET_FIELD / SET_FIELD / SPREAD → RECORD; CONSTRUCT / MATCH → ADT; THROW / TRY / END_TRY → exception unwind; AWAIT → TASK. Closures use RECORD (env) per closure conversion. |
| **06** | Type system constrains which values may appear where; runtime does not re-check types but must preserve type safety. |

---

## 8. Language Feature Coverage

The following language and stdlib features have runtime representation or behaviour defined in this document. Implementors must support all of them.

| Feature | Section(s) in this doc | Notes |
|---------|------------------------|--------|
| **Literals** (Int, Float, Bool, Unit, Char, String) | §1, §2 | Int 61-bit inline; Float boxed; Bool, Unit, Char inline; String heap. |
| **Records** (structural, mut fields) | §2 RECORD, §3 | Shape-defined layout; SET_FIELD for mut. |
| **Tuples** | §2 RECORD | Anonymous shape, field order 0,1,…; `match` tuple patterns project the same indices as field access `.0`, `.1`, … (01 §3.4). |
| **ADTs** (Option, Result, List, Value, exceptions) | §2 ADT | Constructor tag + payload; exceptions are ADTs. |
| **Exceptions** (throw, try/catch) | §2 ADT, §5 | Exception value = ADT; unwind to TRY handler; stack trace via stdlib. |
| **Task / async / await** | §2 TASK, §6 | TASK heap object; AWAIT semantics; scheduling impl-defined. |
| **Closures / lambdas** | §2 RECORD, CLOSURE; tagged fn_ref | Non-capturing: fn_ref. Capturing: CLOSURE (env + function index). |
| **Array\<T\>** | §2 ARRAY | Built-in; creation/access impl-defined or stdlib. |
| **GC and roots** | §4 | Mark-sweep; stack, locals, globals as roots. |

**Signals:** The Kestrel language spec (01) and stdlib (02) do not define OS signals or a “signals” feature. If such a feature is added in a future revision, the runtime model would be extended (e.g. signal handlers as special frames or task-like objects). For the current version, no signal-specific representation is required.

---

## 9. Implementor Summary

An implementation of the runtime model must provide:

1. **Tagged word (64-bit):** A mapping from each of INT, BOOL, UNIT, CHAR, PTR to a 3-bit tag (or equivalent) and a payload layout; FLOAT and STRING represented as PTR. Operations in 04 (e.g. ADD, EQ, GET_FIELD) interpret the tag to dispatch or type-check.
2. **Heap:** Allocations for FLOAT, STRING, ARRAY, RECORD, ADT, TASK (and optionally CLOSURE), each with a header encoding **kind** and kind-specific payload (see §2).
3. **GC:** A mark-sweep (or equivalent) collector with roots = operand stack + local slots of all active frames + globals/statics; all heap objects traceable from roots.
4. **Exceptions:** On THROW, unwind stack to the nearest TRY, deliver the exception value (ADT) to the handler; optional backtrace for StackTrace (02 kestrel:stack) and debug mapping (03 §8).
5. **Tasks:** TASK objects with state (suspended vs completed); AWAIT pops a TASK and either pushes the result or suspends the current frame; scheduling policy is implementation-defined.
6. **Record mutation:** SET_FIELD updates the RECORD in place for `mut` fields; result may be updated record or unit (§3).

Pattern-match literal chains (01 match, 04 lowering) rely on runtime value comparison for Int/String/Char/Unit. Float literal patterns additionally require NaN-aware matching semantics (NaN pattern matches NaN scrutinee) via a predicate path rather than plain equality.
