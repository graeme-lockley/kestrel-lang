# 07 – Module System and URL Resolution

Version: 1.0

---

This document specifies the Kestrel module system in enough detail that implementors can build a deterministic compiler and loader without ambiguity. It must be read together with the import/export grammar in [01-language.md](01-language.md) (§3.1) and the standard library contract in [02-stdlib.md](02-stdlib.md).

---

## 1. Definitions

- **Module:** A single compilation unit. One **source file** (e.g. `.ks`) is one module. The identity of a module for resolution is determined by its **module specifier** (see below).
- **Package:** A module compiled into two artifacts: (1) a **binary file** (e.g. `.kbc`, see 03) containing the executable bytecode for that module, and (2) a **types file** (compile-time only) containing all **exported declarations** (function signatures, types, constants, variables) in a format that allows a **referring package to be typechecked without parsing or compiling** the referenced package. The types file does **not** contain bytecode; it **does** contain **offsets** (e.g. function index, constant index) into the package’s binary so that the **calling** package can be compiled with **static offsets** (no name lookup at load or runtime). See §5 and §8.
- **Module specifier:** The **exact string value** of the STRING token in an import or re-export (the literal in `import ... from "..."` or `export ... from "..."`). No normalisation is applied for the purpose of this spec: the specifier is the character sequence between the quotes after string literal parsing (including escape sequences resolved). Examples: `"./m.ks"`, `"https://example.com/lib.ks"`, `"kestrel:string"`. Two specifiers are **the same** if and only if they are **string-equal** (byte-for-byte or Unicode code point equality, implementation must be consistent).
- **Resolved artifact:** The result of **resolution**: the concrete module (source file, compiled binary and types file, or built-in module) that a specifier maps to. Resolution is the process of mapping a specifier to exactly one artifact (or failing).
- **Public binding (of a module):** A name that another module can import from this module. Defined in §3. A module’s **export set** is the set of names it exports (each name appears at most once after conflict resolution).

---

## 2. Import Forms and Semantics

The grammar is in 01 §3.1 (ImportDecl, ImportClause, ImportSpec). The following defines semantics.

### 2.1 Specifier and distinct imports

- Every import declaration contains exactly one **specifier** (the STRING in `from STRING` or the STRING in `import STRING`). Re-export forms (`export * from STRING` and `export { … } from STRING`, 01 §3.1) also contain a specifier in `from STRING`.
- The **distinct specifiers** of a module are the set of specifier values that appear in its **import** declarations **or** its **re-export** declarations (deduplicated by string equality). Example: if the source has `import { a } from "./m.ks"` and `import { b } from "./m.ks"`, there is **one** distinct specifier, `"./m.ks"`. If the source has no imports but has `export * from "./lib.ks"`, the distinct specifiers include `"./lib.ks"`.
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
- **Semantics:** The resolved module is loaded. The current module binds the namespace name to a **namespace object** that exposes all **public bindings** of that module. The namespace name must be a **UPPER_IDENT** (01 §2.3). Access to a binding is by the namespace name and the exported name (e.g. `M.length` for the `length` exported by the module bound to `M`). For each **exported, non-opaque** ADT in that module, every **exported constructor name** is also a public binding on the namespace (same names as in §3.1.1): **`M.Ctor`** for a nullary constructor (value of type `T`, 06 §5.1) and **`M.Ctor(e1,…,en)`** for n-ary constructors (01 §3.1). Opaque ADT constructors are not namespace members. The namespace name must be unique in the current module (one namespace per specifier; two `import * as M from ...` with different specifiers would need different names, e.g. `M1` and `M2`).

**Implementation notes:** The namespace name is validated at parse time to be UPPER_IDENT (e.g. start with an uppercase letter); otherwise a parse error is reported. The namespace type exposed to the type checker carries all public bindings (values, functions, type aliases, and **exported ADT constructors** for non-opaque types) of the resolved module. At code generation, qualified access `M.f(args)` for a **function or value export** resolves to a static **CALL** (or getter) via the imported function table, like named imports. Qualified **constructor** application **`M.Ctor(args)`** is lowered so the built ADT value carries the **defining module’s** ADT identity (see 04 §1.7 **CONSTRUCT_IMPORT**, 05 §2 ADT). No name lookup is performed at load or runtime. The namespace name must be unique across all import declarations in the module (no duplicate namespace name, and no conflict with a local name from a named import).

