# Union and Intersection Types: Full Runtime Support

## Sequence: 14
## Tier: 3 — Complete the core language
## Former ID: 145

## Summary

Union (`A | B`) and intersection (`A & B`) types are parsed and represented in the type system (InternalType has `union` and `inter` variants). However, runtime support is limited -- there's no runtime type tag for union/intersection values, and the type checker may erase them during codegen. Full support requires `is` narrowing (sequence **13**) and possibly runtime type information.

## Current State

- Parser: Union and intersection types parsed.
- Type system: `union` and `inter` InternalType variants exist. Narrowing types noted in spec 06 §4.
- Codegen: Union/intersection types likely erased (not encoded in bytecode type table).
- VM: No concept of union/intersection at runtime.
- `unify()` may lack cases for union/intersection, causing inference failures in some programs.

## Dependencies

- Sequence **13** (`is` type narrowing) is a prerequisite.

## Acceptance Criteria

- [ ] A function declared as `fun f(x: Int | String): Unit` can accept both Int and String arguments.
- [ ] `is` narrowing (sequence **13**) works with union types: `if (x is Int) { ... } else { ... }`.
- [ ] Type table encoding (03 §6.3) can represent union/intersection types (may need new type tags or they may remain erased with the information used only at compile time).
- [ ] Kestrel test: function accepting union type, using `is` to narrow.
- [ ] Kestrel test: intersection type in record extension context.

## Spec References

- 06-typesystem §1 (Union/intersection grammar)
- 06-typesystem §4 (Narrowing with `is`)
