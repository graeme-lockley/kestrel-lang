# Debug Section: Code-Offset to Source-Line Mapping

## Priority: 09 (High)

## Summary

The debug section (section 4 in .kbc) is always emitted empty (`file_count=0`, `entry_count=0`). This means stack traces, runtime errors, and diagnostic tools cannot map bytecode offsets back to source file and line numbers. Implementing this is essential for a usable developer experience.

## Current State

- `write.ts` emits the debug section as stub: `file_count=0`, `entry_count=0` (8 bytes total).
- The compiler does not track or emit code-offset-to-line mappings during codegen.
- The VM has no logic to read or use debug entries for error reporting.
- `disasm.ts` shows byte offsets but not source lines.

## Acceptance Criteria

- [ ] **Compiler**: During codegen, record `(code_offset, source_file, source_line)` tuples for each significant instruction (at minimum: one entry per statement/expression start).
- [ ] **Bytecode writer**: Emit file entries and debug mapping entries per spec 03 &sect;8 (sorted by code_offset ascending).
- [ ] **VM**: On uncaught exception or runtime error, look up the current PC in the debug entries (binary search) and print `file:line` in the error message.
- [ ] **Disassembler**: Optionally annotate disassembly output with source line numbers from the debug section.
- [ ] E2E test: A program that throws an uncaught exception reports the correct source file and line number.

## Spec References

- 03-bytecode-format &sect;8 (Debug section layout)
- 05-runtime-model &sect;5 (Stack traces; debug section maps code offsets to file/line)
- 10-compile-diagnostics (Diagnostic locations)
