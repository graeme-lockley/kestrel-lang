# Sketch: Assign to imported `export var` from another module

## Goal

Allow `hello := "x"` in hello.ks when `hello` is imported from m3.ks (`import { hello } from "./m3.ks"`), so that the exporting module’s global is updated and future reads of `hello` (in any module) see the new value.

## Current behaviour

- **Exporter (m3):** `export var hello` compiles to:
  - Init: store initial value in `module.globals[slot]`.
  - One 0-arity **getter** in the function table: `LOAD_GLOBAL slot; RET`.
- **Importer (hello.ks):** `hello` is bound to the getter (imported function index). So `hello` and `println(hello)` compile to `CALL getter 0` → load m3’s global and return it.
- Assignment to `hello` in hello.ks is invalid: codegen only allows assignment to names in the local/env (no setter).

## Approach: getter + setter

For each `export var name`, the **exporter** emits two functions:

1. **Getter** (existing): 0-arity, `LOAD_GLOBAL slot; RET`.
2. **Setter** (new): 1-arity, takes the new value as argument; body is `STORE_GLOBAL slot; RET` (argument is in local 0).

The **importer** must know both indices so it can:

- Use the getter for `hello` and `println(hello)` → `CALL getter 0`.
- Use the setter for `hello := expr` → emit `expr`, then `CALL setter 1`.

VM needs no change: a call to the setter is a normal cross-module call; the setter runs in the exporter’s module and writes to that module’s `globals[slot]`.

---

## 1. Compiler (exporter): emit setter

**Codegen (e.g. codegen.ts)**  
After emitting the getter for a `VarDecl`:

- Emit a second function:
  - Arity 1.
  - Body: `LOAD_LOCAL 0` (argument) → `STORE_GLOBAL slot` → `RET`.
- Append it to the function table (so getter and setter have two consecutive indices, or at least both are in the table).

**Export metadata**

- Today: for a var we put in typeExports / .kti: `kind: 'var'`, `function_index` (getter), `type`.
- Add: **setter_index** (index of the setter in the same function table).

So .kti for a var looks like:

```json
"hello": { "kind": "var", "function_index": 0, "setter_index": 1, "type": { "kind": "prim", "name": "String" } }
```

(Exact indices depend on how many other functions exist in the module.)

---

## 2. Compiler (importer): know getter and setter

**compile-file.ts**

- When building the imported function table from a dependency’s **.kti** (or from its codegen result), for each imported name:
  - If export is **function** or **val**: one entry as today (importIndex, functionIndex).
  - If export is **var**: two entries:
    1. (importIndex, getter function_index)
    2. (importIndex, setter setter_index)
- So `importedFunctionTable` might look like:  
  `[..., (m3, getter_hello), (m3, setter_hello)]`.
- **importedFuncIds:** map `'hello'` → the **getter** index in this table (used for `CALL` when evaluating `hello`).
- **importedVarSetterIds** (new): map `'hello'` → the **setter** index in the same table (used for `hello := expr`).

When building from a **compiled dependency** (not .kti), you need the dependency’s codegen to expose getter and setter indices for vars the same way (e.g. in export metadata / getExportSet), and then push two entries per var and fill `importedFuncIds` and `importedVarSetterIds`.

---

## 3. Codegen (importer): AssignStmt for imported var

**codegen.ts**  
In the branch that handles `AssignStmt` with an `IdentExpr` target (e.g. `hello := expr`):

- If `env.get(target.name)` is defined → current behaviour (assign to local/global in this module).
- Else if `options?.importedVarSetterIds?.get(target.name)` is defined:
  - Emit `expr` (value).
  - Emit `CALL setterId 1` (one argument).
- Else → throw “assign to unknown …” as today.

So `hello := "hello"` in hello.ks becomes: push `"hello"`, then `CALL setter_id 1`. The VM runs the setter in m3, which does `STORE_GLOBAL 0` and returns; m3’s `globals[0]` is updated.

---

## 4. Typechecker

- Assigning to an imported var is type-checked like a normal assignment: the RHS type must match the var’s type (from import bindings). No change to type rules beyond ensuring the imported binding is typed (already the case for val/var in .kti).

---

## 5. .kti format

Extend var export to include `setter_index`:

- **function:** `kind`, `function_index`, `arity`, `type`.
- **val:** `kind`, `function_index`, `type`.
- **var:** `kind`, `function_index`, `setter_index`, `type`.

Readers that only care about “callable” exports (getter) can keep using `function_index`; code that handles assignment uses `setter_index` when building the importer’s setter table.

---

## 6. Summary of code touchpoints

| Layer        | Change |
|-------------|--------|
| **codegen** | For each `VarDecl`, emit getter (existing) and setter (1-arity, `LOAD_LOCAL 0`; `STORE_GLOBAL slot`; `RET`). Record both indices for typeExports. |
| **types-file** | Var export: add `setter_index`. Write/read it. |
| **compile-file** | When building imported function table from .kti (or dep result), for var push getter then setter; set `importedFuncIds` (getter) and `importedVarSetterIds` (setter). Pass `importedVarSetterIds` into codegen. |
| **codegen** | AssignStmt: if target is ident and not in env, try `importedVarSetterIds`; if present, emit value + `CALL setterId 1`. |
| **VM**      | No change (setter is a normal 1-arity imported function). |

---

## 7. Edge cases

- **Rebuilding / cache:** After adding setter emission, recompile exporters (e.g. m3) so their .kbc/.kti have the setter and new .kti shape; importers will then get both getter and setter indices.
- **Read-only view:** If you ever want “import hello but not allow assignment”, you could restrict that at typecheck (e.g. a different import kind or a modifier); for this sketch, any importer that imports a var can assign to it if the type matches.

This sketch is enough to implement “assign to var hello outside of m3” end-to-end.

---

## 8. Implementation status

The above is implemented. The .kti format matches §5: var entries include `function_index` (getter) and `setter_index` (setter). Round-trip and integration tests validate that all export kinds and type forms are preserved, and that the importer's bytecode includes getter and setter entries in the imported function table (03 §6.6). See compiler test: `compiler/test/unit/types-file.test.ts` (round-trip) and `compiler/test/integration/compile-file.test.ts` (export var + import and assign).