### 2.4 Side-effect import

- **Form:** `import STRING` (no bindings).
- **Semantics:** The specifier is resolved at compile time. No names are bound in the current module. The specifier is still part of the module’s dependencies and **must appear in the bytecode import table** (03 §6.5) exactly once per distinct specifier (i.e. if the only import is `import "./m.ks"`, the import table has one entry with that specifier). At runtime, the module is **loaded and executed** only when it is loaded—and loading happens only on **first use** (§9). A side-effect-only import does not constitute use (no CALL or other instruction targets that package), so the package is not loaded or executed unless some other use (e.g. a named import that is called) triggers it.

---

## 3. Exports and Public Bindings

### 3.1 Local exports

- **Forms (01 §3.1):** `export TopLevelDecl` (export a function, type, or exception declaration), and `export exception UPPER_IDENT ...` (exception declarations are always exported).
- **Semantics:** The declared name is added to the current module’s **export set** with source **local**. That name is a **public binding** and may be imported by other modules. The same name may not be declared twice (normal duplicate-declaration rules); if a name is both declared locally and re-exported, see §3.3 (conflicts).

### 3.1.1 Type export visibility

Type declarations have three visibility levels (01 §3.1):

- **Local** (`type Foo = ...`): The type name and constructors are module-private. They do not appear in the export set and cannot be imported.
- **Opaque** (`opaque type Foo = ...`): The type **name** is added to the export set. Importers can reference `Foo` in type annotations. However, the type's **constructors** (for ADTs) and **internal structure** (for aliases) are **not** exported. Importers cannot construct values, destructure, or pattern-match on the type. The declaring module retains full access.
- **Exported** (`export type Foo = ...`): The type name **and** all constructors are added to the export set. Importers have full access: construction, destructuring, and pattern matching.

For an **exported ADT** (e.g., `export type Color = Red | Green | Blue`), the export set includes the type name `Color` **and** each constructor name (`Red`, `Green`, `Blue`). Importers can use `import { Color, Red, Green, Blue } from "..."` or `import { Color } from "..."` (constructors are available when the type is imported by name). With **`import * as M from "..."`**, importers may also construct via **`M.Red`**, **`M.Green(…)`**, etc., with the same typing rules as unqualified constructors (06 §5.1).

For an **opaque ADT** (e.g., `opaque type Token = Num(Int) | Op(String)`), only the type name `Token` is in the export set. The constructors `Num` and `Op` are not importable.

For an **extern type** (e.g., `export extern type HashMap = jvm("java.util.HashMap")`), only the type name is exported. Importers may reference the name in type signatures, but the underlying JVM descriptor and representation details are not exposed through the module surface.

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

- **Input:** A module specifier (string) and the **context**: current file path (or current module identity), and environment (e.g. cache directory).
- **Output:** Either (1) a **resolved artifact** (the module’s source or compiled form, or a handle to a built-in module), or (2) **failure** (module not found, invalid specifier, or other error). The implementation must report failure as a **compile error** (or a defined error behaviour).
- **Invariant:** For a given specifier and context, resolution must be **deterministic**: the same specifier and same context (same current file, project layout, cache state) must always yield the same result (same artifact or same failure).

### 4.2 Specifier kinds

