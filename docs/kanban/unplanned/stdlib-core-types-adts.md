# Stdlib: Implement Option, Result, List, Value as Kestrel ADTs

## Description

The stdlib modules `option.ks`, `result.ks`, `list.ks`, `value.ks` are stubs (`val _ = ()`). Per spec 02 and IMPLEMENTATION_PLAN Phase 5.2: implement these as Kestrel ADTs with constructors (Some/None, Ok/Err, Nil/Cons, Null/Bool/Int/Float/String/Array/Object).

These types underpin the stdlib API (e.g. `queryParam` returns `Option<String>`, `parse` returns `Value`).

## Acceptance Criteria

- [ ] option.ks: Option\<T\> with Some(x), None; export type and constructors
- [ ] result.ks: Result\<T,E\> with Ok(x), Err(e); export type and constructors
- [ ] list.ks: List\<T\> with Nil, Cons(head, tail); special syntax [a,b,...c], :: ; export type and constructors
- [ ] value.ks: Value ADT for JSON (Null, Bool, Int, Float, String, Array, Object) per spec 02
- [ ] Compile to .kbc; E2E or typecheck conformance that uses these types
