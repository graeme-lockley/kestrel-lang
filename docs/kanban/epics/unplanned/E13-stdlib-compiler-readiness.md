# Epic E13: Stdlib Compiler Readiness

## Status

Unplanned

## Summary

The Kestrel stdlib already provides the lexer, parser, collections, JSON, HTTP, subprocess, async, ANSI colours, CLI parsing, and pretty-printing necessary to rewrite the compiler in Kestrel. However, six critical primitives and several smaller ergonomic gaps remain that would block or badly hamper a pure-Kestrel compiler implementation. This epic closes every one of those gaps so that no stdlib limitation needs to be worked around during the compiler rewrite. The additions span three layers: new JVM runtime primitives in `KRuntime.java`, new or extended stdlib modules (`io/fs`, `io/crypto`, `sys/path`, `data/string`, `data/list`), and spec updates in `docs/specs/02-stdlib.md`.

## Stories (ordered — implement sequentially within each group)

### Group A — Critical blockers (must be done before compiler work begins)

1. [S13-01 — Binary file I/O (`readBytes`/`writeBytes`/`appendBytes`)](../../unplanned/S13-01-binary-file-io.md)
   Adds `ByteArray` opaque type and `readBytes`, `writeBytes`, `appendBytes` to `kestrel:io/fs`. Required for JVM `.class` file emission.

2. [S13-02 — `mkdirAll` and `stat` / file metadata](../../unplanned/S13-02-mkdir-stat.md)
   Adds `mkdirAll(path)`, `stat(path) -> Task<Result<FileStat, FsError>>` (with `mtimeMs`, `size`, `isDir`, `isFile`) and `touchFile(path)` to `kestrel:io/fs`. Required for output-directory setup and KTI incremental cache staleness detection.

3. [S13-03 — Process exit code (`exit`)](../../unplanned/S13-03-process-exit.md)
   Adds `exit(code: Int) -> Task<Never>` to `kestrel:sys/process`. Required for CLI tools that must return a non-zero exit code on compile error.

4. [S13-04 — Stderr output (`printErr` / `eprintln`)](../../unplanned/S13-04-stderr-output.md)
   Adds `printErr(s: String) -> Unit` and `eprintln(s: String) -> Unit` built-ins (or `kestrel:io/console` exports). Required for diagnostic and progress output that must not pollute stdout.

5. [S13-05 — Cryptographic hashing (`sha256`, `sha1`, `md5`)](../../unplanned/S13-05-crypto-hash.md)
   Adds `kestrel:io/crypto` module exposing `sha256(s: String) -> String`, `sha1(s: String) -> String`, `md5(s: String) -> String` (hex-string output), and `sha256Bytes(bytes: ByteArray) -> String`. Required for URL-import cache key derivation and Maven JAR integrity verification.

6. [S13-06 — Path utilities (`kestrel:sys/path`)](../../unplanned/S13-06-sys-path.md)
   Adds `kestrel:sys/path` module: `join(parts: List<String>) -> String`, `dirname(path: String) -> String`, `basename(path: String) -> String`, `resolve(base: String, rel: String) -> String`, `isAbsolute(path: String) -> Bool`, `extension(path: String) -> Option<String>`, `withoutExtension(path: String) -> String`, `splitPath(path: String) -> (String, String)`. Replaces ad-hoc string manipulation that the compiler uses for path construction.

### Group B — Ergonomic gaps (can be built in parallel with Group A)

7. [S13-07 — `Float` parsing (`parseFloat`, `toFloat`)](../../unplanned/S13-07-float-parsing.md)
   Adds `parseFloat(s: String) -> Option<Float>` and `toFloat(s: String) -> Float` (returns `0.0` on bad input) to `kestrel:data/string`. Required for lexing float literals.

8. [S13-08 — Generic `List.sortBy` and `List.sortWith`](../../unplanned/S13-08-list-sort.md)
   Adds `sortBy(f: A -> comparable, xs: List<A>) -> List<A>` and `sortWith(cmp: (A, A) -> Int, xs: List<A>) -> List<A>` to `kestrel:data/list`. Compiler uses sorted orderings of type variables, diagnostics, and import lists throughout.

