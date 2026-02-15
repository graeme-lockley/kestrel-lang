# 09 – Developer Tools and CLI

Version: 1.0

---

This document specifies the Kestrel developer toolchain: the unified `kestrel` CLI and its subcommands. Implementors and users invoke the CLI to build, run, and inspect Kestrel programs.

---

## 1. Entry Point

- **Name:** `kestrel`
- **Usage:** `kestrel <command> [options]`
- **Location:** A single entry point at the repository root (`./kestrel` or `scripts/kestrel`) exposes all commands. The root script delegates to `scripts/kestrel`.
- **Dependencies:** Requires `node` and `zig` on `PATH` to build and run. The CLI builds the compiler (TypeScript) and VM (Zig) on demand when they are missing or when `build` is invoked.

---

## 2. Commands

### 2.1 run

**Usage:** `kestrel run <script[.ks]> [args...]`

- **Effect:** Compiles the named Kestrel script (and its constituent packages) if the binary is stale or missing, then executes it via the VM.
- **Freshness:** The script is compiled when (a) the `.kbc` binary does not exist, or (b) the `.ks` source is newer than the existing `.kbc`.
- **Cache:** Compiled `.kbc` files are stored under `~/.kestrel/kbc/`, mirroring the absolute path of the source. For example, `/Users/me/proj/foo.ks` → `~/.kestrel/kbc/Users/me/proj/foo.kbc`. This avoids cluttering the project directory. Override with `KESTREL_CACHE` (e.g. `KESTREL_CACHE=/tmp/kbc kestrel run foo.ks`).
- **Execution:** The VM ([05-runtime-model.md](05-runtime-model.md)) loads the compiled bytecode and runs it. Any additional arguments (`args...`) are passed through to the VM (VM behaviour for script arguments is implementation-defined).
- **Errors:** Compile errors are reported on stderr; the process exits non-zero. VM errors (e.g. uncaught exception) produce non-zero exit as per the runtime model.

### 2.2 dis

**Usage:** `kestrel dis <script[.ks]>`

- **Effect:** Compiles the named script if needed (same freshness rules as `run`; output cached under `~/.kestrel/kbc/` as for `run`), then unpacks the `.kbc` and prints the disassembled bytecode in mnemonic form.
- **Output:** Each instruction is printed with its byte offset and mnemonic (e.g. `LOAD_CONST 0`, `ADD`, `RET`). Format follows [04-bytecode-isa.md](04-bytecode-isa.md) instruction encoding.
- **Purpose:** Debugging and inspection of emitted bytecode.

### 2.3 build

**Usage:** `kestrel build [script[.ks]]`

- **Effect:** Builds the compiler and VM so that binaries are up-to-date. If a script path is provided, also compiles that script to `.kbc` (cached under `~/.kestrel/kbc/` as for `run`).
- **Build steps:** (1) `cd compiler && npm run build`; (2) `cd vm && zig build -Doptimize=ReleaseSafe`. Compiler output is `compiler/dist/`; VM output is `vm/zig-out/bin/kestrel`.
- **Optional script:** When `script[.ks]` is given, compiles it to the corresponding `.kbc` in the same directory.

---

## 3. Implementation Responsibilities

| Component | Language | Role |
|-----------|----------|------|
| **`kestrel` script** | **Bash** | Entry-point wrapper: parse subcommand and options, decide what to run, check freshness (binary older than source or missing ⇒ compile), invoke compiler, VM, or disassembler. |
| **Compile** | **TypeScript** | `compiler` (node `dist/cli.js`): parses `.ks`, typechecks ([06-typesystem.md](06-typesystem.md)), emits `.kbc` ([03-bytecode-format.md](03-bytecode-format.md)). |
| **Run** | **Zig** | VM (`vm/zig-out/bin/kestrel`): loads `.kbc` and executes per [04-bytecode-isa.md](04-bytecode-isa.md) and [05-runtime-model.md](05-runtime-model.md). |
| **Disassembler** | **TypeScript** | `compiler/disasm.ts`: reads `.kbc` code section, decodes instructions per [04-bytecode-isa.md](04-bytecode-isa.md), emits mnemonic listing. Built as `dist/disasm.js`. |

---

## 4. Relation to Other Specs

- [01-language.md](01-language.md) – Source language parsed by compiler
- [02-stdlib.md](02-stdlib.md) – Standard library available at runtime
- [03-bytecode-format.md](03-bytecode-format.md) – `.kbc` format produced by compiler and consumed by VM/disassembler
- [04-bytecode-isa.md](04-bytecode-isa.md) – Instruction set executed by VM and disassembled by `dis`
- [05-runtime-model.md](05-runtime-model.md) – VM execution semantics
- [06-typesystem.md](06-typesystem.md) – Type checking during compile
- [07-modules.md](07-modules.md) – Module resolution (future multi-file support)
- [08-tests.md](08-tests.md) – Test harnesses; `scripts/run-e2e.sh` uses compiler and VM directly for E2E
