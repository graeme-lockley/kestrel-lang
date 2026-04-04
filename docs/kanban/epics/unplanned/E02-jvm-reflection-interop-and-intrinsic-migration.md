# Epic E02: JVM Interop — extern Bindings and Intrinsic Migration

## Status

Unplanned

## Summary

Introduce a first-class JVM interop surface through new language constructs (`extern type`, `extern fun`, `extern import`) and module schemes (`java:`, `maven:`) that allow any Kestrel module to bind and call Java classes, constructors, and methods with full static type safety and zero reflection overhead for known APIs. This epic also migrates all existing `__*` compiler builtins to `extern`-based stdlib declarations, eliminating the need to touch `codegen.ts` for every new host-library binding. The `maven:` classpath declaration scheme — including jar resolution, download, caching, and the auto-generated `.kdeps` conflict-detection sidecars — is also part of this epic, as it is a direct requirement for `extern` bindings to third-party jars.

## Design

### The Problem with a Pure-Library Approach

A reflection-only `kestrel:jvm` library forces every Java call site to cross an `Any` boundary:

```kestrel
val result = Jvm.invokeVirtual(prepStmt, conn, [sql]) as ResultSet  // runtime cast, no type safety
```

Kestrel has no member-call syntax (`x.f(y)` is invalid), so chained Java APIs become especially verbose. Errors surface at runtime rather than compile time. Every real library author would work around this, so it should not be the primary mechanism.

### Interop Design

`extern` declarations are the sole mechanism for JVM interop in E02. They cover all known-API use cases — stdlib bindings, third-party jar wrappers, and JDK calls — with full static type safety and direct bytecode emission. A dynamic reflection library for unknown class names (plugin/scripting scenarios) is not in scope for this epic.

### New Language Constructs

#### `extern type` — binding a Java class as an opaque type

```kestrel
extern type HashMap = jvm("java.util.HashMap")
extern type Connection = jvm("java.sql.Connection")
```

The Kestrel type is opaque to importers. The compiler knows the underlying JVM class descriptor and uses it for method dispatch and type checking.

#### `extern fun` — binding a Java method as a Kestrel function

```kestrel
// Instance method (first argument is the receiver)
extern fun put(m: HashMap, k: String, v: String): Unit =
  jvm("java.util.HashMap#put(java.lang.Object,java.lang.Object)")

// Constructor
extern fun newHashMap(): HashMap =
  jvm("java.util.HashMap#<init>()")

// Static method
extern fun connect(url: String, user: String, pass: String): Task<Result<Connection, String>> =
  jvm("java.sql.DriverManager#getConnection(java.lang.String,java.lang.String,java.lang.String)")
```

The compiler resolves the descriptor at compile time and emits a direct `invokevirtual`/`invokestatic`/`invokespecial` with Kestrel↔JVM boxing/unboxing. No reflection at runtime.

#### Parametric `extern fun` — absorbing Java type erasure

Kestrel has no cast operator (`as` is import/export alias syntax only; there is no type-cast expression). Java generics are erased at the class file level, so methods like `HashMap.get` return `Object` in bytecode. Parametric type parameters on `extern fun` declarations are the mechanism for handling this cleanly:

```kestrel
// Type parameter V is the cast promise — compiler emits a JVM checkcast.
// The binding author asserts correctness; all call sites remain fully typed.
extern fun jhmGet<V>(m: JHashMap, k: Any): V =
  jvm("java.util.HashMap#get(java.lang.Object)")

extern fun jhmKeySet<K>(m: JHashMap): List<K> =
  jvm("java.util.HashMap#keySet()")

extern fun jhmValues<V>(m: JHashMap): List<V> =
  jvm("java.util.HashMap#values()")
```

The unsafe trust is scoped precisely to the `extern` declaration. Everything above the `extern` layer — all public-facing Kestrel code — remains statically typed with no casts required.

#### `extern import` — auto-binding from class metadata (advanced)

For convenience when wrapping many methods, the compiler reads the `.class` file metadata and auto-generates `extern fun` stubs. Generic Java types become `Any` in the auto-generated stubs; specific methods can be overridden inline with precise Kestrel types:

