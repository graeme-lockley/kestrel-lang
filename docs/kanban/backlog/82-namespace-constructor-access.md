# Namespace constructor access (`M.Ctor(args)`)

## Priority: 82 (Medium)

## Summary

Allow calling **exported** ADT constructors through a namespace, e.g. `import * as Lib from "lib.ks"` then `Lib.PubNum(42)` when `PublicToken` is an exported type with constructor `PubNum(Int)`.

## Scope

- **In scope**: For a namespace `M` and an exported (non-opaque) ADT, treat constructor names as names visible on `M`. Typecheck `M.Ctor(args)` and emit CONSTRUCT using the dependency's ADT/constructor (same as named import of the constructor would).
- **Out of scope**: Opaque types' constructors remain inaccessible (no change to 15-opaque-types).

## Acceptance Criteria

- [ ] **.kti / compile-file**: Exported ADT constructors are represented in the dependency's export info (e.g. in .kti or equivalent) so the importer knows `PubNum` exists and which adt_id/ctor index to use.
- [ ] **Type checker**: When `M.name` is a constructor of an exported ADT from the dependency, resolve to the constructor's type (e.g. `(Int) -> PublicToken`).
- [ ] **Codegen**: For `M.Ctor(args)`, resolve to the dependency's CONSTRUCT (adt_id, ctor index, arity) and emit CONSTRUCT with correct indices.
- [ ] Typecheck invalid: `M.Ctor` when `Ctor` is not a constructor of any exported type from that module (e.g. typo or constructor of an opaque type).
- [ ] Kestrel test: e.g. `import * as Lib from "../fixtures/opaque_pkg/lib.ks"` then `val x: Lib.PublicToken = Lib.PubNum(42)` and `Lib.publicTokenToInt(x) === 42`.

## Notes

- Namespace imports (80) already support val, var, fun, and type names (including qualified type annotations like `Lib.PublicToken`). This story adds **constructor** names to the namespace binding set and codegen for `M.Ctor(args)`.
