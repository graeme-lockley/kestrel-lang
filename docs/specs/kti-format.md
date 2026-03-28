# Types File (.kti) Format (Reference Implementation)

This document describes the concrete .kti format produced and consumed by the reference compiler (07 §5). It complements [07-modules.md](07-modules.md) §5.1.

## Version

- **Top-level `version`** (number): currently **3** in the reference compiler. Consumers must reject files with an unsupported or missing version. Version **3** adds **`constructor`** export entries for non-opaque exported ADTs (namespace-qualified construction and `.kti`-only consumers; see 07 §5.1).

## Export kinds and required fields

All exports appear in the **`functions`** object (map from export name to entry). Common fields depend on `kind` (see reference `types-file.ts`):

- **`kind`**: `"function"` | `"val"` | `"var"` | `"constructor"` | `"type"` | `"exception"`
- **`type`**: serialized type (see below) where applicable.

By kind:

- **function:** **`function_index`** (number, 03 §6.1), **`arity`** (number).
- **val:** **`function_index`** (number); getter only (0-arity).
- **var:** **`function_index`** (getter), **`setter_index`** (number, 1-arity setter); both indices are into the same package function table (03 §6.1).
- **exception:** `kind` = `"exception"`, **`type`** only (no `function_index`; exception ADT metadata is elsewhere).

- **constructor:** `kind` = `"constructor"`, **`adt_id`** (u32 index into the **dependency** package’s bytecode ADT table, 03 §10), **`ctor_index`** (0-based constructor tag within that ADT), **`arity`** (number), **`type`** (serialized constructor scheme: `T` for nullary, `(A1,…) -> T` for n-ary). No `function_index` — lowering uses **CONSTRUCT_IMPORT** (04 §1.7). Opaque ADT constructors are not emitted.

Type alias and opaque type exports are also stored in **`functions`** with **`kind`** = `"type"`, and optional **`opaque`** (boolean). Opaque entries do not expose the underlying type structure.

## Type encoding (SerType)

The **`type`** field is a JSON object with a **`kind`** discriminator. Supported kinds:

| kind      | Description | Extra fields |
|----------|-------------|--------------|
| `prim`   | Primitive    | `name`: "Int" \| "Float" \| "Bool" \| "String" \| "Unit" \| "Char" \| "Rune" |
| `arrow`  | Function     | `params`: SerType[], `return`: SerType |
| `record` | Record       | `fields`: { name, mut, type }[], optional `row`: SerType |
| `app`    | Type application | `name`: string, `args`: SerType[] |
| `tuple`  | Tuple        | `elements`: SerType[] |
| `union`  | Union        | `left`: SerType, `right`: SerType |
| `inter`  | Intersection | `left`: SerType, `right`: SerType |
| `var`    | Type variable | `id`: number (0-based index within scheme, or global id) |
| `scheme` | Quantified   | `varCount`: number, `body`: SerType (vars in body referenced by 0-based index) |

All forms are recursive. Round-trip is guaranteed for the full InternalType set used by the type checker (06).

## Round-trip and tests

- **Round-trip:** Writing a .kti and reading it back preserves all fields for function, val, var, constructor (when present), and type exports, and all type structure (including union, intersection, record with row, scheme).
- **Tests:** `compiler/test/unit/types-file.test.ts` (round-trip for all kinds and type forms, including `constructor`); `compiler/test/integration/compile-file.test.ts` (export var + importer assigns; namespace ADT constructors; `.kti`-only dependency).
