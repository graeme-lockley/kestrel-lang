# Char/Rune Runtime Support

## Priority: 135 (Medium)

## Summary

Char and Rune are specified as the same type (one Unicode code point), stored inline in the tagged value (05 &sect;1). The lexer parses character literals (`'x'`, `'\u{1F600}'`), the constant pool has tag 5 (Char), and the VM value model has a `char` tag. However, runtime support is minimal -- no char-specific operations, no string-to-char or char-to-string conversion, and limited print formatting.

## Current State

- Lexer: Parses `'x'` and `'\u{XXXX}'` character literals correctly.
- Constant pool: Tag 5 (Char) with u32 payload.
- VM `value.zig`: Has `char` tag, can encode/decode u32 code points.
- `primitives.zig` `formatInto`: Does not specifically handle the `char` tag (likely falls through to a default case or prints as integer).
- No built-in functions for char operations (toInt, fromInt, isDigit, isAlpha, etc.).
- Type checker: Treats `Char` and `Rune` as the same type.

## Acceptance Criteria

- [ ] `formatInto` in `primitives.zig` properly formats char values as the character (e.g., `'a'` or the Unicode glyph).
- [ ] `print`/`println` display char values correctly.
- [ ] String interpolation with char values works (char is converted to a single-character string).
- [ ] Add `eq` comparison support for char values in VM (EQ, NE).
- [ ] Add `lt`/`gt` comparison for char values (by code point order).
- [ ] Consider basic char utility functions: `charToInt(Char): Int`, `intToChar(Int): Char`, `charToString(Char): String`.
- [ ] Kestrel test: char literals, comparison, interpolation.

## Spec References

- 01-language &sect;2.9 (Character and Rune literals)
- 05-runtime-model &sect;1 (CHAR tag: Unicode code point inline)
- 06-typesystem &sect;1 (Char and Rune denote the same type)