9. [S13-09 — `List.find`, `List.findIndex`, `List.findMap`, `List.last`](../../unplanned/S13-09-list-find.md)
   Adds `find(pred: A -> Bool, xs: List<A>) -> Option<A>`, `findIndex(pred: A -> Bool, xs: List<A>) -> Option<Int>`, `findMap(f: A -> Option<B>, xs: List<A>) -> Option<B>`, and `last(xs: List<A>) -> Option<A>` to `kestrel:data/list`. Eliminates verbose `filter` + `head` patterns throughout the compiler.

10. [S13-10 — `String` additions: `parseFloat`, base-N int parse, `format` / left-pad-int, `indexOfChar`](../../unplanned/S13-10-string-additions.md)
    Adds to `kestrel:data/string`: `parseIntRadix(radix: Int, s: String) -> Option<Int>` (hex/octal/binary literal parsing), `formatInt(width: Int, s: String) -> String` (left-pad with zeros for hex output), `indexOfChar(c: Char, s: String) -> Option<Int>` (faster than `indexOf` for single-char search). Required for lexer numeric-literal tokenising and diagnostic column formatting.

11. [S13-11 — Recursive `listDir` and `collectFiles`](../../unplanned/S13-11-recursive-listdir.md)
    Adds `listDirAll(path: String) -> Task<Result<List<DirEntry>, FsError>>` (recursive) and `collectFilesByExtension(path: String, ext: String) -> Task<Result<List<String>, FsError>>` to `kestrel:io/fs`. Required for enumerating `.kti` incremental-cache files during `--clean`.

### Group C — Polish (build after Groups A and B)

12. [S13-12 — `Dict` with structural-equality keys (`StructDict`)](../../unplanned/S13-12-struct-dict.md)
    Adds `kestrel:data/structdict` (or extends `data/dict`) with a `StructDict<K,V>` backed by a key-serialization strategy so that ADT and record values can be used as keys with structural equality. The compiler's type environment uses string-keyed `Dict<String, ...>` exclusively, so this is not a hard blocker, but it would eliminate a class of subtle bugs if the compiler later uses composite keys.

13. [S13-13 — `kestrel:data/string` `parseIntBase`, `toHexString`, `toBinaryString`](../../unplanned/S13-13-string-numeric-format.md)
    Adds `toHexString(n: Int) -> String`, `toHexStringPadded(width: Int, n: Int) -> String`, `toBinaryString(n: Int) -> String`, `toOctalString(n: Int) -> String` to `kestrel:data/string`. Needed for JVM constant-pool debug output and diagnostic hex offsets.

14. [S13-14 — Atomic file write (`writeTextAtomic`, `writeBytesAtomic`)](../../unplanned/S13-14-atomic-write.md)
    Adds `writeTextAtomic(path: String, content: String) -> Task<Result<Unit, FsError>>` and `writeBytesAtomic(path: String, bytes: ByteArray) -> Task<Result<Unit, FsError>>` to `kestrel:io/fs` using a write-to-tmp-then-rename pattern. The URL import cache and KTI files must be written atomically on crash.

**Notes on ordering:**
- S13-01 (binary I/O) must precede S13-05 (crypto, which can operate on `ByteArray`) and S13-14 (atomic binary write).
- S13-02 (mkdir/stat) must precede S13-11 (recursive listDir).
- S13-03, S13-04, S13-06 are independent of each other and of Group B/C.
- Group B stories (S13-07–S13-11) are mutually independent and can be built in any order, in parallel with Group A.
- S13-12–S13-14 (Group C) depend on S13-01 and S13-02 but are otherwise independent of each other.

## Dependencies

- **E02 (JVM Interop / Intrinsic Migration)** — the pattern for adding new JVM primitives in `KRuntime.java` and exposing them via `extern import` is fully established. Must be done (it is — E02 is in `done/`).
- **E03 (HTTP and Networking)** — `kestrel:io/http` and `kestrel:io/fs` are in place; this epic extends `fs` and adds new modules alongside them.
- **E11 (Pure-Kestrel Test Runner)** — `getEnv`, `runProcess`, `sys/process` patterns are established. Must be done (it is).
- **E12 (Full Process Environment)** — `getProcess()` returns a fully populated env list. Must be done (it is).

## Epic Completion Criteria

