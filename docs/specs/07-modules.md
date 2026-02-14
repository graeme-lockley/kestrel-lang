# 07 – Module System and URL Resolution

Version: 1.0

---

This document specifies the Kestrel module system in enough detail that implementors can build a deterministic compiler and loader without ambiguity. It must be read together with the import/export grammar in [01-language.md](01-language.md) (§3.1), the bytecode format in [03-bytecode-format.md](03-bytecode-format.md) (§6.5 import table), and the standard library contract in [02-stdlib.md](02-stdlib.md).

---

## 1. Definitions

- **Module:** A single compilation unit. One **source file** (e.g. `.ks`) is one module; it compiles to one **.kbc** file (03). The identity of a module for resolution is determined by its **module specifier** (see below).
- **Module specifier:** The **exact string value** of the STRING token in an import or re-export (the literal in `import ... from "..."` or `export ... from "..."`). No normalisation is applied for the purpose of this spec: the specifier is the character sequence between the quotes after string literal parsing (including escape sequences resolved). Examples: `"./m.ks"`, `"https://example.com/lib.ks"`, `"kestrel:string"`. Two specifiers are **the same** if and only if they are **string-equal** (byte-for-byte or Unicode code point equality, implementation must be consistent).
- **Resolved artifact:** The result of **resolution**: the concrete module (source file, compiled .kbc, or built-in module) that a specifier maps to. Resolution is the process of mapping a specifier to exactly one artifact (or failing).
- **Public binding (of a module):** A name that another module can import from this module. Defined in §3. A module’s **export set** is the set of names it exports (each name appears at most once after conflict resolution).

---

## 2. Import Forms and Semantics

The grammar is in 01 §3.1 (ImportDecl, ImportClause, ImportSpec). The following defines semantics.

### 2.1 Specifier and distinct imports

- Every import declaration contains exactly one **specifier** (the STRING in `from STRING` or the STRING in `import STRING`).
- The **distinct specifiers** of a module are the set of specifier values that appear in its import declarations (deduplicated by string equality). Example: if the source has `import { a } from "./m.ks"` and `import { b } from "./m.ks"`, there is **one** distinct specifier, `"./m.ks"`.
- **Resolution** is performed for each distinct specifier. The same artifact is used for every import declaration that shares that specifier. The **order** in which specifiers are resolved is implementation-defined but must be **deterministic** (same source and environment ⇒ same order and results).

### 2.2 Named import

- **Form:** `import { ImportSpec { "," ImportSpec } } from STRING`. Each ImportSpec is `IDENT [ "as" IDENT ]`.
- **Semantics:** For each ImportSpec:
  - Let **external name** be the first IDENT (the name in the other module). Let **local name** be the second IDENT if `as` is present, otherwise the external name.
  - The resolved module (for the specifier of this import) must have a **public binding** whose name equals the external name. If it does not, that is a **compile error** (e.g. “module M does not export name x”).
  - The current module binds **local name** to that exported value (or type). Local name must be unique in the current module’s import scope (two imports cannot bind the same local name unless they refer to the same export; see conflicts below).
- **Duplicate imports of the same name from the same specifier:** If the source has `import { x } from "./m"` and `import { x } from "./m"` again, both bind the same `x` from the same module. Having the same local name bound twice from the same specifier is **redundant but allowed**; the implementation may treat it as one binding. If the same local name is bound from **different** specifiers (e.g. `import { x } from "./a"` and `import { x } from "./b"`), that is a **name conflict** in the import scope → **compile error** unless the programmer uses `as` to rename one or both.

### 2.3 Namespace import

- **Form:** `import "*" "as" UPPER_IDENT "from" STRING` (01). The UPPER_IDENT is the **namespace name**.
- **Semantics:** The resolved module is loaded. The current module binds the namespace name to a **namespace object** that exposes all **public bindings** of that module. The namespace name must be a **UPPER_IDENT** (01 §2.3). Access to a binding is by the namespace name and the exported name (e.g. `M.length` for the `length` exported by the module bound to `M`). The namespace name must be unique in the current module (one namespace per specifier; two `import * as M from ...` with different specifiers would need different names, e.g. `M1` and `M2`).

### 2.4 Side-effect import

