# Stdlib: Implement kestrel:string

## Description

`stdlib/kestrel/string.ks` is a stub. Per spec 02: implement length, slice, indexOf, equals, toUpperCase. Each takes the string as an explicit argument. Calls VM string primitives (e.g. `__string_length`) for operations the language cannot do.

## Acceptance Criteria

- [ ] length(String): Int
- [ ] slice(String, Int, Int): String
- [ ] indexOf(String, String): Int
- [ ] equals(String, String): Bool
- [ ] toUpperCase(String): String
- [ ] E2E: user program imports kestrel:string, calls at least one function, asserts output