- **Standard library:** Any specifier that starts with `kestrel:` followed by one or more path segments is a **stdlib specifier**. The specifier `kestrel:X` or `kestrel:X/Y/...` is mapped to the file `<stdlibDir>/kestrel/X.ks` or `<stdlibDir>/kestrel/X/Y/....ks`. **Segment validation:** each segment between `:` and `/` must match `[a-zA-Z0-9_-]+`; any segment containing characters outside this set (including `..` path traversal) is a **compile error**. If the mapped file exists, it is resolved as-is. If the file does not exist, the compiler must report an `unknown stdlib module` error identifying the specifier and the expected file path. No hardcoded allowlist of module names is required: any `kestrel:` specifier that passes segment validation and whose mapped file exists is a valid stdlib module. The well-known stdlib modules (e.g. `kestrel:string`, `kestrel:list`, `kestrel:http`) remain valid under this rule. How stdlib modules are provided (bundled `.ks` source, compiled `.kbc`, or generated) is implementation-defined.

  **Note for `kestrel:http`:** The module exports three opaque types — `Server`, `Request`, and `Response` — backed by JDK classes (`com.sun.net.httpserver.HttpServer`, `com.sun.net.httpserver.HttpExchange`, and an implementation-defined response representation respectively). These types are not constructible by user code; they are produced exclusively by the `kestrel:http` module functions (`createServer`, `get`, `makeResponse`). See 02 §`kestrel:http` and 05 §2 for the concurrency model.

  **Note for `kestrel:web`:** A lightweight routing framework built on `kestrel:http` and implemented entirely in Kestrel. See 02 §`kestrel:web` for the `Router` type, pattern syntax, and `serve`. Depends on `kestrel:http`, `kestrel:list`, `kestrel:dict`, and `kestrel:string`.

  **Note for `kestrel:socket`:** TCP and TLS socket library backed by `java.net.Socket` / `javax.net.ssl.SSLSocket` via `extern type`/`extern fun`. No maven dependencies — JDK-only. See 02 §`kestrel:socket` for types (`Socket`, `ServerSocket`), client functions (`tcpConnect`, `tlsConnect`), I/O functions (`sendText`, `readAll`, `readLine`, `close`), and server functions (`listen`, `accept`, `serverPort`, `serverClose`).
- **URL:** If the specifier is a valid URL (e.g. starts with `https://` or `http://`, or implementation-defined URL scheme), it is a **URL specifier**. On first encounter the source is fetched, content-hashed (SHA-256), and cached under `~/.kestrel/cache/` (see §7); subsequent resolutions use the cached copy. Resolution is deterministic for a given cache state (see §7).
- **Path (from a local module):** If the importing module is a local file, a path specifier is resolved relative to the importing file's directory on the local filesystem. Extension rules (`.ks` auto-append) are implementation-defined but deterministic.
- **Path (from a URL-fetched module):** If the importing module was fetched from a URL, a relative path specifier (e.g. `"./dir/mary.ks"` or `"../util.ks"`) is resolved relative to the **base URL** of the importing module using standard URL resolution rules (RFC 3986). The result is a new absolute URL that is itself fetched and cached as a URL specifier. This applies recursively: the entire transitive dependency tree of a remote module is downloaded into the cache. A relative path from a URL module can never resolve to a local filesystem path. Path traversal (`../`) is bounded to the same origin: a resolved URL that changes the scheme or host from the importing module's URL is a **compile error** with the import span. the pattern `maven:groupId:artifactId:version` (the prefix `maven:` followed by exactly three colon-separated segments), it is a **maven specifier**. Maven specifiers are **side-effect-only** imports: they add a JAR to the compile-time and runtime classpath but do **not** bind any names into scope. Consequently they may only appear in the bare side-effect import form (`import STRING`); using them with a named or namespace clause (`import { … } from STRING` or `import * as N from STRING`) is a **compile error**. **Segment validation**: each of `groupId`, `artifactId`, and `version` must match the pattern `[a-zA-Z0-9._-]+` after trimming whitespace; any segment containing characters outside this set (including path separators, spaces, or control characters) is a **compile error** before any filesystem or network operation is performed. Resolution: the implementation locates or downloads the artifact JAR from the configured Maven repository (default `https://repo1.maven.org/maven2`), stores it under `~/.kestrel/maven/` (overridable via `KESTREL_MAVEN_CACHE`), and records the Maven coordinate in a `.kdeps` sidecar alongside the emitted `.class` file. At runtime `kestrel run` reads `.kdeps` sidecars transitively and appends the resolved JARs to the JVM classpath. If the same `groupId:artifactId` appears at two different versions in the transitive dependency graph, the implementation **must** report a **compile-time** version-conflict error (naming both offending source files and versions) — not a runtime error. An `extern import "maven:g:a:version#Class"` whose version does not match the version declared by the corresponding side-effect import `import "maven:g:a:version"` in the same compilation unit is also a **compile error**.
- **Path (local only):** Otherwise (importing module is a local file), the specifier is treated as a **filesystem path** (relative or absolute). Resolution: the implementation interprets the path relative to a **base** (e.g. the directory containing the current source file). The base and the rules for resolving `"."`, `".."`, and file extensions (e.g. whether `"./m"` can resolve to `./m.ks` or `./m.kbc`) are **implementation-defined** but must be **deterministic**. The result must be a single file (or failure). Path resolution must not depend on non-deterministic state (e.g. current working directory at compile time may be fixed by the implementation).

