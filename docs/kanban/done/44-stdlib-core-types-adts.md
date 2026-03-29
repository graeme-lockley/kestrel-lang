# Stdlib: Implement Option, Result, List, Value as Kestrel ADTs


## Sequence: 44
## Former ID: (none)
## Description

The stdlib modules `option.ks`, `result.ks`, `list.ks`, `value.ks` are stubs (`val _ = ()`). Per spec 02 and IMPLEMENTATION_PLAN Phase 5.2: implement these as Kestrel ADTs with constructors (Some/None, Ok/Err, Nil/Cons, Null/Bool/Int/Float/String/Array/Object).

These types underpin the stdlib API (e.g. `queryParam` returns `Option<String>`, `parse` returns `Value`).

## Acceptance Criteria

- [x] option.ks: Option\<T\> with Some(x), None; export type and constructors
- [x] result.ks: Result\<T,E\> with Ok(x), Err(e); export type and constructors
- [x] list.ks: List\<T\> with Nil, Cons(head, tail); special syntax [a,b,...c], :: ; export type and constructors
- [x] value.ks: Value ADT for JSON (Null, Bool, Int, Float, String, Array, Object) per spec 02
- [x] Compile to .kbc; E2E or typecheck conformance that uses these types

## Tasks

- [x] option.ks: Ensure Option\<T\> with Some/None documented and helpers exported; compiles
- [x] result.ks: Ensure Result\<T,E\> with Ok/Err documented and helpers exported; compiles
- [x] list.ks: Ensure List\<T\> with Nil/Cons and syntax documented and helpers exported; compiles
- [x] value.ks: Value ADT (Null, Bool, Int, Float, String, Array, Object) with helpers; compiles
- [x] Conformance: compile stdlib to .kbc; verify unit tests (option, result, list, value) pass
