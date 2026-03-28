# 03 – Bytecode Format (.kbc)

Version: 1.0

---

Kestrel compiles to a bytecode file with extension `.kbc`. **One `.kbc` file represents one module** (one compilation unit). This document specifies the exact file layout and section format so that all implementations produce and consume identical binaries. A module may have an associated **types file** (07 §5) used at compile time only; the .kbc file is the only artifact used at runtime.

---

## 0. References by Offset; No Name-Based Resolution

All references to **variables**, **constants**, and **functions** in the bytecode are by **index or offset**, not by name. Name-based lookup is slow and must not be used for execution.

- **Constants:** Instructions (e.g. LOAD_CONST, 04 §1.1) refer to the **constant pool** by **index** (§5).
- **Functions:** The CALL instruction (04 §1.5) takes a single **function index** operand. That index is either **local** ([0, function_count) → this module’s function table §6.1) or **imported** ([function_count, function_count + imported_function_count) → §6.6 imported function table, which yields (import_index, function_index in that module). No package or name is encoded in the instruction; the package is determined by the imported function table (§6.6).
- **Locals:** LOAD_LOCAL / STORE_LOCAL (04 §1.1) use **slot indices**.
- **Types, shapes, ADTs:** The type table (§6.2), shape table (§9), and ADT table (§10) are referenced by **type_index**, **shape_index**, and **adt_index**.

**Name tables** (e.g. string table for function names in §6.1 `name_index`) exist for **debugging, reflection, and tooling** only. They must **not** be used for resolving references at load time or at runtime. The VM and loader resolve all references using only indices and offsets from the binary. Cross-module references are obtained at compile time from the dependency’s **types file** (07 §5), which supplies the offsets so the caller emits static indices.

---

## 1. Endianness and Alignment

- All multi-byte integers are **little-endian**.
- **All sections and multi-byte fields are 4-byte aligned.** Section content starts at the byte offset given in the header; padding may be inserted so that the next section or the next field respects alignment. Implementations must use 4-byte alignment throughout.

---

## 2. File Header

The file begins with a fixed header:

| Field | Type | Description |
|-------|------|-------------|
| `magic` | 4 bytes | Literal `KBC1` (0x4B 0x42 0x43 0x31) |
| `version` | u32 | Bytecode format version (1 for v1). Increment for any format change; VM must reject unknown version. |
| `section_offsets` | u32 × N | One offset per section; offset is byte offset from start of file. For v1, N = 7. |

Header size: 4 + 4 + 7×4 = **36 bytes**. The first section starts at `section_offsets[0]`.

**Entry point:** The **code section** is at index 3. The byte offset `section_offsets[3]` is the **module execution entry point**: execution begins at the first byte of the code section. This is the module initializer (top-level statements). If the module has no code to execute, the compiler must place a single **RET** instruction at that offset so that the code section is valid.

---

## 3. Sections (Order and Purpose)

Sections appear in the order listed. Each section starts at the byte offset given in the header. Section end is the start of the next section (or end of file for the last section). All indices used in the file (string, constant, function, type, shape, ADT) are **u32** and 0-based.

| Index | Section | Purpose |
|-------|---------|---------|
| 0 | String table | **Only** store of string data (literals and symbol names); every string reference elsewhere is a u32 index into this table. |
| 1 | Constant pool | **Only** store of loadable scalar constants (Int, Float, Bool, Unit, Char, string-by-index); code refers to constants by pool index. |
| 2 | Function table | **Only** store of module metadata: function entries, type table, exported type aliases, import table. Required for dependency resolution and type/symbol resolution without recompiling. |
| 3 | Code section | **Only** store of executable bytecode; first byte is the module entry point. |
| 4 | Debug section | **Only** store of code-offset → (file, line) mapping for stack traces. Same layout always; may be zero-sized or empty when built without debug. |
| 5 | Shape table | **Only** store of record shapes (field names and types); type table references shapes here by index (Record tag). |
| 6 | ADT table | **Only** store of ADT definitions (type name, constructors, payload types); type table references ADTs here by index (ADT tag). |

Index validity: string table indices in [0, string_table_count); constant pool indices in [0, constant_pool_count); function table indices (local) in [0, function_count); **CALL fn_id** (04) may be in [0, function_count + imported_function_count) — local calls use [0, function_count), cross-package calls use [function_count, function_count + imported_function_count) and resolve via §6.6; type_index in [0, type_count); shape_index (Record tag) in [0, shape_count); adt_index (ADT tag) in [0, adt_count). Each kind of data lives in exactly one section (no duplication).

**Determining module dependencies:** A module’s imports are recorded **only** in the **import table** (§6.5), which is a subsection of section 2. There is **no dedicated section** and **no header offset** for dependencies. To obtain the list of modules this file imports from: (1) start at `section_offsets[2]`; (2) parse section 2 in fixed order — n_globals (u32), then 6.1 Function table, 6.2 Type table, 6.4 Exported type declarations, 6.5 Import table, 6.6 Imported function table — skipping or decoding each subsection until you reach 6.5; (3) read `import_count` (u32) then `import_count` × u32; each u32 is a string table index whose value is the import source (e.g. `"kestrel:string"`). Resolve each index in the string table (section 0) to get the dependency list.

---

## 4. Section 0: String Table

**Purpose:** Single store for every string used in the module (literals and symbol names); all other sections refer to strings by index.

- **Encoding:** UTF-8 only.
- **Layout:**
  - `count` (u32): number of strings.
  - For each string index `i` in `0 .. count`, one **length-prefixed** entry:
    - `length` (u32): number of bytes in the UTF-8 encoding (no null terminator). The **start** of this u32 must be 4-byte aligned within the section.
    - `bytes` (length bytes): the UTF-8 bytes immediately after `length` (no padding between length and bytes).
    - After the last byte of `bytes`, pad with 0–3 bytes so that the **next** entry’s `length` (if any) is 4-byte aligned.
- String index `i` is the `i`-th entry (0-based). To resolve index `i`: start at byte offset 4 (after `count`); for each j in 0..i-1, read `length`, skip that many bytes, then advance to the next 4-byte boundary; then read `length` and `bytes` for the `i`-th string.

---

## 5. Section 1: Constant Pool

**Purpose:** Holds every scalar constant value (numbers, booleans, unit, chars, string references) that instructions can load; one index space for “constant *i*” regardless of kind.

- **Layout:**
  - `count` (u32): number of constant entries.
  - Then `count` entries in order. Constant index `i` is the `i`-th entry (0-based). There is **no offset table**; to locate constant `i`, the decoder must walk the sequence from the start, so decoding by index is **O(i)**. Implementations may build an in-memory index when loading the module. (The writer may compute and store offsets elsewhere; the file format does not prescribe that.)
  - Each entry:
    - `tag` (u8): constant kind (see table below).
    - 3 bytes padding so that the **payload** starts at the next 4-byte boundary.
    - `payload`: as defined per tag. The **next** entry starts at the next 4-byte boundary after the payload (i.e. total entry size is 4 + payload_len rounded up to a multiple of 4).

**Constant tags and payloads:**

| Tag | Name   | Payload size | Payload description |
|-----|--------|--------------|----------------------|
| 0   | Int    | 8 bytes      | i64 (61-bit value stored in 64 bits; see [05-runtime-model.md](05-runtime-model.md)) |
| 1   | Float  | 8 bytes      | IEEE 754 double (f64) |
| 2   | False  | 0 bytes      | Boolean false (no payload) |
| 3   | True   | 0 bytes      | Boolean true (no payload) |
| 4   | Unit   | 0 bytes      | No payload |
| 5   | Char   | 4 bytes      | u32 (Unicode code point) |
| 6   | String | 4 bytes      | u32 index into string table (section 0) |

**Reserved tags:** 7–255 reserved for future use.

**Entry size summary:** Int=12 (1+3+8), Float=12, False=4, True=4, Unit=4, Char=8 (1+3+4), String=8 (1+3+4). Each entry is padded so the next entry starts on a 4-byte boundary.

---

## 6. Section 2: Function Table and Type Table

**Purpose:** Holds all module-level metadata: function entries, type table, exported type aliases, import table, and imported function table (for cross-package calls). Subsection **layout** order is fixed: 6.1 Function table → 6.2 Type table (offsets + type blob; blob content format is 6.3) → 6.4 Exported type declarations → 6.5 Import table → 6.6 Imported function table. Each subsection starts at the next 4-byte-aligned offset after the previous one.

**Skip distances (to reach import table without decoding type blob):** Let `S2` = start of section 2 (byte at `section_offsets[2]`). Section 2 begins with `n_globals` (u32) then the function table (6.1). To jump to the start of the import table (6.5):

1. **After 6.1:** `S2 + 8 + function_count×24` (4-byte aligned). Read `type_count` (u32) at this offset.
2. **After 6.2:** At offset `S2 + 8 + function_count×24`, read `type_count` (u32). The type table is: 4 bytes (type_count) + (type_count+1)×4 bytes (offsets) + `offsets[type_count]` bytes (blob). Skip to next 4-byte boundary after the blob:  
   `skip_6_2 = 4 + (type_count+1)*4 + blob_len`, then `pad = (4 - (skip_6_2 mod 4)) mod 4`. Start of 6.4 = `S2 + 8 + function_count×24 + skip_6_2 + pad`.
3. **After 6.4:** At start of 6.4, read `exported_type_count` (u32). Skip 4 + exported_type_count×8 bytes. Start of 6.5 = start of 6.4 + 4 + exported_type_count×8.

So: **start of 6.5** = `S2 + 8 + function_count×24 + skip_6_2 + pad + 4 + exported_type_count×8`, where `blob_len = offsets[type_count]` (read from the four bytes at `S2 + 8 + function_count×24 + 4 + type_count×4`), `skip_6_2 = 4 + (type_count+1)*4 + blob_len`, and `pad = (4 - (skip_6_2 mod 4)) mod 4`.

### 6.1 Function table

Section 2 starts with:

- `n_globals` (u32): number of module-level global variable slots allocated for the module initializer. Used for `export val` and `export var` (LOAD_GLOBAL / STORE_GLOBAL). When 0, the module has no globals.
- `function_count` (u32).
- Then `function_count` entries, each **24 bytes** (6 × u32), 4-byte aligned. **Calls and other references use the function table index only;** name lookups are not used for execution (§0).

| Offset in entry | Type | Field | Description |
|-----------------|------|--------|-------------|
| 0  | u32 | name_index | String table index of function name (for debug/reflection only; not used for call resolution) |
| 4  | u32 | arity | Number of parameters |
| 8  | u32 | code_offset | Byte offset of first instruction **relative to start of code section** (section 3) |
| 12 | u32 | flags | Bit 0 = async (1 if async, 0 otherwise); bits 1–31 reserved (0) |
| 16 | u32 | _reserved | Must be 0 |
| 20 | u32 | type_index | Index into the type table below (signature of this function: params + return) |

### 6.2 Type table

At the next 4-byte-aligned offset after the function table (6.1):

- `type_count` (u32): number of type encodings.
- `offsets` (u32 × (type_count + 1)): byte offsets **relative to the first byte of the type blob**. `offsets[i]` is the start of type encoding `i`; `offsets[type_count]` is the byte length of the blob. Length of encoding `i` is `offsets[i+1] - offsets[i]`.
- `type_blob` (bytes): concatenated type encodings (see 6.3). Type index `i` is the bytes in the blob from `offsets[i]` to `offsets[i+1]` (exclusive). The blob length is exactly `offsets[type_count]` bytes. After the blob, insert 0–3 bytes of padding so that the next subsection (6.4) starts at a 4-byte-aligned offset.

Function table entries, shape table, and ADT table refer to types via this **type_index** (u32). Type indices are 0-based and must be in **[0, type_count)**. All such references are into this type table only.

### 6.3 Type encoding (type blob)

Each type in the blob is encoded as a tag byte followed by a payload. All multi-byte values in the payload are u32 little-endian. The encoding is recursive (types may refer to other types by index).

| Tag | Name    | Payload |
|-----|---------|---------|
| 0   | Int     | (none) |
| 1   | Float   | (none) |
| 2   | Bool    | (none) |
| 3   | Unit    | (none) |
| 4   | String  | (none) |
| 5   | Char    | (none) |
| 6   | Arrow   | n_params (u32), then n_params × type_index (u32), then return type_index (u32) |
| 7   | Record  | shape_index (u32) into shape table (section 5) |
| 8   | ADT     | adt_index (u32), n_type_params (u32), then n_type_params × type_index (u32) |
| 9   | Option  | type_index (u32) |
| 10  | List    | type_index (u32) |
| 11  | TypeVar | index (u32) — for polymorphic type variables |

**Reserved tags:** 12–255. Decoder must reject unknown type tags.

Type indices inside the blob refer to other entries in the **same** type table (0-based; index < type_count). Arrow: parameter types first, then return type. Record refers to shape table (section 5). ADT refers to ADT table (section 6) and supplies type arguments. Library types with multiple type parameters (e.g. **Result\<T, E\>** from 02) are encoded as **ADT** (tag 8) with the appropriate adt_index and the corresponding number of type_index arguments (e.g. two for Result); there is no separate Result tag in the type blob.

### 6.4 Exported type declarations

At the next 4-byte-aligned offset after the type blob (6.2):

- `exported_type_count` (u32): number of exported type aliases (e.g. `export type Foo = Bar`).
- Then `exported_type_count` pairs, each 8 bytes (2 × u32), 4-byte aligned:
  - `name_index` (u32): string table index of the exported type name.
  - `type_index` (u32): type table index of the type it refers to (right-hand side of the alias).

Only **exported** type aliases are listed. ADT and record definitions are in the ADT and shape tables; this table is only for alias names so that importing modules can resolve them without recompiling.

### 6.5 Import table

**This is the only place in the .kbc file that records the module’s imports.** There is no dedicated section index for dependencies and no dependency offset in the header; the compiler or loader must parse section 2 in order (6.1 → 6.2 → 6.4 → 6.5 → 6.6) to reach the import table and the imported function table.

At the next 4-byte-aligned offset after the exported type declarations (6.4):

- `import_count` (u32): number of modules this file depends on at the specifier level (one entry per **distinct** specifier string from **import** or **re-export** `from "..."`; see 07 §2.1 and §6).
- Then `import_count` × u32: `module_specifier_index` (u32): string table index of that specifier string (e.g. `"kestrel:string"` or a path).

Order of entries is unspecified. Per-symbol import details (which names are imported from which module) are not stored here; the compiler resolves those at compile time and embeds references (e.g. function index, type index) in the code and type table.

### 6.6 Imported function table (cross-package calls)

**Purpose:** Enables **CALL** (04 §1.5) to target functions in other packages. The CALL instruction’s `fn_id` operand can refer either to a **local** function (index in [0, function_count)) or to an **imported** function (index in [function_count, function_count + imported_function_count)). For an imported call, the VM uses this table to resolve (import_index, function_index in that module).

At the next 4-byte-aligned offset after the import table (6.5):

- `imported_function_count` (u32): number of distinct external call targets this module uses (one entry per (import, function) pair the code calls).
- Then `imported_function_count` entries, each 8 bytes (2 × u32), 4-byte aligned:
  - `import_index` (u32): index into this module’s **import table** (6.5); identifies which dependency (0 = first import, 1 = second, etc.). Must be in [0, import_count).
  - `function_index` (u32): index into the **imported** module’s function table (03 §6.1). Obtained at compile time from that dependency’s **types file** (07 §5).

**CALL resolution:** For **CALL** `fn_id`, `arity`: if `fn_id` < `function_count`, the call is **local** (dispatch to the code_offset of function table entry `fn_id` in this module). If `fn_id` ≥ `function_count`, let `k` = `fn_id` - `function_count`; `k` must be in [0, imported_function_count). The k-th entry in this table gives (`import_index`, `function_index`). The VM resolves the module for that import (loading it on first use per 07 §9), then calls the function at `function_index` in that module’s function table. Thus CALL has a single index space: [0, function_count) = local, [function_count, function_count + imported_function_count) = imported.

For an imported **var** (07 §5.1), the calling package may emit **two** entries in this table: one for the getter and one for the setter, so that CALL with the first index reads the var and CALL with the second index (one argument) updates it. The types file (07 §5) supplies both indices for vars.

---

## 7. Section 3: Code Section

**Purpose:** Executable bytecode; the first byte is the module entry point (initializer).

- **Layout:** Raw bytecode only; no internal header. Section length = `section_offsets[4] - section_offsets[3]`.
- **Entry point:** Execution begins at the first byte of this section. If the module has no top-level statements to run, the compiler must emit exactly one **RET** instruction at that offset.
- Instruction encoding and semantics: [04-bytecode-isa.md](04-bytecode-isa.md). The code may contain opcodes 0x20 (CALL_INDIRECT), 0x21 (LOAD_FN), 0x22 (MAKE_CLOSURE), 0x23 (LOAD_IMPORTED_FN), 0x24 (CONSTRUCT_IMPORT), and others listed in 04 §4.1 (including closure and cross-module construction).

---

## 8. Section 4: Debug Section

**Purpose:** Maps code offsets to (source file, line) for stack traces; single format. When built without debug, the section still follows this layout with `file_count` = 0 and `entry_count` = 0.

- **Layout:** Same structure always. When debug is omitted, either the section has zero length or it contains the same layout with zero counts (see Empty debug below).
- `file_count` (u32): number of source files (0 if no debug).
- `file_string_indices` (u32 × file_count): for each file, string table index of its path. If `file_count` is 0, zero u32s.
- `entry_count` (u32): number of (code offset, file, line) mappings (0 if no debug).
- `entries` (entry_count × 12 bytes): each entry:
  - `code_offset` (u32): byte offset **relative to start of code section** (section 3).
  - `file_index` (u32): index into the file list; must be in [0, file_count).
  - `line` (u32): 1-based source line number.
- **Sorting:** Entries must be sorted by `code_offset` ascending so that the VM can binary-search to map a code offset to (file, line).
- **Empty debug:** If compiled without debug, either (a) `section_offsets[4]` equals `section_offsets[5]` (zero-length section; nothing is read), or (b) the section is present with `file_count` = 0 and `entry_count` = 0, so the layout is exactly 8 bytes (two u32s, no file indices, no entries).

---

## 9. Section 5: Shape Table

**Purpose:** Defines record shapes (structural types) by field names and types; referenced by the type table (Record tag) only.

- **Layout:**
  - `shape_count` (u32).
  - For each shape, one **shape entry**:
    - `field_count` (u32): number of fields. Must be 4-byte aligned at the start of this u32 (pad 0–3 bytes after the previous shape’s last field pair if needed).
    - Then `field_count` pairs, each 8 bytes (2 × u32): `name_index` (string table), `type_index` (type table in section 2). No padding between pairs. Field order is significant (record layout).
  - After the last field pair of a shape, pad to the next 4-byte boundary before the next shape’s `field_count`.

---

## 10. Section 6: ADT Table

**Purpose:** Defines algebraic data types (type name and constructors with payload types); referenced only by the type table (ADT tag). Type *aliases* are in section 2 (§6.4); ADT *definitions* are only here. Language-level **exported exceptions** (e.g. `export exception Foo { x: T }`) are represented as ADTs in this table with a single constructor and optional payload type.

- **Layout:**
  - `adt_count` (u32).
  - For each ADT, one **ADT entry** (each 4-byte aligned):
    - `name_index` (u32): string table index of the type name.
    - `constructor_count` (u32): number of constructors.
    - Then `constructor_count` **constructor entries**, each 8 bytes (2 × u32):
      - `name_index` (u32): string table index of constructor name.
      - `payload_type_index` (u32): type table index of payload type, or **0xFFFF_FFFF** if no payload.
    - After the last constructor entry, pad to the next 4-byte boundary before the next ADT’s `name_index`.
  - Constructor order is significant: runtime tag for the k-th constructor is k (0-based).

---

## 11. Relation to Other Specs

- Instruction encoding and semantics: [04-bytecode-isa.md](04-bytecode-isa.md)
- Runtime layout of values and heap objects: [05-runtime-model.md](05-runtime-model.md)
- How shapes and ADTs map to the type system: [06-typesystem.md](06-typesystem.md)
- Modules and imports: [07-modules.md](07-modules.md) (one .kbc per module; linking/loading is implementation-defined)

---

## 12. Versioning

- The header `version` (u32) identifies the bytecode format. Implementations must **increment** this value for any change to section count, order, or layout.
- The VM must **reject** a file with an unknown or unsupported `version`.
- Magic remains `KBC1` across format versions; version number distinguishes layouts.