### 4.3 Resolution order and cycles

- The compiler must resolve the **current module’s** distinct specifiers. Resolving a specifier may require **loading** the target module, which in turn has its own imports. So resolution is recursive.
- **Order:** The order in which the current module’s distinct specifiers are resolved is **implementation-defined** but must be **deterministic** (e.g. order of first occurrence in source, or lexicographic order of specifier).
- **Cycles:** If module A imports B and B (transitively) imports A, the dependency graph has a cycle. The implementation may (1) **reject** circular dependencies at compile time, or (2) **allow** them and define a deterministic load order (e.g. load A, then when A’s resolution needs B, load B, then when B’s resolution needs A, use the partially loaded A). This spec does not require a particular behaviour; the implementation must document whether cycles are allowed and, if so, how they are handled.

### 4.4 Failure cases

- **Module not found:** The specifier could not be resolved to any artifact (path does not exist, URL unreachable, stdlib name unknown). → **Compile error** (or implementation-defined error reporting).
- **Invalid specifier:** Empty string, or a string that is not a valid path/URL/stdlib name per the implementation’s rules. → **Compile error** or implementation-defined.
- **Name not exported:** A named import or re-export references a name that the resolved module does not export. → **Compile error** (§2.2, §3.2).

---

## 5. Compilation Artifacts

- Each **package** (one module) is compiled into a single **binary file** (03) and a **types file**. The binary is used at runtime; the types file is used only at compile time.
- **Types file:** Contains all exported declarations (signatures and types) so that a referring package can **typecheck** without parsing or compiling the dependency. The types file also contains **offsets** (e.g. function table index, constant pool index) for each exported value and function, so that the **calling** package’s compiler can emit **static offsets** (e.g. CALL with a function index, LOAD_CONST with a constant index). No name lookup is required at load or runtime for variables, constants, or functions (03, 04).
- **Binary file:** Contains only bytecode and tables (03). All references inside the binary are by index/offset (03 §0). The VM and loader do not use names for resolution at runtime.

### 5.1 Types file format

The types file is **JSON**. Implementations must produce and consume this format so that compilers and tools remain compatible. File extension is implementation-defined (e.g. `.kti`).

- **Top-level fields:**
  - `version` (number): format version; the reference implementation uses **3** (adds **`constructor`** export entries; see [kti-format.md](kti-format.md)). Consumers must reject unsupported versions.
  - `functions` (object): map from **export name** (string) to an **export entry** (object). Every exported function, value, variable, and (for non-opaque exported ADTs) each **constructor name** must appear exactly once under its export name where applicable.

