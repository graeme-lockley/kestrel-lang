# Kestrel CLI script

## Description

Create a unified `kestrel` CLI that dispatches to subcommands, bringing binaries up-to-date as needed and delegating to the appropriate compiler (TS), VM (Zig), or disassembler.

**Usage:** `kestrel <command> [options]`

**Commands:**
- `run` — Execute a Kestrel script
- `dis` — Disassemble bytecode to mnemonic form
- `build` — Compile and bring binaries up-to-date

## Acceptance Criteria

- [x] Invoking `kestrel run <script[.ks]> [args...]` compiles the script (and its constituent packages) if the binary is stale or missing, then executes it via the VM with the given args.
- [x] Invoking `kestrel dis <script[.ks]>` compiles the script if needed, then unpacks the binary and prints the disassembled bytecode in mnemonic form.
- [x] Invoking `kestrel build [script[.ks]]` builds compiler and VM; optionally compiles the given script to .kbc.
- [x] A single `kestrel` entry point (./kestrel at repo root, delegates to scripts/kestrel) exposes all three commands.
- [x] The story document specifies which language implements each piece.

## Language Responsibilities

| Piece | Language | Role |
|-------|----------|------|
| **`kestrel` script** | **Bash** | Entry-point wrapper: parse `kestrel <command> options`, decide what to run, manage freshness (binary older than source or missing ⇒ rebuild), invoke TS/Zig tools. |
| **Compile** | **TypeScript** | Existing `compiler` (node `dist/cli.js`): parses .ks, typechecks, emits .kbc. Called by the bash script when a script needs compilation. |
| **Run** | **Zig** | Existing VM (`vm/zig-out/bin/kestrel`): loads .kbc, executes bytecode. Called by the bash script to run the compiled binary. |
| **Build** | **Bash + TS + Zig** | Bash orchestrates: `cd compiler && npm run build`, `cd vm && zig build`. Brings compiler and VM binaries up-to-date. |
| **Disassembler** | **TypeScript** | `compiler/disasm.ts`: reads .kbc, walks code section (spec 04), emits mnemonic listing (e.g. `LOAD_CONST 0`, `ADD`, `RET`). Built as `dist/disasm.js`. |

## Tasks

- [x] Add Tasks section with checkboxes
- [x] Create `scripts/kestrel` bash script (run, dis, build)
- [x] Implement disassembler in TypeScript (compiler)
- [x] Wire disassembler CLI (disasm.js / npm run disasm)
- [x] Verify run/dis/build and update story
