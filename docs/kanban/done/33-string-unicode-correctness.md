# String Operations: Unicode Correctness


## Sequence: 33
## Former ID: 70
## Priority: 70 (Medium)

## Summary

String operations in both the VM primitives and stdlib are currently byte-based, not Unicode-aware. This violates the spec which defines strings as sequences of Unicode code points. `length` returns byte count, `slice` slices by byte offset, and `toUpperCase` only handles ASCII.

## Current State

- `primitives.zig`:
  - `stringLength`: returns `str_data.len` (byte length, not character length).
  - `stringSlice`: slices by byte indices, which can split multi-byte UTF-8 sequences.
  - `stringIndexOf`: byte-based search (happens to work for ASCII substrings).
  - `stringUpper`: iterates bytes, uppercases ASCII only (a-z -> A-Z).
- `stdlib/kestrel/string.ks`: thin wrappers around the VM primitives, inheriting their byte-based behavior.
- Spec 02 says `length` returns "character length" and `slice` uses character indices.

## Acceptance Criteria

- [x] `stringLength`: Count Unicode code points (not bytes). Iterate UTF-8 and count characters.
- [x] `stringSlice(s, start, end)`: Slice by character index (code point index), not byte index. Handle multi-byte characters correctly.
- [x] `stringIndexOf`: Return character-based index of first occurrence, not byte index.
- [x] `stringUpper`: Support full Unicode uppercasing (at minimum, the common Latin-extended range; ideally use Zig's unicode-aware facilities or a lookup table).
- [x] Add Kestrel test with multi-byte strings: emoji, accented characters, CJK.
- [x] Verify no performance regression for ASCII-only strings (fast path).
- [x] Kerstrel's string library is updated and serves as the entry point into the builtin functions.

## Spec References

- 02-stdlib (kestrel:string: length is character length, slice by character indices)
- 01-language &sect;2.8 (Strings are UTF-8)

## Tasks

- [x] Add utf8IsAscii, utf8CountCodepoints, utf8ByteOffsetForCodepoint helpers to primitives.zig
- [x] Rewrite stringLength to count code points (with ASCII fast path)
- [x] Rewrite stringSlice to use code-point indices (with ASCII fast path)
- [x] Rewrite stringIndexOf to return code-point index (with ASCII fast path)
- [x] Rewrite stringUpper with code-point iteration and Latin-extended case table
- [x] Add Unicode test cases to string.test.ks and strings.test.ks (emoji, accented, CJK)
- [x] Update 02-stdlib.md and optionally 01-language.md to clarify code-point semantics
- [x] Run full test suite: VM tests, compiler tests, kestrel tests, E2E tests
