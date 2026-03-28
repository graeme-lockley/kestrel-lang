# Char/Rune Runtime Support

## Sequence: 03
## Tier: 1 — Fix broken language
## Former ID: 135

## Summary

Char and Rune are specified as the same type (one Unicode code point), stored inline in the tagged value (05 §1). The lexer parses character literals (`'x'`, `'\u{1F600}'`), the constant pool has tag 5 (Char), and the VM value model has a `char` tag. Runtime support now includes comparisons, robust formatting, stdlib aliases, JVM parity for Char display and ordering, and correct codegen for astral character literals.

## Current State

- VM `exec.zig`: **EQ/NE/LT/LE/GT/GE** on two `char` values compare code points as unsigned scalars.
- VM `primitives.zig` `formatInto`: Encodes **CHAR** as UTF-8; invalid/surrogate payloads map to U+FFFD before encoding.
- Compiler: **Char literal codegen** uses `codePointAt(0)` on the parser’s decoded character (fixes astral scalars that occupy two UTF-16 code units in JS).
- **kestrel:char** exports `charToInt`, `intToChar`, `charToString` (plus existing helpers).
- JVM: **Char** boxed as **Integer**; `formatOne` renders Char as a glyph; **charLess/Eq/Gt** on `KMath`; `charFromCode` / `stringCharAt` return `Integer`.
- Tests: `tests/unit/comparison.test.ks` (char compare), `tests/unit/strings.test.ks` (interpolation); `stdlib/kestrel/char.test.ks` extended; spec **05-runtime-model** updated (**CHAR operations**).

## Acceptance Criteria

- [x] `formatInto` in `primitives.zig` properly formats char values as the character (e.g., `'a'` or the Unicode glyph).
- [x] `print`/`println` display char values correctly.
- [x] String interpolation with char values works (char is converted to a single-character string).
- [x] Add `eq` comparison support for char values in VM (EQ, NE).
- [x] Add `lt`/`gt` comparison for char values (by code point order).
- [x] Consider basic char utility functions: `charToInt(Char): Int`, `intToChar(Int): Char`, `charToString(Char): String`.
- [x] Kestrel test: char literals, comparison, interpolation.

## Spec References

- 01-language §2.9 (Character and Rune literals)
- 05-runtime-model §1 (CHAR tag: Unicode code point inline)
- 06-typesystem §1 (Char and Rune denote the same type)

## Tasks

- [x] VM: `binopCmp` branch for `char` (eq/ne/lt/le/gt/ge).
- [x] VM: Harden `formatInto` for `char` (valid scalar / replacement).
- [x] Compiler: Fix char literal constant emission for astral code points (`charLiteralCodePoint`).
- [x] Stdlib `kestrel/char.ks`: export `charToInt`, `intToChar`, `charToString`; extend `char.test.ks`.
- [x] JVM: `formatOne` + ordered comparisons + `Integer` Char boxing for `charFromCode` / `stringCharAt`.
- [x] Unit tests (`comparison`, `strings`) and spec 05 update.
- [x] Verify: `npm test` (compiler), `zig build` + `zig build test`, `./scripts/kestrel test`, `./scripts/run-e2e.sh`.

## Notes

- Interpolation source `${...}` is scanned by brace depth; a **`\u{...}`** escape **inside** the `${...}` expression can close the hole early. Tests use a **local `val`** for emoji-in-template (documented in `strings.test.ks`).
