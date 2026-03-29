# Disassembler Improvements

## Sequence: 54
## Tier: 6 — Polish
## Former ID: 21

## Summary

The `kestrel dis` command provides basic bytecode disassembly but could be enhanced with more context: function boundaries, constant values inline, source line annotations when the debug section is populated, shape/ADT table dumps, and cross-references.

## Current State

- `compiler/disasm.ts`: Reads `.kbc`, parses header and sections 0–4, disassembles the code section with mnemonic names.
- Shows constant annotations (e.g. `LOAD_CONST 0 ; Int(42)`).
- Parses the debug section and emits `; --- file:line ---` banners when entries exist; empty debug yields no annotations.
- Does not parse section 2 (function / import / type metadata) beyond what is needed for strings and constants—no function boundaries, import list, shape table (section 5), or ADT table (section 6).
- CLI: `scripts/kestrel` invokes `node dist/disasm.js <kbc>` with no flags; `disasm.ts` usage is `disasm <file.kbc>` only.
- `OP_NAMES` in `disasm.ts` may lag the ISA (e.g. opcodes added in spec 04); align disassembly with [04-bytecode-isa.md](../../specs/04-bytecode-isa.md) when touching this file.

## Relationship to other stories

- **None** for correctness or ordering. Same roadmap tier as [53-block-expression-codegen-cleanups.md](53-block-expression-codegen-cleanups.md) (polish); no shared deliverable.

## Goals

1. Make bytecode listings easier to navigate by marking each function’s code region (name, arity, code offset).
2. Surface module metadata (imports, record shapes, ADTs) in the disassembler when the user asks for detail, without cluttering the default listing.
3. Keep source correlation behavior correct and spec-aligned when the debug section is present; document flag semantics in tools spec.
4. Wire `kestrel dis` to forward new flags to the disassembler entrypoint.

## Acceptance Criteria

- [ ] Show function boundaries: `--- function "name" (arity N, offset 0xABC) ---` before each function's code.
- [ ] Show shape table contents: field names per shape.
- [ ] Show ADT table contents: type names and constructor names.
- [ ] Show import table: module specifiers.
- [ ] If debug section is populated, annotate instructions with source file:line.
- [ ] Optional `--verbose` flag for full table dumps vs. `--code-only` for just instructions.

## Spec References

- `docs/specs/09-tools.md` §2.2 (`kestrel dis`: disassemble bytecode)
- `docs/specs/03-bytecode-format.md` §6.1 (function table), §6.5 (import table), §8 (debug), §9 (shape table), §10 (ADT table)
- `docs/specs/04-bytecode-isa.md` (mnemonics and operands)

## Risks / notes

- **Section 2 parsing** is non-trivial (variable-length type blob, alignment). Follow skip formulas in 03 §6 and mirror the VM loader order; fuzz/truncate inputs should fail cleanly with a clear error rather than silent garbage.
- **`--code-only` vs. boundaries/debug:** Resolve explicitly during implementation: e.g. default + `--verbose` include function banners and debug banners; `--code-only` prints only opcode lines (no `;` comments, no table preambles). Document the chosen behavior in 09-tools §2.2.
- **Cross-references** (summary): optional stretch—resolve `CALL` / `LOAD_IMPORTED_FN` indices to names when tables are available; not required for acceptance unless promoted from “optional” in a follow-up.
- **Duplication:** No shared TypeScript reader for `.kbc` today; either keep self-contained parsing in `disasm.ts` or extract a small `readKbcLayout` helper if it stays readable.

## Impact analysis

| Area | Change |
|------|--------|
| **Compiler** | `compiler/disasm.ts` — parse section 2 for function and import tables; read sections 5–6 for shape/ADT; implement output modes; possibly extend opcode map to match 04. |
| **Scripts** | `scripts/kestrel` — `cmd_dis`: pass through `--verbose` / `--code-only` (and update `usage`). |
| **VM / JVM** | None unless fixing format drift; disassembler is tooling-only. |
| **Risk** | Low for runtime; medium for maintenance if section-2 walk diverges from VM. Mitigate with tests using compiler-emitted `.kbc` fixtures. |
| **Compatibility** | Output format change only; `.kbc` format unchanged. |

## Tasks

