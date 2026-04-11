# String numeric formatting: `toHexString`, `toBinaryString`, `toOctalString`

## Sequence: S13-13
## Tier: 1
## Former ID: (none)

## Epic

- Epic: [E13 Stdlib Compiler Readiness](../epics/unplanned/E13-stdlib-compiler-readiness.md)

## Summary

Add integer-to-string formatting functions for non-decimal bases to `kestrel:data/string`. Required for JVM constant-pool debug output (hex offsets and opcodes), and diagnostic hex addresses.

## Current State

`data/string` has `fromInt(n)` (decimal only). No hex/binary/octal representation functions exist. Java provides `Long.toHexString`, `Long.toBinaryString`, `Long.toOctalString`.

## Goals

1. Export `toHexString(n: Int): String` — lowercase hex, no prefix (e.g. `255` → `"ff"`).
2. Export `toHexStringPadded(width: Int, n: Int): String` — lowercase hex, zero-padded to `width` (e.g. `formatInt(4, 255)` in hex → `"00ff"`).
3. Export `toBinaryString(n: Int): String` — binary digits, no prefix (e.g. `5` → `"101"`).
4. Export `toOctalString(n: Int): String` — octal digits, no prefix (e.g. `8` → `"10"`).

## Acceptance Criteria

- `toHexString(255)` returns `"ff"`.
- `toHexString(0)` returns `"0"`.
- `toHexStringPadded(4, 255)` returns `"00ff"`.
- `toHexStringPadded(2, 255)` returns `"ff"` (no truncation — wider than width).
- `toBinaryString(5)` returns `"101"`.
- `toOctalString(8)` returns `"10"`.

## Spec References

- `docs/specs/02-stdlib.md` (data/string section)

## Risks / Notes

- Can be implemented via KRuntime JVM primitives calling `Long.toHexString` etc., or in pure Kestrel using `parseIntRadix` in reverse. The JVM approach is simpler and more efficient.
- `toHexStringPadded` = `padLeft(width, "0", toHexString(n))`.
- Independent of all other E13 stories except `padLeft` from existing `data/string` (already there).
