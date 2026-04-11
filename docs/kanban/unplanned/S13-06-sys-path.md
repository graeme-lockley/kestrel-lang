# Path utilities (`kestrel:sys/path`)

## Sequence: S13-06
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E13 Stdlib Compiler Readiness](../epics/unplanned/E13-stdlib-compiler-readiness.md)

## Summary

Add a new `kestrel:sys/path` module with common path manipulation utilities backed by `java.nio.file.Path`. The compiler driver performs extensive path construction, splitting, and resolution that currently requires ad-hoc string operations. A proper path module using the OS-native separator and resolution rules is essential for cross-platform correctness.

## Current State

`stdlib/kestrel/io/fs.ks` only exports `pathBaseName` (a simple string-split function). No `dirname`, `join`, `resolve`, `isAbsolute`, `extension`, etc. exist. The current implementation splits on `"/"` which is wrong on Windows. `KRuntime.java` imports `java.nio.file.Paths` already (used by fs operations).

## Goals

1. Add new stdlib module `stdlib/kestrel/sys/path.ks`.
2. Export `join(parts: List<String>): String` — joins path segments with OS separator.
3. Export `dirname(path: String): String` — parent directory (e.g. `"/a/b/c.ks"` → `"/a/b"`).
4. Export `basename(path: String): String` — filename component (e.g. `"/a/b/c.ks"` → `"c.ks"`).
5. Export `resolve(base: String, rel: String): String` — resolves `rel` relative to `base` as an absolute path.
6. Export `isAbsolute(path: String): Bool` — true if path is absolute.
7. Export `extension(path: String): Option<String>` — file extension without dot (e.g. `"c.ks"` → `Some("ks")`; `"Makefile"` → `None`).
8. Export `withoutExtension(path: String): String` — path without the last extension.
9. Export `splitPath(path: String): (String, String)` — splits into `(dir, filename)` pair.
10. Export `normalize(path: String): String` — canonicalize `.` and `..` without I/O.

## Acceptance Criteria

- `join(["a", "b", "c"])` returns `"a/b/c"` on POSIX.
- `dirname("/a/b/c.ks")` returns `"/a/b"`.
- `basename("/a/b/c.ks")` returns `"c.ks"`.
- `resolve("/a/b", "../c")` returns `"/a/c"`.
- `isAbsolute("/foo")` returns `True`; `isAbsolute("foo")` returns `False`.
- `extension("c.ks")` returns `Some("ks")`; `extension("Makefile")` returns `None`.
- `withoutExtension("/a/b/c.ks")` returns `"/a/b/c"`.
- `normalize("/a/b/../c")` returns `"/a/c"`.

## Spec References

- `docs/specs/02-stdlib.md` (sys/path section — new)

## Risks / Notes

- Use `java.nio.file.Paths.get(...).normalize().toString()` for `normalize` and `resolve`. This is I/O-free on absolute paths.
- `join` should use `Paths.get(first, rest...)` to be OS-correct.
- Independent of all other E13 stories.
