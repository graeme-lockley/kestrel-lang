# Disassembler Improvements

## Priority: 175 (Low)

## Summary

The `kestrel dis` command provides basic bytecode disassembly but could be enhanced with more context: function boundaries, constant values inline, source line annotations (once debug section is populated), shape/ADT table dumps, and cross-references.

## Current State

- `disasm.ts` (285 lines): Reads .kbc, parses headers, disassembles code section with mnemonic names.
- Shows constant annotations (e.g., `LOAD_CONST 0 ; Int(42)`).
- Does not show function boundaries.
- Does not show shape table or ADT table contents.
- Does not annotate with source lines (debug section is empty).

## Acceptance Criteria

- [ ] Show function boundaries: `--- function "name" (arity N, offset 0xABC) ---` before each function's code.
- [ ] Show shape table contents: field names per shape.
- [ ] Show ADT table contents: type names and constructor names.
- [ ] Show import table: module specifiers.
- [ ] If debug section is populated (story 06), annotate instructions with source file:line.
- [ ] Optional `--verbose` flag for full table dumps vs. `--code-only` for just instructions.

## Spec References

- 09-tools &sect;2.2 (kestrel dis: disassemble bytecode)
