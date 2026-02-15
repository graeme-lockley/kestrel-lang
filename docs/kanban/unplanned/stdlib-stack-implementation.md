# Stdlib: Implement kestrel:stack

## Description

`stdlib/kestrel/stack.ks` is a stub. Per spec 02: implement trace(T): StackTrace\<T\>, print(T): Unit, format(T): String. These call VM primitives (`__write_stdout_string`, `__capture_trace`). Note: built-in `print` primitive exists; stdlib print may wrap it or call __write_stdout_string. Clarify relationship with built-in print per todo (print/println story).

## Acceptance Criteria

- [ ] trace(T): StackTrace\<T\> — stack trace for thrown value
- [ ] print(T): Unit — print value to stdout (or defer to built-in)
- [ ] format(T): String — format value as string (used in template interpolation)
- [ ] E2E: throw, catch, call trace; assert trace output