```kestrel
extern import "java:java.util.HashMap" as HashMap {
  // Compiler auto-generates stubs from class file; override types you care about:
  fun get(m: HashMap, k: String): Option<String>
}
```

### Module Schemes

#### `java:` — JDK classes (always available, no import declaration needed)

```kestrel
// JDK types are always on the classpath — just use extern type/fun:
extern type HashMap = jvm("java.util.HashMap")
```

For auto-binding from class metadata, the `java:` scheme makes the source explicit:

```kestrel
extern import "java:java.util.HashMap" as HashMap { ... }
```

#### `maven:` — third-party jar classpath declaration

A bare `import "maven:..."` is a **classpath declaration only** — it makes the jar available for `extern` resolution within that file. It does not import names into scope:

```kestrel
import "maven:org.apache.commons:commons-lang3:3.20.0"

extern type ToStringBuilder = jvm("org.apache.commons.lang3.builder.ToStringBuilder")

extern fun append(b: ToStringBuilder, field: String, val: String): ToStringBuilder =
  jvm("org.apache.commons.lang3.builder.ToStringBuilder#append(java.lang.String,java.lang.String)")
```

The version coordinate lives in the source file — no separate manifest. This keeps each `.ks` file self-describing.

#### Version conflict detection via `.kdeps` sidecars

When the compiler emits `mymodule.class` it also writes `mymodule.kdeps` alongside it (a generated file, never hand-edited):

```json
{
  "maven": {
    "org.apache.commons:commons-lang3": "3.20.0"
  }
}
```

When the CLI assembles or runs a multi-module program, it reads `.kdeps` files transitively and reports any artifact with conflicting versions, pointing directly to the source files at fault:

```
Dependency conflict:
  myapp.ks requires org.apache.commons:commons-lang3:3.20.0
  util/text.ks requires org.apache.commons:commons-lang3:3.18.0

  Fix: align both imports to the same version.
```

There is no user-written manifest. Conflicts surface at link/run time, but the fix is always "edit the import in the offending source file".

### Intrinsic Migration

All existing `__*` compiler builtins in `codegen.ts` are migrated to `extern fun` declarations in the stdlib:

```kestrel
// Before (in stdlib/kestrel/string.ks):
export fun length(s: String): Int = __string_length(s)

// After:
extern fun length(s: String): Int = jvm("java.lang.String#length()")
```

This removes the bespoke `if (name === '__string_length') { ... }` blocks from `codegen.ts` entirely. New host-library integrations never require a compiler change.

### Worked Example — `kestrel:dict` Rewritten over `java.util.HashMap`

The `kestrel:dict` module is used as the primary integration test vehicle. The current implementation is a pure Kestrel association-list (O(n) operations). The rewritten version binds `java.util.HashMap` directly, demonstrates all `extern` constructs, and serves as a concrete acceptance test:

