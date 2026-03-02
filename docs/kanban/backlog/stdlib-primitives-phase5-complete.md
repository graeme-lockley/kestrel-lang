# Stdlib and VM primitives (Phase 5 complete)

## Description

Per spec 02 and IMPLEMENTATION_PLAN Phase 5, the five stdlib modules (kestrel:string, stack, http, json, fs) and core types (Option, Result, List, Value) must be implemented. The VM exposes a minimal set of primitives (I/O, string, JSON, FS, HTTP, stack trace); the rest is Kestrel source in stdlib. This story completes Phase 5: wire all required primitives and ensure stdlib modules satisfy the 02 contract.

## Acceptance Criteria

- [ ] VM primitives: implement and register minimal set (e.g. `__write_stdout_string`, `__string_*`, `__json_parse`/`__json_stringify`, `__read_file_async`, HTTP hooks, `__capture_trace` or equivalent) in `vm/src/primitives.zig`
- [ ] Stdlib: kestrel:string, kestrel:stack, kestrel:json, kestrel:fs, kestrel:http implement 02 signatures; Option, Result, List, Value as Kestrel ADTs in stdlib
- [ ] Compiler/VM: import resolution resolves stdlib specifiers to stdlib .kbc (or source); stdlib .kbc can call primitives; user code imports stdlib and calls functions
- [ ] E2E: user program imports each of kestrel:string, stack, json, fs, http and calls at least one function; conformance to 02 contract (signatures and behaviour where specified)

## Notes

- Several done stories (stdlib-string-implementation, stdlib-stack-implementation, stdlib-json-fs-http, stdlib-core-types-adts) already delivered parts; this story closes remaining gaps and ensures full Phase 5 deliverables.
