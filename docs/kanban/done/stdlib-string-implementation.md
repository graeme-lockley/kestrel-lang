# Stdlib: Implement kestrel:string

## Description

`stdlib/kestrel/string.ks` is a stub. Per spec 02: implement length, slice, indexOf, equals, toUpperCase. Each takes the string as an explicit argument. Calls VM string primitives (e.g. `__string_length`) for operations the language cannot do.

## Acceptance Criteria

- [x] length(String): Int
- [x] slice(String, Int, Int): String
- [x] indexOf(String, String): Int
- [x] equals(String, String): Bool
- [x] toUpperCase(String): String
- [x] E2E: user program imports kestrel:string, calls at least one function, asserts output

## Tasks

- [x] VM primitives __string_length, __string_slice, __string_index_of, __string_equals, __string_upper
- [x] Compiler typecheck + codegen for string primitives
- [x] stdlib/kestrel/string.ks implementations + E2E test