- **Form:** `import STRING` (no bindings).
- **Semantics:** The specifier is resolved and the module is **loaded and executed** (for side effects). No names are bound in the current module. The specifier is still part of the module’s dependencies and **must appear in the bytecode import table** (03 §6.5) exactly once per distinct specifier (i.e. if the only import is `import "./m.ks"`, the import table has one entry with that specifier).

---

## 3. Exports and Public Bindings

### 3.1 Local exports

- **Forms (01 §3.1):** `export TopLevelDecl` (export a function, type, or exception declaration), and `export exception UPPER_IDENT ...` (exception declarations are always exported).
- **Semantics:** The declared name is added to the current module’s **export set** with source **local**. That name is a **public binding** and may be imported by other modules. The same name may not be declared twice (normal duplicate-declaration rules); if a name is both declared locally and re-exported, see §3.3 (conflicts).

### 3.2 Re-export

- **Export all:** `export "*" "from" STRING`. The specifier is resolved. For **every** name in that module’s export set, the current module re-exports that name (as if it had exported it itself). Each such name is added to the current module’s export set with source **re-export from &lt;specifier&gt;**.
- **Export with rename:** `export "{" ExportSpec { "," ExportSpec } "}" "from" STRING`, where ExportSpec is `IDENT [ "as" IDENT ]`. For each ExportSpec: the **external name** (first IDENT) must be in the resolved module’s export set; otherwise **compile error**. The **local export name** (second IDENT if `as` present, else the external name) is added to the current module’s export set with source re-export from that specifier.

### 3.3 Export conflicts

- The current module’s export set is built by processing every export declaration in **source order**. Each export adds one or more **(name, source)** pairs.
- **Conflict:** Adding a name **N** with source **S** causes a conflict if **N** is already in the export set and was added with a **different** source (e.g. local vs re-export, or re-export from specifier A vs re-export from specifier B). When a conflict is detected, the implementation must report a **compile error** (e.g. “name N is exported from multiple sources”).
- **No conflict:** The same name re-exported twice from the **same** specifier (e.g. `export * from "./m"` and `export { x } from "./m"` when x is already in "./m"’s export set) does not introduce a second source; the implementation may treat the export set as containing the name once from that specifier.
- **Resolving conflicts:** The programmer must rename so that no name is exported twice from different sources. For example: `export * from "./a"` and `export * from "./b"` and both a and b export `foo` → conflict. The programmer must use `export { foo as fooA } from "./a"` and `export { foo as fooB } from "./b"` (or omit one) so that the current module’s export set has no duplicate name.

### 3.4 Definition of a module’s export set

- **Algorithm (conceptual):** Start with an empty set. For each export declaration in order: (1) Local export: add (name, local). (2) `export * from "<specifier>"`: resolve specifier, get that module’s export set, add (n, re-export &lt;specifier&gt;) for each n in that set. (3) `export { x as y } from "<specifier>"`: resolve specifier, check x is in that module’s export set, add (y, re-export &lt;specifier&gt;). If any add would create a conflict (same name, different source), **compile error**.
- Recursive re-exports: if module A does `export * from "./b"` and B does `export * from "./c"`, then A’s export set includes everything C exports (via B). So “that module’s export set” means the fully computed export set of the resolved module (computed after that module’s own imports and exports are processed).

---

## 4. Resolution

### 4.1 What resolution does

- **Input:** A module specifier (string) and the **context**: current file path (or current module identity), project root (if any), lockfile (if present), and environment (e.g. cache directory).
- **Output:** Either (1) a **resolved artifact** (the module’s source or compiled form, or a handle to a built-in module), or (2) **failure** (module not found, invalid specifier, or other error). The implementation must report failure as a **compile error** (or a defined error behaviour).
- **Invariant:** For a given specifier and context, resolution must be **deterministic**: the same specifier and same context (same current file, project layout, lockfile, cache state) must always yield the same result (same artifact or same failure).

### 4.2 Specifier kinds

