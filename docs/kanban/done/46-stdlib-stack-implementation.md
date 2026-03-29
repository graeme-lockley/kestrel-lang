# Stdlib: Implement kestrel:stack


## Sequence: 46
## Former ID: (none)
## Description

`stdlib/kestrel/stack.ks` is a stub. Per spec 02: implement trace(T): StackTrace\<T\>, print(T): Unit, format(T): String. These call VM primitives (`__write_stdout_string`, `__capture_trace`). Note: built-in `print` primitive exists; stdlib print may wrap it or call __write_stdout_string.

## Acceptance Criteria

- [ ] trace(T): StackTrace\<T\> — deferred (requires __capture_trace and StackTrace type)
- [x] print(T): Unit — print value to stdout (via __print_one)
- [x] format(T): String — format value as string (via __format_one)
- [x] E2E: format/print; trace when __capture_trace exists

## Tasks

- [x] Compiler: __format_one, __print_one (use existing VM 0xFFFFFF03, 0xFFFFFF00)
- [x] stdlib/kestrel/stack.ks: format, print; trace stub
- [x] E2E test for stack
