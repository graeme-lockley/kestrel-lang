# String additions: `parseIntRadix`, `formatInt`, `indexOfChar`

## Sequence: S13-10
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E13 Stdlib Compiler Readiness](../epics/unplanned/E13-stdlib-compiler-readiness.md)

## Summary

Add three targeted string utilities to `kestrel:data/string`: base-N integer parsing (`parseIntRadix`), integer-to-string with zero-padding (`formatInt`/`padInt`), and character-position search (`indexOfChar`). These three fill specific compiler lexer and diagnostic formatter needs.

## Current State

`data/string` has `parseInt` (decimal only), `padLeft`/`padRight` (for string padding), and `indexOf` (for substring search). No radix-aware integer parser, no zero-padded integer formatter, and no single-character index search.

## Goals

1. Export `parseIntRadix(radix: Int, s: String): Option<Int>` — parse integer in given base (2, 8, 10, 16). Returns `None` on invalid input.
2. Export `formatInt(width: Int, n: Int): String` — format integer as string left-padded to at least `width` characters with `'0'`. E.g. `formatInt(4, 255)` → `"0255"`.
3. Export `indexOfChar(c: Char, s: String): Option<Int>` — index of first occurrence of character `c`, or `None`. More convenient than `indexOf` for single characters.

## Acceptance Criteria

- `parseIntRadix(16, "ff")` returns `Some(255)`.
- `parseIntRadix(16, "FF")` returns `Some(255)` (case-insensitive).
- `parseIntRadix(2, "1010")` returns `Some(10)`.
- `parseIntRadix(8, "17")` returns `Some(15)`.
- `parseIntRadix(10, "42")` returns `Some(42)`.
- `parseIntRadix(16, "xyz")` returns `None`.
- `parseIntRadix(16, "")` returns `None`.
- `formatInt(4, 255)` returns `"0255"`.
- `formatInt(4, 1)` returns `"0001"`.
- `formatInt(4, 12345)` returns `"12345"` (wider than width → no truncation).
- `indexOfChar('b', "abc")` returns `Some(1)`.
- `indexOfChar('z', "abc")` returns `None`.

## Spec References

- `docs/specs/02-stdlib.md` (data/string section)

## Risks / Notes

- `parseIntRadix` can be implemented in pure Kestrel using `codePointAt` and digit mapping. No JVM call needed for String variant.
- `formatInt` = `padLeft(width, "0", fromInt(n))`.
- `indexOfChar` can use `charAt` loop or convert char to single-char string and call `indexOf`.
- Independent of all other E13 stories.

## Tasks

- [x] `stdlib/kestrel/data/string.ks`: add `parseIntRadix`, `formatInt`, `indexOfChar`
- [x] `tests/conformance/runtime/valid/string_extras.ks`: conformance test (12 checks)
- [x] Compiler tests pass (`cd compiler && npm test`)
- [x] `docs/specs/02-stdlib.md`: add three functions to data/string table

## Build notes

- 2025-01-01: Implemented `parseIntRadix` in pure Kestrel via `digitValue` + recursive accumulator helper `parseRadixLoop`.
- Parser accepts uppercase and lowercase digits for bases above 10 (`A-F`/`a-f` for hex).
- Kept API argument order per story spec: radix first, string second; char first, string second for `indexOfChar`.