- **Standard library:** If the specifier is exactly one of the module names defined in 02, it is a **stdlib specifier**. The names are: `kestrel:string`, `kestrel:stack`, `kestrel:http`, `kestrel:json`, `kestrel:fs`. The implementation must resolve these to modules that satisfy the contract in 02 (same names and signatures). How they are provided (built-in, bundled .kbc, or generated) is implementation-defined. Any other specifier that starts with `kestrel:` (or matches an implementation-defined pattern for stdlib) may be **reserved**: the implementation may reject it or treat it as a future stdlib module.
- **URL:** If the specifier is a valid URL (e.g. starts with `https://` or `http://`, or implementation-defined URL scheme), it is a **URL specifier**. Resolution (fetch, cache, lockfile lookup) is implementation-defined but must be deterministic when a lockfile is present (see §6).
- **Path:** Otherwise, the specifier is treated as a **path** (relative or absolute). Resolution: the implementation interprets the path relative to a **base** (e.g. the directory containing the current source file, or the project root). The base and the rules for resolving `"."`, `".."`, and file extensions (e.g. whether `"./m"` can resolve to `./m.ks` or `./m.kbc`) are **implementation-defined** but must be **deterministic**. The result must be a single file (or failure). Path resolution must not depend on non-deterministic state (e.g. current working directory at compile time may be fixed by the implementation).

### 4.3 Resolution order and cycles

- The compiler must resolve the **current module’s** distinct specifiers. Resolving a specifier may require **loading** the target module, which in turn has its own imports. So resolution is recursive.
- **Order:** The order in which the current module’s distinct specifiers are resolved is **implementation-defined** but must be **deterministic** (e.g. order of first occurrence in source, or lexicographic order of specifier).
- **Cycles:** If module A imports B and B (transitively) imports A, the dependency graph has a cycle. The implementation may (1) **reject** circular dependencies at compile time, or (2) **allow** them and define a deterministic load order (e.g. load A, then when A’s resolution needs B, load B, then when B’s resolution needs A, use the partially loaded A). This spec does not require a particular behaviour; the implementation must document whether cycles are allowed and, if so, how they are handled.

### 4.4 Failure cases

- **Module not found:** The specifier could not be resolved to any artifact (path does not exist, URL unreachable, stdlib name unknown). → **Compile error** (or implementation-defined error reporting).
- **Invalid specifier:** Empty string, or a string that is not a valid path/URL/stdlib name per the implementation’s rules. → **Compile error** or implementation-defined.
- **Name not exported:** A named import or re-export references a name that the resolved module does not export. → **Compile error** (§2.2, §3.2).

---

## 5. Bytecode Import Table (03)

- The **import table** (03 §6.5) stores the list of module specifiers that this module imports from. It does **not** store resolved paths, URLs, or any normalised form. It stores the **exact specifier string** as it appeared in the source (the STRING token value).
- **Content:** For each **distinct** specifier that appears in any import declaration of the current module, the compiler must emit **exactly one** entry in the import table. Each entry is the **string table index** (03 §0) of that specifier string. So: (1) Ensure the specifier string is in the string table; (2) Add one u32 (that string table index) to the import table for each distinct specifier.
- **Order:** The order of entries in the import table is **unspecified** (03). The compiler may emit entries in any order (e.g. order of first occurrence in the source).
- **Side-effect imports:** A side-effect-only import (`import "<specifier>"`) still contributes that specifier to the distinct set; it must appear in the import table like any other import from that specifier.
- **Purpose:** A loader or tool that reads the .kbc file can reconstruct the set of dependencies by reading the import table and resolving each stored specifier string again. The bytecode does not store which **names** were imported from which module; that is only used at compile time to generate code (e.g. function indices). Per-symbol import details are not persisted (03 §6.5).

---

## 6. Lockfile

- **File name and location:** `kestrel.lock` in the **project root**, or in an implementation-defined location (e.g. alongside the main module). The implementation must define how the project root is determined.
- **Purpose:** When present, the lockfile records enough information to resolve **URL** (and optionally **path**) dependencies **without network access or other non-determinism**. For each specifier that was resolved from a URL (or path), the lockfile typically stores a content hash or a pinned URL/version so that the next resolution uses the same artifact.
- **Format:** Implementation-defined (e.g. TOML, JSON). The format must be sufficient to map every such specifier used in the project to a single artifact (e.g. a path to a cached file or a content hash).
- **Behaviour when lockfile is present:** When resolving a specifier that is listed in the lockfile, the implementation must use the locked artifact (or fail if the artifact is missing). When resolving a specifier that is **not** in the lockfile, the implementation may **error** (e.g. “run kestrel lock to update lockfile”) or **resolve** and optionally **update** the lockfile; behaviour is implementation-defined but must be deterministic for a given environment.
- **Behaviour when lockfile is absent:** Resolution proceeds without a lockfile; behaviour is implementation-defined but must be deterministic for the same inputs (same specifiers, same project layout, same cache).