```kestrel
// stdlib/kestrel/dict.ks (HashMap-backed)

extern type JHashMap = jvm("java.util.HashMap")

extern fun jhmNew(): JHashMap                        = jvm("java.util.HashMap#<init>()")
extern fun jhmNewCopy(src: JHashMap): JHashMap       = jvm("java.util.HashMap#<init>(java.util.Map)")
extern fun jhmPut(m: JHashMap, k: Any, v: Any): Unit = jvm("java.util.HashMap#put(java.lang.Object,java.lang.Object)")
extern fun jhmRemove(m: JHashMap, k: Any): Unit      = jvm("java.util.HashMap#remove(java.lang.Object)")
extern fun jhmGet<V>(m: JHashMap, k: Any): V         = jvm("java.util.HashMap#get(java.lang.Object)")
extern fun jhmContains(m: JHashMap, k: Any): Bool    = jvm("java.util.HashMap#containsKey(java.lang.Object)")
extern fun jhmSize(m: JHashMap): Int                 = jvm("java.util.HashMap#size()")
extern fun jhmKeySet<K>(m: JHashMap): List<K>        = jvm("java.util.HashMap#keySet()")
extern fun jhmValues<V>(m: JHashMap): List<V>        = jvm("java.util.HashMap#values()")

// JHashMap is hidden behind the public opaque type —
// callers never see any Java type.
opaque type Dict<K, V> = JHashMap

export fun empty<K, V>(): Dict<K, V> = jhmNew()

export fun insert<K, V>(d: Dict<K, V>, k: K, v: V): Dict<K, V> = {
  val m = jhmNewCopy(d)
  jhmPut(m, k, v)
  m
}

export fun remove<K, V>(d: Dict<K, V>, k: K): Dict<K, V> = {
  val m = jhmNewCopy(d)
  jhmRemove(m, k)
  m
}

export fun get<K, V>(d: Dict<K, V>, k: K): Option<V> =
  if (jhmContains(d, k)) Some(jhmGet(d, k))
  else None

export fun member<K, V>(d: Dict<K, V>, k: K): Bool  = jhmContains(d, k)
export fun isEmpty<K, V>(d: Dict<K, V>): Bool       = jhmSize(d) == 0
export fun size<K, V>(d: Dict<K, V>): Int           = jhmSize(d)
export fun keys<K, V>(d: Dict<K, V>): List<K>       = jhmKeySet(d)
export fun values<K, V>(d: Dict<K, V>): List<V>     = jhmValues(d)
```

Key properties of this example:
- `opaque type Dict<K, V> = JHashMap` — the Java type is fully hidden; the public API is unchanged
- `insert`/`remove` are copy-on-write — Kestrel's immutability contract is preserved
- `empty()` takes no hash/equality arguments — `HashMap` uses `.equals()`/`.hashCode()` on keys natively, which simplifies the API relative to the current association-list implementation
- Parametric `extern fun` (`jhmGet<V>`, `jhmKeySet<K>`, `jhmValues<V>`) absorb Java type erasure without any cast expression in caller code
- The existing `dict.test.ks` test suite passes unchanged — the rewrite is a drop-in replacement

## Stories (ordered — implement sequentially)

1. [x] [S02-01-extern-type-ast-parser-typecheck.md](../../done/S02-01-extern-type-ast-parser-typecheck.md) — `extern type` AST node, parser grammar, typecheck registration
2. [x] [S02-02-extern-fun-non-parametric-ast-parser-typecheck-codegen.md](../../done/S02-02-extern-fun-non-parametric-ast-parser-typecheck-codegen.md) — `extern fun` (non-parametric) full pipeline: AST, parser, typecheck, JVM codegen
3. [S02-03-extern-fun-parametric-type-params-checkcast.md](../../unplanned/S02-03-extern-fun-parametric-type-params-checkcast.md) — `extern fun` (parametric) type params + `checkcast` emission
4. [S02-04-migrate-char-intrinsics-to-extern-fun.md](../../unplanned/S02-04-migrate-char-intrinsics-to-extern-fun.md) — Migrate `char.ks` intrinsics (`__char_code_point`, `__char_from_code`, `__char_to_string`)
5. [S02-05-migrate-string-intrinsics-to-extern-fun.md](../../unplanned/S02-05-migrate-string-intrinsics-to-extern-fun.md) — Migrate `string.ks` intrinsics (10 `__string_*`; fix `stack.test.ks` direct calls)
6. [S02-06-migrate-basics-numeric-float-time-intrinsics.md](../../unplanned/S02-06-migrate-basics-numeric-float-time-intrinsics.md) — Migrate `basics.ks` intrinsics (9 float/numeric + `__now_ms`)
7. [S02-07-migrate-stack-format-trace-intrinsics.md](../../unplanned/S02-07-migrate-stack-format-trace-intrinsics.md) — Migrate `stack.ks` intrinsics (`__format_one`, `__print_one`, `__capture_trace`)
8. [S02-08-migrate-fs-async-io-intrinsics.md](../../unplanned/S02-08-migrate-fs-async-io-intrinsics.md) — Migrate `fs.ks` async I/O intrinsics (`__read_file_async`, `__list_dir`, `__write_text`)
9. [S02-09-migrate-process-env-intrinsics.md](../../unplanned/S02-09-migrate-process-env-intrinsics.md) — Migrate `process.ks` intrinsics (`__get_os`, `__get_args`, `__get_cwd`, `__run_process`)
10. [S02-10-migrate-task-combinator-intrinsics.md](../../unplanned/S02-10-migrate-task-combinator-intrinsics.md) — Migrate `task.ks` task combinator intrinsics (4 `__task_*`)
11. [S02-11-dict-rewrite-over-hashmap.md](../../unplanned/S02-11-dict-rewrite-over-hashmap.md) — `kestrel:dict` rewrite over `java.util.HashMap` (integration test vehicle)
12. [S02-12-maven-classpath-scheme-and-kdeps-sidecars.md](../../unplanned/S02-12-maven-classpath-scheme-and-kdeps-sidecars.md) — `maven:` classpath declaration scheme + `.kdeps` conflict detection
13. [S02-13-extern-import-auto-binding-optional.md](../../unplanned/S02-13-extern-import-auto-binding-optional.md) — `extern import` auto-binding from class metadata **(Optional)**

