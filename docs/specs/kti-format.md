# `.kti` Types File — Concrete Format Reference

This document is the canonical reference for the `.kti` types-file format used by the Kestrel compiler. It supplements `docs/specs/07-modules.md §5` with concrete field-by-field JSON encoding details.

---

## 1. Overview

A `.kti` file is a UTF-8 JSON text file that carries the compile-time export metadata for one Kestrel package. It is the only artifact that a dependent package needs in order to typecheck and generate JVM bytecode against a dependency — no re-parsing of the dependency's source is required.

**File extension:** `.kti` (Kestrel Types Interface)

**Placement:** alongside the compiled `.class` file for the same package (same directory, same base name).

**Versioning:** the top-level `version` field is a positive integer. Readers **must** reject a `.kti` whose `version` they do not support and fall through to a full recompile from source. The current version is **4** (see §8 for history).

---

## 2. Top-level structure

```json
{
  "version": 4,
  "functions": { ... },
  "types": { ... },
  "sourceHash": "<hex-sha256>",
  "depHashes": { "<absPath>": "<hex-sha256>", ... },
  "codegenMeta": { ... }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | `number` | always | Format version integer. Readers must reject unsupported values. |
| `functions` | `object` | always | Map from export name (string) to export entry object. Every exported function, value, variable, constructor and type alias entry lives here. |
| `types` | `object` | v1+ | Map from type name (string) to type export entry. Contains exported and opaque type declarations. May be empty but must be present. |
| `sourceHash` | `string` | v4 | Lowercase hex SHA-256 of the source file bytes that produced this `.kti`. Used for cache invalidation (§5.2 in 07-modules.md). |
| `depHashes` | `object` | v4 | Map from **absolute path** of each direct dependency to that dependency's `sourceHash` value. Used for transitive invalidation. Keys use the same path form as the in-process cache (`compile-file-jvm.ts`). |
| `codegenMeta` | `object` | v4 | JVM codegen metadata extracted from the compiled Program AST. Allows a `.kti`-loaded dependency to provide all data needed by JVM codegen without re-parsing. See §6. |

---

## 3. Export entry kinds (`functions` map)

Each value in the `functions` object is an **export entry** object with at minimum a `kind` field. The `type` field (when present) is a `SerType` (§4).

### 3.1 `function`

An exported function or extern function.

```json
{
  "kind": "function",
  "function_index": 3,
  "arity": 2,
  "type": { "k": "arrow", "ps": [{ "k": "prim", "n": "Int" }, { "k": "prim", "n": "Int" }], "r": { "k": "prim", "n": "Int" } }
}
```

| Field | Description |
|-------|-------------|
| `function_index` | Index into the package's function table (spec 03 §6.1). |
| `arity` | Number of parameters. |
| `type` | Type scheme of the function. |

### 3.2 `val`

An exported immutable value (0-arity getter).

```json
{
  "kind": "val",
  "function_index": 5,
  "type": { "k": "prim", "n": "Int" }
}
```

| Field | Description |
|-------|-------------|
| `function_index` | Getter index in the function table. |
| `type` | Type of the value. |

### 3.3 `var`

An exported mutable variable with a getter and a setter.

```json
{
  "kind": "var",
  "function_index": 6,
  "setter_index": 7,
  "type": { "k": "prim", "n": "Int" }
}
```

| Field | Description |
|-------|-------------|
| `function_index` | Getter index (0-arity function). |
| `setter_index` | Setter index (1-arity function). Both indices are in the same package's function table. |
| `type` | Type of the variable. |

Writers **must** emit `setter_index` for every `var` entry. Readers that do not support `var` mutation may ignore `setter_index`, but they must not hard-error on its presence.

### 3.4 `constructor`

One exported constructor of a non-opaque ADT. One entry per constructor per non-opaque ADT.

```json
{
  "kind": "constructor",
  "adt_id": 0,
  "ctor_index": 1,
  "arity": 2,
  "type": { "k": "scheme", "vs": [0], "b": { "k": "arrow", "ps": [...], "r": { "k": "app", "n": "Maybe", "as": [{ "k": "var", "id": 0 }] } } }
}
```

| Field | Description |
|-------|-------------|
| `adt_id` | Opaque identifier for the ADT within the package. Used to group constructors of the same type. |
| `ctor_index` | Index of this constructor within the ADT (0-based). |
| `arity` | Number of constructor parameters. |
| `type` | Constructor scheme type. |

Opaque ADTs omit constructor entries.

### 3.5 `type` (alias or opaque)

A type alias or opaque type exported from the package. Also used for exception declarations.

```json
{
  "kind": "type",
  "type": { "k": "app", "n": "List", "as": [{ "k": "prim", "n": "String" }] },
  "opaque": false
}
```

| Field | Description |
|-------|-------------|
| `type` | Underlying type (omitted or `{ "k": "opaque" }` for opaque aliases/types). |
| `opaque` | `true` if the type is exported opaquely. |

---

## 4. SerType encoding

`SerType` is the JSON serialization of `InternalType` from `compiler/src/types/internal.ts`. All `SerType` objects have a `k` field (the kind discriminator). Each variant:

### 4.1 Primitive

```json
{ "k": "prim", "n": "Int" }
```

`n` is one of: `"Int"`, `"Float"`, `"Bool"`, `"String"`, `"Unit"`, `"Char"`, `"Rune"`.

### 4.2 Type variable

```json
{ "k": "var", "id": 3 }
```

`id` is the numeric type variable identifier. Only meaningful in the context of an enclosing `scheme`.

### 4.3 Arrow (function type)

```json
{ "k": "arrow", "ps": [<SerType>, ...], "r": <SerType> }
```

`ps` is the parameter type array (may be empty for 0-arity). `r` is the return type.

### 4.4 Record

```json
{
  "k": "record",
  "fs": [{ "n": "x", "mut": false, "t": { "k": "prim", "n": "Int" } }],
  "row": <SerType> | null
}
```

`fs` is the array of field descriptors (`n` = field name, `mut` = mutable flag, `t` = field type). `row` is the optional row-type extension variable (null or omitted if closed).

### 4.5 Type application

```json
{ "k": "app", "n": "List", "as": [<SerType>] }
```

`n` is the type constructor name. `as` is the array of type arguments.

### 4.6 Tuple

```json
{ "k": "tuple", "es": [<SerType>, <SerType>] }
```

`es` is the array of element types.

### 4.7 Union

```json
{ "k": "union", "l": <SerType>, "r": <SerType> }
```

### 4.8 Intersection

```json
{ "k": "inter", "l": <SerType>, "r": <SerType> }
```

### 4.9 Scheme (universally quantified type)

```json
{ "k": "scheme", "vs": [0, 1], "b": <SerType> }
```

`vs` is the list of bound type variable ids. `b` is the quantified body.

### 4.10 Opaque sentinel

```json
{ "k": "opaque" }
```

Used as the `type` field value for opaque type aliases/exports to explicitly indicate that the underlying structure is hidden.

### 4.11 Namespace (scope-only, not exported)

`{ "k": "namespace", ... }` is an internal inference type that is **never written** to a `.kti` file. Compiler readers may safely assume this kind never appears in a `.kti`.

---

## 5. v4 additions

### 5.1 `sourceHash`

```
"sourceHash": "a3f2e1b4c5d607e8..."
```

Lowercase hexadecimal SHA-256 of the **raw bytes** of the source `.ks` file that was compiled to produce this `.kti`. The hash is computed before the compiler transforms the source in any way. Used as a correctness guard for the slow-path freshness check (see `07-modules.md §5.2`).

### 5.2 `depHashes`

```json
"depHashes": {
  "/absolute/path/to/dep.ks": "b1c2d3e4...",
  "/absolute/path/to/other.ks": "c2d3e4f5..."
}
```

A JSON object mapping the **absolute file path** of each **direct dependency** to that dependency's `sourceHash`. Used for transitive invalidation: if a dep's source has changed since this `.kti` was written, the dep-hash entry will no longer match the dep's current `.kti.sourceHash`, invalidating this `.kti` even though this package's own source has not changed.

Keys must be absolute paths in the same form as the keys of the in-process `cache` Map in `compile-file-jvm.ts` (resolved to an absolute, normalized POSIX path). Only **direct** dependencies appear here; transitive deps are handled recursively when their own packages are loaded.

### 5.3 `codegenMeta`

See §6 for full sub-field specification.

---

## 6. `codegenMeta` sub-fields

`codegenMeta` carries JVM codegen metadata for all exported names. This allows a consumer (a package that imports this package) to emit JVM bytecode for calls, field accesses, and ADT construction without re-parsing the dependency's source.

```json
"codegenMeta": {
  "funArities": { "add": 2, "empty": 0 },
  "asyncFunNames": ["fetch"],
  "varNames": ["counter"],
  "valOrVarNames": ["counter", "pi"],
  "adtConstructors": [
    {
      "typeName": "Maybe",
      "constructors": [
        { "name": "Some", "params": 1 },
        { "name": "None", "params": 0 }
      ]
    }
  ],
  "exceptionDecls": [
    { "name": "MyError", "arity": 1 }
  ]
}
```

| Sub-field | Type | Description |
|-----------|------|-------------|
| `funArities` | `{ [name: string]: number }` | Arity (param count) of every exported function and extern function. |
| `asyncFunNames` | `string[]` | Names of exported functions (and extern funs) that are async — i.e., return a `Task`. |
| `varNames` | `string[]` | Names of exported `var` declarations (mutable variables). Used by JVM codegen to emit setter calls on assignment. |
| `valOrVarNames` | `string[]` | Names of exported `val` **and** `var` declarations (all value-like exports). Superset of `varNames`. |
| `adtConstructors` | `CtorGroup[]` | One entry per exported **non-opaque** ADT. Each entry has `typeName` (the ADT type name) and `constructors` (array of `{ name, params }`). Used to build JVM inner-class names like `ClassName$TypeName$CtorName`. |
| `exceptionDecls` | `ExnEntry[]` | One entry per exported exception declaration. Each entry has `name` and `arity` (number of exception fields). |

**`CtorGroup`:**
```json
{ "typeName": "Maybe", "constructors": [{ "name": "Some", "params": 1 }, { "name": "None", "params": 0 }] }
```

**`ExnEntry`:**
```json
{ "name": "MyError", "arity": 1 }
```

**Notes:**
- `adtConstructors` includes **all** exported non-opaque ADTs — not just those whose constructors appear in the `functions` map. The `functions` map may contain `constructor` kind entries for the same constructors, but `codegenMeta.adtConstructors` provides the grouped data structure needed for inner-class name generation.
- Opaque ADTs are **excluded** from `adtConstructors`.
- `funArities`, `asyncFunNames`, `varNames`, and `valOrVarNames` only include **exported** names (names in the module's export list).

---

## 7. Full example

Source: a small module `Counter.ks` that exports a `var counter`, a function `increment`, and an ADT `Color`.

```json
{
  "version": 4,
  "functions": {
    "counter": {
      "kind": "var",
      "function_index": 0,
      "setter_index": 1,
      "type": { "k": "prim", "n": "Int" }
    },
    "increment": {
      "kind": "function",
      "function_index": 2,
      "arity": 1,
      "type": {
        "k": "arrow",
        "ps": [{ "k": "prim", "n": "Int" }],
        "r": { "k": "prim", "n": "Int" }
      }
    },
    "Red": {
      "kind": "constructor",
      "adt_id": 0,
      "ctor_index": 0,
      "arity": 0,
      "type": { "k": "app", "n": "Color", "as": [] }
    },
    "Green": {
      "kind": "constructor",
      "adt_id": 0,
      "ctor_index": 1,
      "arity": 0,
      "type": { "k": "app", "n": "Color", "as": [] }
    }
  },
  "types": {
    "Color": {
      "visibility": "export",
      "kind": "adt",
      "constructors": [
        { "name": "Red", "params": [] },
        { "name": "Green", "params": [] }
      ]
    }
  },
  "sourceHash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "depHashes": {
    "/abs/path/to/Prelude.ks": "a3f2e1b4c5d607e8fa91b23456789abc"
  },
  "codegenMeta": {
    "funArities": { "increment": 1 },
    "asyncFunNames": [],
    "varNames": ["counter"],
    "valOrVarNames": ["counter"],
    "adtConstructors": [
      {
        "typeName": "Color",
        "constructors": [
          { "name": "Red", "params": 0 },
          { "name": "Green", "params": 0 }
        ]
      }
    ],
    "exceptionDecls": []
  }
}
```

---

## 8. Version history

| Version | Added in | What changed |
|---------|----------|--------------|
| 1 | S20–S30 (old VM pipeline) | Initial format: `version`, `functions` (function/val/var kinds), `SerType` encoding |
| 2 | S30+ | `setter_index` for `var` kind; type serialization covers all `InternalType` variants |
| 3 | S30-types-file-full-spec07 | `constructor` export entries for non-opaque ADT constructors; `types` map for type aliases and opaque declarations |
| 4 | S07-01 (E07 Incremental Compilation) | `sourceHash`, `depHashes`, `codegenMeta` — enables incremental compilation without re-parsing in JVM pipeline |
