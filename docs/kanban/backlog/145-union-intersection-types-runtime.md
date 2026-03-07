# Union and Intersection Types: Full Runtime Support

## Priority: 145 (Low)

## Summary

Union (`A | B`) and intersection (`A & B`) types are parsed and represented in the type system (InternalType has `union` and `inter` variants). However, runtime support is limited -- there's no runtime type tag for union/intersection values, and the type checker may erase them during codegen. Full support requires `is` narrowing (story 12) and possibly runtime type information.

## Current State

- Parser: Union and intersection types parsed.
- Type system: `union` and `inter` InternalType variants exist. Narrowing types noted in spec 06 &sect;4.
- Codegen: Union/intersection types likely erased (not encoded in bytecode type table).
- VM: No concept of union/intersection at runtime.
- This story depends on story 12 (`is` type narrowing) for practical usage.

## Acceptance Criteria

- [ ] A function declared as `fun f(x: Int | String): Unit` can accept both Int and String arguments.
- [ ] `is` narrowing (story 12) works with union types: `if (x is Int) { ... } else { ... }`.
- [ ] Type table encoding (03 &sect;6.3) can represent union/intersection types (may need new type tags or they may remain erased with the information used only at compile time).
- [ ] Kestrel test: function accepting union type, using `is` to narrow.
- [ ] Kestrel test: intersection type in record extension context.

## Dependencies

- Story 12 (`is` type narrowing) is a prerequisite.

## Spec References

- 06-typesystem &sect;1 (Union/intersection grammar)
- 06-typesystem &sect;4 (Narrowing with `is`)