- **Binary I/O**: `fs.readBytes(path)` returns the raw bytes of any file as a `ByteArray`; `fs.writeBytes(path, bytes)` writes a `ByteArray` as a binary file. A JVM `.class` file can be round-tripped through `readBytes`/`writeBytes` without corruption.
- **Directory creation**: `fs.mkdirAll(path)` creates nested directories without error if they already exist. The compiler can prepare its output directory tree before writing class files.
- **File metadata**: `fs.stat(path)` returns `mtimeMs`, `size`, `isDir`, `isFile`. `fs.touchFile(path)` resets the mtime to now.
- **Process exit**: `process.exit(1)` terminates the Kestrel program with exit code 1; `process.exit(0)` terminates with code 0. The shell `$?` reflects the argument.
- **Stderr**: `printErr("msg")` writes to stderr; it does not appear on stdout. Can be verified by redirecting stderr and stdout separately.
- **Crypto hashing**: `crypto.sha256("hello")` returns the correct lowercase hex SHA-256 digest. `crypto.sha1(...)` and `crypto.sha256Bytes(bytes)` likewise.
- **Path utilities**: `path.join(["a", "b", "c"])` returns `"a/b/c"` on POSIX; `path.dirname("/a/b/c.ks")` returns `"/a/b"`; `path.basename("/a/b/c.ks")` returns `"c.ks"`; `path.resolve("/a/b", "../c")` returns `"/a/c"`.
- **Float parsing**: `String.parseFloat("3.14")` returns `Some(3.14)`; `String.parseFloat("bad")` returns `None`.
- **Generic sort**: `List.sortBy(fun(x) = x.key, myList)` returns elements in ascending key order. `List.sortWith(cmp, xs)` sorts by a custom comparator returning negative/zero/positive.
- **List search**: `List.find`, `List.findIndex`, `List.findMap`, `List.last` behave as specified; eliminate the need for `filter` + `head` patterns.
- **String additions**: `String.parseIntRadix(16, "ff")` returns `Some(255)`; `String.toHexString(255)` returns `"ff"`; `String.toHexStringPadded(4, 255)` returns `"00ff"`.
- **Recursive listDir**: `fs.listDirAll(path)` returns all files/dirs recursively. `fs.collectFilesByExtension(path, ".kti")` returns only `.kti` files.
- **Atomic write**: `fs.writeTextAtomic` and `fs.writeBytesAtomic` complete without leaving partial files if the process is interrupted.
- **Specs**: `docs/specs/02-stdlib.md` documents every new function, type, and module added by this epic.
- **Tests**: Every new stdlib function has at least one Kestrel unit test (`./kestrel test`). All compiler tests continue to pass (`cd compiler && npm test`).
- **No stdlib workarounds**: A compiler author starting a Kestrel-in-Kestrel implementation after this epic is done can do so without reaching outside the stdlib for any of the capabilities listed in the Gap Analysis (binary I/O, mkdir, exit, stderr, hashing, path ops, float parse, generic sort, list search, string radix ops, recursive dir listing, atomic writes).

## Implementation Approach

Each story in Groups A and B follows the same three-layer pattern established by E02:

1. **JVM primitive** — Add one or more `static` methods to `runtime/jvm/src/kestrel/runtime/KRuntime.java`. Use Java 21 standard library where possible (no new Maven dependencies).
2. **`extern import` stub** — Declare the primitive in the appropriate stdlib `.ks` file using `extern import "kestrel-runtime" { ... }`.
3. **Kestrel wrapper** — Wrap the primitive in idiomatic Kestrel (e.g. wrapping a raw Task return in `Result`, joining path segments via `String.join`).

For S13-01 (`ByteArray`), the opaque type is backed by `byte[]` in Java, mirroring how `Array<T>` is backed by `ArrayList`. No new JVM class is needed — `KRuntime` can expose static helpers that accept/return `byte[]` directly, and the Kestrel type system's opaque-type mechanism hides the representation.

For S13-05 (crypto), `java.security.MessageDigest` (SHA-256, SHA-1, MD5) is used. No external JAR dependency.

For S13-06 (`sys/path`), `java.nio.file.Path` and `java.nio.file.Paths` are used to ensure OS-correct path handling on all platforms.
