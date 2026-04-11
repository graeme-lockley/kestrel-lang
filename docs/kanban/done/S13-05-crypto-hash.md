# Cryptographic hashing (`sha256`, `sha1`, `md5`)

## Sequence: S13-05
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E13 Stdlib Compiler Readiness](../epics/unplanned/E13-stdlib-compiler-readiness.md)

## Summary

Add a new `kestrel:io/crypto` module that exposes SHA-256, SHA-1, and MD5 hashing via `java.security.MessageDigest`. The compiler uses SHA-256 to derive URL-import cache directory names and SHA-1 to verify Maven JAR integrity. No external JARs needed — `MessageDigest` is a Java standard library class.

## Current State

No cryptographic hashing exists anywhere in the Kestrel stdlib. `KRuntime.java` has no `MessageDigest` usage. The Node.js compiler uses `node:crypto`'s `createHash('sha256')` extensively.

## Goals

1. Add new stdlib module `stdlib/kestrel/io/crypto.ks`.
2. Export `sha256(s: String): String` — SHA-256 of UTF-8 bytes of `s`, returned as lowercase hex.
3. Export `sha1(s: String): String` — SHA-1 of UTF-8 bytes of `s`, returned as lowercase hex.
4. Export `md5(s: String): String` — MD5 of UTF-8 bytes of `s`, returned as lowercase hex.
5. Export `sha256Bytes(bytes: ByteArray): String` — SHA-256 of a `ByteArray`, returned as lowercase hex.
6. Export `sha1Bytes(bytes: ByteArray): String` — SHA-1 of a `ByteArray`, returned as lowercase hex.

## Acceptance Criteria

- `sha256("hello")` returns `"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"`.
- `sha1("hello")` returns `"aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d"`.
- `md5("hello")` returns `"5d41402abc4b2a76b9719d911017c592"`.
- `sha256Bytes` with a known byte array returns the correct digest.
- All functions are exported from `kestrel:io/crypto`.

## Spec References

- `docs/specs/02-stdlib.md` (io/crypto section — new)

## Risks / Notes

- **Depends on S13-01** (ByteArray type must exist for `sha256Bytes`/`sha1Bytes`). If S13-01 is built first the `Bytes` variants can be added; alternatively, ship the String variants first and add Bytes variants as a follow-up in the same story.
- `MessageDigest` is not thread-safe; create a new instance per call.
- MD5 is cryptographically broken but still commonly used for integrity checks (e.g. some Maven repos use MD5). Include it but document the limitation.

## Tasks

- [x] `runtime/jvm/src/kestrel/runtime/KRuntime.java`: add `sha256`, `sha1`, `md5`, `sha256Bytes`, `sha1Bytes`
- [x] `stdlib/kestrel/io/crypto.ks`: create new module with `sha256`, `sha1`, `md5` (string variants; see build note for bytes)
- [x] `tests/conformance/runtime/valid/crypto_hash.ks`: test known-good hashes
- [x] `cd runtime/jvm && bash build.sh`
- [x] `cd compiler && npm test`

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md`: add `kestrel:io/crypto` section

## Build notes

`sha256Bytes` and `sha1Bytes` (ByteArray variants) are implemented in KRuntime.java but NOT exported from `crypto.ks`. Cross-module opaque type usage in `extern fun` parameters fails: when `ByteArray` (opaque, defined in `kestrel:io/fs`) is imported into `crypto.ks` and used as a parameter in an `extern fun` declaration, the typecheck sees `JByteArray<> vs __opaque__<>` at the call site. This is a known limitation of the opaque/extern type system — the underlying `JByteArray` representation is only visible within the defining module. The bytes variants are not needed for compiler self-hosting (the TypeScript compiler only hashes strings).