- **Export entry by kind.** Each entry in `functions` has a `kind` field and, for most kinds, a `type` field (serialized type for typechecking). The remaining fields depend on `kind`:

  - **function:** `kind` = `"function"`, `function_index` (number, index into the package’s function table 03 §6.1), `arity` (number). Used for exported functions.
  - **val:** `kind` = `"val"`, `function_index` (number). Getter only (0-arity function in the package’s function table). Used for exported immutable values.
  - **var:** `kind` = `"var"`, `function_index` (number), **`setter_index`** (number), `type`. Both indices are into the **same** package’s function table (03 §6.1). `function_index` is the **getter** (0-arity); `setter_index` is the **setter** (1-arity). Writers for packages that export vars **must** emit `setter_index`. Consumers must support all three kinds; for **var**, both getter and setter indices are required so that importers can emit CALL getter (read) and CALL setter (assign). Readers that only need callable exports may use `function_index` only; writers for packages that export vars must emit `setter_index`.
  - **constructor:** `kind` = `"constructor"`, `adt_id`, `ctor_index`, `arity`, `type` (constructor scheme). One entry per exported constructor of each **non-opaque** exported ADT so importers can typecheck and compile **`M.Ctor(…)`** even when the dependency is consumed from a **fresh types file only** (no re-parse of dependency source). Opaque ADTs omit constructor entries. Concrete layout: [kti-format.md](kti-format.md).

- **Type encoding:** The `type` field in each entry is a serialized type (structure is implementation-defined but must be sufficient for typechecking and for distinguishing primitives, arrows, records, etc.). Exact encoding is out of scope here; see [kti-format.md](kti-format.md) (`SerType`, including **`union`** / **`inter`**). Importers therefore see full source-level types even when the companion **`.kbc`** type blob omits `|` / `&` (03 §6.3).

- **Type declarations in the types file:**
  - `types` (object, optional): map from **type name** (string) to a **type export entry** (object). Contains all exported and opaque type declarations.
  - Each type export entry has:
    - `visibility`: `"export"` or `"opaque"`.
    - `kind`: `"alias"` or `"adt"`.
    - For **alias**: `type` (serialized underlying type). For **opaque alias**, the `type` field is omitted or set to `{ "kind": "opaque" }` so that consuming compilers cannot see the underlying type.
    - For **adt**: `constructors` (array of `{ name: string, params: Type[] }`). For **opaque ADT**, the `constructors` field is omitted so that consuming compilers cannot access constructor information.
    - Optional: `typeParams` (array of strings) for parameterized types.
  - **Local** types (no qualifier) are NOT included in the types file.

- **Implementation note:** The reference implementation uses a single `functions` map that includes value/function exports, **`constructor`** rows for exported ADT constructors, type alias entries (`kind` = `"type"` and optional `opaque`), and exceptions. Consumers must support `setter_index` for `kind` = `"var"`, **`constructor`** entries when `version` ≥ 3, and reject unsupported `version` values. See [kti-format.md](kti-format.md) for the concrete encoding.

---

## 6. Bytecode Import Table (03)

- The **import table** (03 §6.5) stores the list of module specifiers that this module imports from. It does **not** store resolved paths, URLs, or any normalised form. It stores the **exact specifier string** as it appeared in the source (the STRING token value).
- **Content:** For each **distinct** specifier that appears in any **import** or **re-export** declaration of the current module (§2.1), the compiler must emit **exactly one** entry in the import table. Each entry is the **string table index** (03 §0) of that specifier string. So: (1) Ensure the specifier string is in the string table; (2) Add one u32 (that string table index) to the import table for each distinct specifier. A barrel file that only re-exports from `"./lib.ks"` must still list `"./lib.ks"` in the import table so the loader can resolve the dependency.
- **Order:** The order of entries in the import table is **unspecified** (03). The compiler may emit entries in any order (e.g. order of first occurrence in the source).
- **Side-effect imports:** A side-effect-only import (`import "<specifier>"`) still contributes that specifier to the distinct set; it must appear in the import table like any other import from that specifier.
- **Purpose:** A loader or tool that reads the .kbc file can reconstruct the set of dependencies by reading the import table and resolving each stored specifier string again. The bytecode does not store which **names** were imported from which module; that is only used at compile time to generate code (e.g. function indices). Per-symbol import details are not persisted (03 §6.5).

