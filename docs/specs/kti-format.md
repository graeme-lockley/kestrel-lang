# Types File (.kti) Format (Reference Implementation)

This document describes the concrete .kti format produced and consumed by the reference compiler (07 §5). It complements [07-modules.md](07-modules.md) §5.1.

## Version

- **Top-level `version`** (number): currently **1**. Consumers must reject files with an unsupported or missing version.

## Export kinds and required fields

All value/function exports appear in the **`functions`** object (map from export name to entry). Each entry has:

- **`kind`**: `"function"` | `"val"` | `"var"`
- **`type`**: serialized type (see below)
- **`function_index`** (number): index into the package’s function table (03 §6.1)

By kind:

- **function:** `arity` (number) required.
- **val:** Getter only (0-arity); no extra fields.
- **var:** **`setter_index`** (number) required; index of the 1-arity setter in the same function table. Both getter and setter indices are required so importers can emit CALL getter (read) and CALL setter (assign).

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

- **Round-trip:** Writing a .kti and reading it back preserves all fields for function, val, var, and type exports, and all type structure (including union, intersection, record with row, scheme).
- **Tests:** `compiler/test/unit/types-file.test.ts` (round-trip for all kinds and type forms); `compiler/test/integration/compile-file.test.ts` (export var + importer assigns, bytecode has getter and setter in imported function table).
