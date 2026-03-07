# String Operations: Unicode Correctness

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

- [ ] `stringLength`: Count Unicode code points (not bytes). Iterate UTF-8 and count characters.
- [ ] `stringSlice(s, start, end)`: Slice by character index (code point index), not byte index. Handle multi-byte characters correctly.
- [ ] `stringIndexOf`: Return character-based index of first occurrence, not byte index.
- [ ] `stringUpper`: Support full Unicode uppercasing (at minimum, the common Latin-extended range; ideally use Zig's unicode-aware facilities or a lookup table).
- [ ] Add Kestrel test with multi-byte strings: emoji, accented characters, CJK.
- [ ] Verify no performance regression for ASCII-only strings (fast path).

## Spec References

- 02-stdlib (kestrel:string: length is character length, slice by character indices)
- 01-language &sect;2.8 (Strings are UTF-8)