---

## 7. URL Import Cache

- **Cache root:** `~/.kestrel/cache/` by default; overridable via the `KESTREL_CACHE` environment variable. Created on first use.
- **Cache layout:** Each URL specifier is stored under `<cacheRoot>/<sha256-of-url>/source.ks`, where the directory name is the lowercase hex SHA-256 of the URL string. This makes the layout stable and human-inspectable.
- **On cache miss (first use):** The implementation fetches the URL source over HTTPS (`http://` requires `--allow-http`), writes the source to the cache path above, and continues compilation. No user action is required — resolution is seamless.
- **Atomic write:** The source is first downloaded into a temp file `source.ks.tmp` in the same cache directory, then renamed to `source.ks`. Because `rename()` is atomic on POSIX filesystems, a concurrent or interrupted run can never leave a partially-written file that appears valid.
- **Partial-failure recovery:** If `source.ks.tmp` exists in a cache directory but `source.ks` does not, a previous download was interrupted (e.g. process killed). The implementation must treat this as a cache miss: delete the stale `.tmp` file and re-fetch the URL.
- **On cache hit:** The cached `source.ks` file is used directly; no network request is made.
- **`--refresh` flag:** When `kestrel run --refresh` or `kestrel build --refresh` is invoked, all URL dependencies in the transitive dependency graph are re-fetched unconditionally and the cache is updated, even if a cached copy already exists.
- **Staleness:** A cached entry is considered stale when it was downloaded more than `KESTREL_CACHE_TTL` seconds ago (default: 604800 = 7 days). Stale entries are used for compilation unless `--refresh` is supplied; `kestrel build --status` flags stale entries.
- **`--status` flag:** `kestrel build --status <entry.ks>` resolves the full transitive dependency graph without compiling or running. It prints a pretty-printed dependency report to stdout and exits 0. Each URL dependency appears as one line:

  ```
  https://example.com/lib.ks   ✓ cached  3 days ago
  https://other.com/util.ks    ✓ cached  9 days ago  ⚠ stale
  https://new.com/mod.ks       ✗ not cached
  ```

- **No lockfile.** There is no `kestrel.lock` file. The cache is the sole persistence mechanism. Reproducibility is achieved by keeping the cache warm and using `--refresh` when updates are desired.
- **URL fetch rules:** `https://` is accepted by default. `http://` requires `--allow-http` on the invoking command. Redirects to a different host are not followed. A fetch failure with no cached copy is a compile error that includes the import source span.

---

## 8. Determinism and Compile-Time Errors

- **Determinism:** Given the same **source files**, **project layout**, and **environment** (cache directory and cache contents), module resolution and the resulting dependency graph must be **the same**. No implementation may produce different resolved modules or different export sets for the same inputs.
- **Compile-time errors (summary):** The implementation must report an error and must not produce a valid .kbc in at least the following cases: (1) A named import or re-export references a name that the resolved module does not export. (2) Two exports introduce the same name from different sources (export conflict). (3) Two imports bind the same local name from different specifiers (import name conflict), unless the programmer uses `as` to rename. (4) Module not found (resolution failure). (5) Invalid specifier (if the implementation defines validity). The implementation may report additional errors (e.g. namespace name not UPPER_IDENT, duplicate import of same name from same specifier); see 01 for lexical and grammatical requirements.

---

## 9. Loading and Linking (Runtime)

