# VM: Implement primitives required by stdlib

## Description

The stdlib .ks modules will call VM primitives for operations the language cannot express (I/O, string ops, JSON, FS, HTTP, stack traces). Currently only `print` (fn_id 0xFFFFFF00) is wired. Per IMPLEMENTATION_PLAN Phase 5.1.

## Acceptance Criteria

- [ ] Define primitive namespace/IDs (e.g. 0xFFFFFF00–0xFFFFFFFF)
- [ ] `__write_stdout_string` or equivalent for print/format
- [ ] String primitives: `__string_length`, `__string_slice`, `__string_index_of`, `__string_equals`, `__string_upper`
- [ ] JSON: `__json_parse`, `__json_stringify` (consume/produce Value ADT)
- [ ] FS: `__read_file_async` → Task\<String\>
- [ ] Stack trace: `__capture_trace` for kestrel:stack trace/format
- [ ] HTTP primitives (createServer, listen, get, bodyText, queryParam, requestId, nowMs) — or defer to later story
- [ ] Wire primitive dispatch: CALL with fn_id in primitive range → Zig implementation