---

## 7. Determinism and Compile-Time Errors

- **Determinism:** Given the same **source files**, **project layout**, **lockfile** (if present), and **environment** (e.g. cache directory, network disabled when lockfile present), module resolution and the resulting dependency graph must be **the same**. No implementation may produce different resolved modules or different export sets for the same inputs.
- **Compile-time errors (summary):** The implementation must report an error and must not produce a valid .kbc in at least the following cases: (1) A named import or re-export references a name that the resolved module does not export. (2) Two exports introduce the same name from different sources (export conflict). (3) Two imports bind the same local name from different specifiers (import name conflict), unless the programmer uses `as` to rename. (4) Module not found (resolution failure). (5) Invalid specifier (if the implementation defines validity). The implementation may report additional errors (e.g. namespace name not UPPER_IDENT, duplicate import of same name from same specifier); see 01 for lexical and grammatical requirements.

---

## 8. Loading and Linking (Runtime)

- **Loading:** The VM (or host) loads one or more .kbc files. The process of **finding** which .kbc files to load (e.g. from the import table of the entry module and then recursively) is **implementation-defined** but should use the specifier strings in the import table to resolve dependencies (e.g. by path or by a registry).
- **Linking:** Cross-module references (e.g. CALL to a function in another module) are resolved at **load time** or **link time**: the compiler emits indices or placeholders that the loader/linker fills in with the actual address or function index of the target module’s export. The exact mechanism (per-module function index space vs global index, etc.) is **implementation-defined**. The module system only requires that (1) the import table in each .kbc accurately lists the specifiers that module depends on, and (2) resolution at runtime (or at link time) is deterministic when the same specifiers and environment are used.

---

## 9. Implementor Checklist

1. **Parse** all ImportDecl and ExportDecl per 01 §3.1; extract the STRING value (specifier) for each.
2. **Distinct specifiers:** Build the set of distinct specifiers (string equality) from all import declarations.
3. **Resolution:** For each distinct specifier, resolve to an artifact (path → file, URL → fetch/cache/lockfile, stdlib → built-in or bundled). Resolve in a deterministic order. If resolution fails, report a compile error.
4. **Export set:** Compute the current module’s export set by processing export declarations in order; on conflict (same name, different source), report a compile error.
5. **Import checks:** For each named import, verify that the requested external name is in the resolved module’s export set; otherwise compile error. For namespace import, ensure the namespace name is UPPER_IDENT and unique.
6. **Import name conflicts:** Ensure no local name is bound from two different specifiers without explicit rename; report compile error if so.
7. **Bytecode:** Write the string table so that each distinct specifier string appears at least once; write the import table (03 §6.5) with `import_count` = number of distinct specifiers and one `module_specifier_index` (u32) per distinct specifier, pointing to that string. Do not store resolved paths or normalised URLs in the import table—only the source specifier string.
8. **Code generation:** When generating code for cross-module calls or references, use the **resolved** module’s export information (e.g. function index, type index) so that the emitted bytecode is valid. The import table is for dependency recording; the actual references are embedded in the code and type table (03).

---

## 10. Relation to Other Specs

| Spec | Relation |
|------|----------|
| **01** | ImportDecl, ExportDecl, TopLevelDecl grammar (01 §3.1). STRING is the specifier. UPPER_IDENT for namespace; IDENT for named import/export. Program order: imports first, then declarations and statements. |
| **02** | Standard library module names (`kestrel:string`, `kestrel:stack`, `kestrel:http`, `kestrel:json`, `kestrel:fs`) must resolve to modules that satisfy 02. No other spec may use those names for a different contract. |
| **03** | One .kbc per module. Import table (§6.5): `import_count` and one u32 (string table index) per distinct import specifier; the string is the **exact source specifier**. Exported names appear in function table (§6.1), exported type declarations (§6.4), and ADT table (§10) for exceptions. |