- **Import vs. load:** An **import** declares a dependency at compile time (used for typechecking and for emitting static references). It does **not** cause the dependency’s binary to be loaded. **Loading** must be deferred until **first use**: the dependency’s binary is loaded only when execution **actually uses** that package (e.g. first call into that module, first access to an exported value). Given a specific execution path, a dependency may never be used and therefore never loaded. This allows optional or conditional use of dependencies and avoids loading and initializing modules that are never needed on that path.
- **Loading:** The VM (or host) loads a package’s **binary file** when that package is first needed (first use). The process of **finding** which binary to load (e.g. from the import table and the specifier) is **implementation-defined** but should use the specifier strings in the import table to resolve the dependency (e.g. by path or by a registry). The **types file** is not used at runtime; only the binary is loaded.
- **Load on first use; package body at load time:** A package is **loaded** only when it is **used**. "Used" means execution performs an operation that targets that package (e.g. the first CALL instruction whose function index refers to an imported function from that package via the imported function table, 03 §6.6). When a package is loaded, the VM loads its binary, then runs the package's **module initializer** (the code at offset 0 in the code section—top-level statements) **exactly once**. Only after the initializer returns does the VM invoke the requested function. Loaded packages are **cached** (e.g. by resolved path); subsequent CALLs to the same dependency do not reload or re-run the initializer.
- **Side-effect-only imports:** A side-effect import (`import STRING`, §2.4) declares a dependency and adds an entry to the bytecode import table, but it does not add any entry to the **imported function table** (03 §6.6). At runtime there is therefore no **use** of that package (no CALL or other instruction targets it). The package is **never loaded** and its **body never runs**. This is the intended design: optional dependencies remain unloaded until actually used. Programs that need a module's side effects must import at least one binding and use it (e.g. call a function).
- **Linking:** Cross-module references (e.g. CALL to a function in another module) are expressed as **indices or offsets** (03, 04). The calling package’s compiler obtains these from the dependency’s **types file** at compile time and emits static offsets (e.g. function index, constant index). The loader/linker resolves these when the target package’s binary is loaded (e.g. by mapping module + index to actual address or function index). **Name-based lookup** is not used at load or runtime for variables, constants, or functions; all references are by offset/index.

- **Assignment to imported var:** An assignment `x := expr` in module B where `x` is a named import of an **export var** from module A has the same effect as calling a 1-argument function (the **setter**) exported by A: the RHS is evaluated, the setter is invoked with that value, and the exporter’s global is updated. The importer emits CALL with the setter index from the types file (07 §5.1); no name lookup at runtime.

---

## 10. Async Exports and Cross-Module Async Calling

This section specifies how `async fun` declarations interact with the module system.

### 10.1 Async functions at export sites

- An `export async fun f(params): Task<T>` is exported with the same type signature as `export fun f(params): Task<T>` — namely the function type `(params) -> Task<T>`. The `async` keyword is **not** part of the type; it is a codegen directive that instructs the compiler to emit the function as a virtual-thread payload.
- Importing modules cannot distinguish an async export from a non-async export that returns `Task<T>`. Both have type `(params) -> Task<T>` at import sites.
- There is no way to require a caller to pass an "actually async" function at the type level. Higher-order functions that accept `(A) -> Task<B>` work equally for `async fun` and for ordinary functions returning `Task<B>`.

### 10.2 Importing and calling async functions from other modules