- [x] Implement parsing of section 2 through §6.1 (after `n_globals`, read `function_count` and 24-byte entries: `name_index`, `arity`, `code_offset`, flags, reserved, `type_index`) using string table for names. Sort or walk by `code_offset` to emit boundaries in address order (spec does not require sorted function table; disassembler should order by `code_offset` for listing).
- [ ] Implement skip/parse through §6.5: read `import_count` and specifier string indices; resolve via string table for the import listing.
- [ ] Parse section 5 (shape table) per 03 §9: for each shape, list field names (string table) in `--verbose` (and default if spec/task agreement: prefer **verbose-only** for large tables to match acceptance “full table dumps”).
- [ ] Parse section 6 (ADT table) per 03 §10: type name, each constructor name, note payload vs. none (`0xFFFF_FFFF`).
- [ ] Integrate function boundaries into the code walk: before the first instruction at each distinct function `code_offset`, print the required banner (module initializer: functions with offset `0` or top-level chunk—treat entry at code section start as initializer if no function claims it, or label per compiler convention once inspected in `write.ts`).
- [ ] Refine debug behaviour if needed: ensure populated debug maps to file:line annotations per acceptance; binary-search on sorted entries is allowed (03 §8) — current linear scan works but may be slow on huge files (optional optimization).
- [ ] Add CLI flags: `--verbose` (emit import + shape + ADT sections before code, or clearly sectioned), `--code-only` (minimal lines only). Default: current-style listing plus function boundary comments, debug annotations when present, **without** full shape/ADT dump unless `--verbose`.
- [ ] Update `scripts/kestrel` usage and `cmd_dis` to forward flags to `disasm.js`.
- [ ] Align `OP_NAMES` / operand decoding with 04 for any missing opcodes encountered in real `.kbc` files (e.g. `KIND_IS` and others).
- [ ] Run `cd compiler && npm run build && npm test` and spot-check `./kestrel dis` on a small script and one with imports/shapes/ADTs.

## Build notes

- Implemented parsing of section 2 (function table, import table), section 5 (shape table), and section 6 (ADT table)
- Added function boundary markers in disassembly output with format `--- function "name" (arity N, offset 0xABC) ---`
- Added module initializer boundary `--- function "<module>" (arity 0, offset 0x00000000) ---` when no function claims offset 0
- Added CLI flags: `--verbose` for full table dumps (imports, shapes, ADTs), `--code-only` for minimal instruction-only output
- Fixed readU32 to handle unsigned 32-bit values correctly (was returning signed due to JS bitwise ops)
- Added KIND_IS opcode support (0x25)
- Updated scripts/kestrel to forward flags to disassembler
- All existing compiler tests pass
- Tested on various scripts: empty.ks, records.test.ks, functions.test.ks

## Tests to add

| Layer | Intent |
|-------|--------|
| **Vitest** | `compiler/test/unit/disasm.test.ts` (or `integration/`): build or load a minimal `.kbc` fixture (compile tiny `.ks` via existing compile helper if available, or hand-crafted bytes matching 03). Assert: function boundary line contains name and arity; with debug-enabled compile, output contains `file:line`; `--verbose` output contains import specifier substring; shape/ADT samples appear when present. Use `spawn`/`execFile` on `node dist/disasm.js` with temp files, or factor a testable `disassembleToLines(buffer, options)` export if refactoring is needed. |
| **Kestrel / E2E** | Optional: `tests/e2e/` or `scripts/run-e2e.sh` snippet invoking `./kestrel dis` with flags on a fixture script—only if the repo pattern prefers shell-level smoke; otherwise Vitest coverage is enough. |
| **Zig** | Not required unless bytecode format changes. |

## Documentation and specs to update

- [ ] `docs/specs/09-tools.md` §2.2 — document default vs. `--verbose` vs. `--code-only`, function boundary format, and table dump sections; update implementation table if flags are parsed in the shell vs. Node.
- [ ] `AGENTS.md` or `README.md` — one-line mention of `kestrel dis` flags if user-facing examples are maintained there (only if already describing `dis`).

## Notes

- **Module initializer vs. functions:** Confirm how `writeKbc` lays out top-level code vs. `function_count` entries (offset 0). Banner for “`<module>`” or first function must match how the VM enters the module (03 §2 header: entry is start of code section).
- **Imported function table (§6.6):** Verbose output may optionally list `(import_index, foreign_fn_index)` rows for debugging cross-module calls; defer if scope tight.