**Story dependencies:**
- S02-01, S02-02, S02-03 are strictly sequential; each blocks the next.
- S02-04 through S02-10 depend on S02-01 + S02-02 + S02-03 and are otherwise independent; can be implemented in any order.
- S02-07 additionally depends on S02-03 (parametric `extern fun` required for `capture_trace<T>`).
- S02-08, S02-09 (partial: `__run_process`), S02-10 require async `extern fun` support (Task<T> return); for this epic build run, that support is folded into S02-02 so later stories remain unblocked.
- S02-11 depends on S02-01 + S02-02 + S02-03 and benefits from S02-04 being complete first (char type in dict keys).
- S02-12 depends on S02-01 + S02-02 only; independent of all migration stories.
- S02-13 is Optional and depends on S02-01 + S02-02 + S02-03; this build run includes S02-13.

## Dependencies

- Epic E01 async runtime foundation completed and stable (Task semantics and virtual-thread execution are required for async host-library calls).
- JVM-only backend direction remains in force (interop is JVM-host specific).
- Existing stdlib/spec baseline in `docs/specs/02-stdlib.md`, `docs/specs/06-typesystem.md`, and `docs/specs/09-tools.md` available to extend.

## Related

- **E04** (Module Resolution and Reproducibility): covers URL-based Kestrel module resolution and lockfiles. The `maven:` jar resolution design in E02 should align with E04's caching and reproducibility conventions.

## Epic Completion Criteria

- `extern type` and `extern fun` declarations (including parametric form) are supported by the parser, type checker, and JVM code generator with direct bytecode emission (`invokevirtual`/`invokestatic`/`invokespecial`/`checkcast`); no reflection for resolved bindings.
- The `java:` module scheme is recognised by the compiler and resolves JDK types at compile time.
- The `maven:` classpath declaration scheme is recognised; jars are resolved and `.kdeps` sidecar files are emitted; conflicting versions across a program are reported with source locations pointing to the offending import.
- `extern import` with class-metadata auto-binding is supported, with per-method type overrides.
- `kestrel:dict` is rewritten to use `java.util.HashMap` via `extern` bindings and passes the existing `dict.test.ks` suite unchanged — demonstrating a complete end-to-end integration test of all `extern` constructs including parametric `extern fun`.
- All existing `__*` intrinsic builtins in `codegen.ts` are migrated to `extern fun` declarations in the stdlib; the `if (name === '__...')` dispatch blocks are removed from the code generator.
- Behavioural parity with the former intrinsic path is verified: all existing conformance, compiler, stdlib, and E2E test suites pass.
- Performance of hot operations (string, char, numeric primitives) is validated to be no worse than the intrinsic path.
- New language constructs (`extern type`, `extern fun`, `extern import`) are documented in `docs/specs/01-language.md` and `docs/specs/07-modules.md`.