- When module B imports `f` from module A where `f` is declared `async fun f(x: A): Task<B>`, B may call `f(arg)` to receive a `Task<B>`. The call site does not use the `async` keyword; it simply calls the function. The returned `Task<B>` may be awaited inside any `async` context in B: `val result = await f(arg)`.
- At the codegen level, the JVM backend emits a call to the imported function using the `KTask`-returning descriptor for async exports (so that the foreign class's `submitAsync` wrapper is invoked). The caller in B does not need to know that `f` was declared `async`; it uses only the type `(A) -> Task<B>` to determine how to call it.
- `await` on the result of a cross-module async call has the same semantics as `await` on a same-module async call: it blocks the current virtual thread until the task completes and returns `B` (or re-throws if the task failed).

### 10.3 Top-level await restriction at module boundaries

- `await` is prohibited outside an `async` context (01 §5, 06 §6). This applies equally within a module and at module boundaries. A module's top-level body (the module initializer) is **not** an async context, so `await` cannot appear at the top level of any module, even if it is importing and calling async functions from another module.
- Modules that need to produce async effects at the top level must do so by defining an `async fun run()` (or equivalent) and calling it at the top level; the returned `Task<Unit>` is submitted to the async runtime, which then awaits quiescence before the program exits (see `kestrel.exitWait` system property in the JVM runtime).

---

## 11. Implementor Checklist

1. **Parse** all ImportDecl and ExportDecl per 01 §3.1; extract the STRING value (specifier) for each.
2. **Distinct specifiers:** Build the set of distinct specifiers (string equality) from all import **and** re-export declarations (§2.1).
3. **Resolution:** For each distinct specifier, resolve to an artifact (path → file, URL → fetch/cache/lockfile, stdlib → built-in or bundled). Resolve in a deterministic order. If resolution fails, report a compile error.
4. **Export set:** Compute the current module’s export set by processing export declarations in order; on conflict (same name, different source), report a compile error.
5. **Import checks:** For each named import, verify that the requested external name is in the resolved module’s export set; otherwise compile error. For namespace import, ensure the namespace name is UPPER_IDENT and unique. Build the namespace **value binding** map from the dependency’s exports: values, functions, type names, type aliases, and **each exported constructor** of each **non-opaque** exported ADT (with constructor types from §3.1.1 / 06 §5.1).
6. **Import name conflicts:** Ensure no local name is bound from two different specifiers without explicit rename; report compile error if so.
7. **Bytecode:** Write the string table so that each distinct specifier string appears at least once; write the import table (03 §6.5) with `import_count` = number of distinct specifiers and one `module_specifier_index` (u32) per distinct specifier, pointing to that string. Do not store resolved paths or normalised URLs in the import table—only the source specifier string.
8. **Types file:** Emit a types file (07 §5) for this package with exported declarations and **offsets** (function index, constant index, etc.) and, for **version** ≥ 3, **`constructor`** entries (§5.1) so referring packages can typecheck **`M.Ctor(…)`** and emit correct bytecode without parsing this package’s source when only `.kti` (and `.kbc`) are fresh.
9. **Code generation:** When generating code for cross-module calls or references, use the **resolved** module’s **types file** (export offsets) so that the emitted bytecode uses static indices (e.g. function index, constant index). No name lookup at load or runtime. Emit the **imported function table** (03 §6.6): for each call to an imported function, add an entry (import_index, function_index from that dependency’s types file); assign such entries consecutive indices starting at function_count so that CALL fn_id with fn_id ≥ function_count resolves via that table. The import table (03 §6.5) records dependency specifiers; the imported function table (03 §6.6) maps CALL indices to (import, function_index). For **namespace-qualified ADT construction** `M.Ctor(args)`, emit **CONSTRUCT_IMPORT** (04 §1.7) with the dependency’s `adt_id` / `ctor` / `arity` and this module’s **import_index** for `M`’s specifier so the runtime-built ADT value matches identity for values constructed inside the dependency (05 §2 ADT).

---

## 12. Relation to Other Specs

| Spec | Relation |
|------|----------|
| **01** | ImportDecl, ExportDecl, TopLevelDecl grammar (01 §3.1). STRING is the specifier. UPPER_IDENT for namespace; IDENT for named import/export. Program order: imports first, then declarations and statements. |
| **02** | Standard library module names (including `kestrel:string`, `kestrel:char`, `kestrel:list`, `kestrel:stack`, `kestrel:http`, `kestrel:json`, `kestrel:fs`, `kestrel:web`, `kestrel:socket`) must resolve to modules that satisfy 02. No other spec may use those names for a different contract. |
| **03** | One .kbc (binary) per module; references in bytecode are by offset/index only (03 §0). Import table (§6.5): `import_count` and one u32 (string table index) per distinct import specifier; the string is the **exact source specifier**. Exported names and their offsets appear in the package’s types file (07 §5); function table (§6.1), exported type declarations (§6.4), and ADT table (§10) hold the definitions in the binary. || **06** | Structural async typing (06 §6): `async fun f(x: A): Task<B>` has the same type `(A) -> Task<B>` as a plain `fun f(x: A): Task<B>`. The `async` keyword is invisible at module boundaries. `await` prohibition at module scope enforced by the type checker (06 §6). |