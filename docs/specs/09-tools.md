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

**Usage:** `kestrel run [--target vm|jvm] <script[.ks]> [args...]`

- **Effect:** Compiles the named Kestrel script (and its constituent packages) if the target binary is stale or missing, then executes it via the selected runtime.
- **Target:** `vm` (default) executes via the Zig VM; `jvm` executes via the JVM using generated `.class` files.
- **Freshness:** For `vm`, the script is compiled when (a) the `.kbc` binary does not exist, or (b) the entry `.ks` is newer than the `.kbc`, or (c) a `.kbc.deps` file exists beside the cached bytecode and any listed path (transitive `.ks` sources and each imported module’s `.kbc`) has modification time greater than or equal to the entry `.kbc`—so consumers recompile when a dependency’s bytecode or source changes. For `jvm`, compilation is also driven by `.class` freshness using a dependency list stored alongside the class in `.class.deps`.
- **Cache:**
  - For `vm`, compiled `.kbc` files are stored under `~/.kestrel/kbc/`, mirroring the absolute path of the source. For example, `/Users/me/proj/foo.ks` → `~/.kestrel/kbc/Users/me/proj/foo.kbc`. This avoids cluttering the project directory. Override with `KESTREL_CACHE` (e.g. `KESTREL_CACHE=/tmp/kbc kestrel run foo.ks`).
  - For `jvm`, compiled `.class` files are stored under `~/.kestrel/jvm/`, mirroring the absolute path of the source. Override with `KESTREL_JVM_CACHE` (e.g. `KESTREL_JVM_CACHE=/tmp/jvm kestrel run --target jvm foo.ks`).
- **Execution (vm):** The VM ([05-runtime-model.md](05-runtime-model.md)) loads the compiled bytecode and runs it. Any additional arguments (`args...`) are passed through to the VM (VM behaviour for script arguments is implementation-defined).
- **Execution (jvm):** `kestrel` runs `java` with a classpath containing `kestrel-runtime.jar` and the JVM cache root, and uses a main class derived from the entry source file path (strip leading `/`, remove `.ks`, capitalize the last path segment; convert `/` to `.` for the Java binary name). Entry-point discovery is implementation-defined, but the derived class name is stable for a given absolute source path.
- **Errors:** Compile errors are reported on stderr; the process exits non-zero. Diagnostic format and behaviour are specified in [10-compile-diagnostics.md](10-compile-diagnostics.md). VM/JVM runtime errors (e.g. uncaught exception) produce non-zero exit as per the runtime model.

### 2.2 dis

**Usage:** `kestrel dis [--verbose|--code-only] <script[.ks]>`

- **Effect:** Compiles the named script if needed (same freshness rules as `run`; output cached under `~/.kestrel/kbc/` as for `run`), then unpacks the `.kbc` and prints the disassembled bytecode in mnemonic form.
- **Output modes:**
  - **Default:** Shows code section with function boundaries (`; --- function "name" (arity N, offset 0xABC) ---`), debug annotations when present (`; --- file:line ---`), and constant comments.
  - **`--verbose`:** Additionally shows import table, shape table, and ADT table before the code section.
  - **`--code-only`:** Shows only raw instruction lines without comments, headers, or table dumps.
- **Function boundaries:** When the bytecode contains a function table (03 §6.1), the disassembler marks each function's code region with a boundary comment. The module initializer (top-level code) is labeled `"<module>"` if no function claims offset 0.
- **Table dumps (--verbose only):** Imports list module specifiers; shapes show field names and types; ADTs show constructor names and payload status.
- **Format:** Each instruction is printed with its byte offset and mnemonic (e.g. `LOAD_CONST 0`, `ADD`, `RET`). Format follows [04-bytecode-isa.md](04-bytecode-isa.md) instruction encoding. When the bytecode includes a non-empty debug section (03 §8), instructions are annotated with source file and line.
- **Purpose:** Debugging and inspection of emitted bytecode.

### 2.3 build

**Usage:** `kestrel build [--target vm|jvm] [script[.ks]]`

- **Effect:** Builds the compiler and VM so that binaries are up-to-date. If a script path is provided, also compiles that script for the selected target (`vm` ⇒ `.kbc`, `jvm` ⇒ `.class`) using the same cache and freshness rules as `run`.
- **Build steps:** (1) `cd compiler && npm run build`; (2) `cd vm && zig build -Doptimize=ReleaseSafe`. Compiler output is `compiler/dist/`; VM output is `vm/zig-out/bin/kestrel`.
- **Optional script:** When `script[.ks]` is given, compiles it to the corresponding output for the selected target (`vm` ⇒ `.kbc`, `jvm` ⇒ `.class`) under the same cache root as `run`.

### 2.4 test

**Usage:** `kestrel test [--target vm|jvm] [--verbose|--summary] [files...]`

- **Effect:** Runs the Kestrel unit test suite via [`scripts/run_tests.ks`](../../scripts/run_tests.ks), which compiles dependencies, writes a generated runner (e.g. `.kestrel_test_runner.ks` under the project root), and executes it on the chosen backend. If no file arguments are given, the runner discovers all `*.test.ks` under `tests/unit/` and `stdlib/kestrel/`. With file arguments, only those tests run (paths relative to the current working directory). **`--verbose` and `--summary` together** are rejected with a non-zero exit before tests run (see [02-stdlib.md](02-stdlib.md) **kestrel:test**).
- **Output:** While compiling, the compiler may print short “Compiling …” lines. Test output comes from **`kestrel:test`**: default **compact** mode prints a nested tree (group summaries, green ✓ counts, dim timing, etc.); **`--verbose`** prints per-assertion lines; **`--summary`** suppresses passing chrome. The run ends with a blank line and a total line such as green `N passed (…ms)` or red `M failed, N passed (…ms)` from `printSummary`.
- **Exit code:** 0 if all tests passed; 1 if any test failed, did not compile, or flag validation failed.

### 2.5 test-both

**Usage:** `kestrel test-both [files...]`

- **Effect:** Runs the same unit test selection as `kestrel test` twice: once on the Zig VM and once on the JVM (same file list and discovery rules as §2.4). Requires `node`, `zig`, `java`, `javac`, and `perl` on `PATH`. Builds the compiler and VM and the JVM runtime jar when missing, as for `run` / `test`.
- **Output:** Prints only a compact comparison, using the same ANSI styling vocabulary as the test harness ([`stdlib/kestrel/console.ks`](../../stdlib/kestrel/console.ks)): default-weight and dim text, **bold** for emphasis, green for success and faster timing, red for failures and non-zero exit, and ✓/✗ where failures are listed. Content: wall-clock time for each full run (including any compile steps), a relative speed line (which backend was faster and by how much, with a simple ratio), and parsed pass/fail counts plus in-harness elapsed milliseconds from the test framework’s final summary line ([`stdlib/kestrel/test.ks`](../../stdlib/kestrel/test.ks) `printSummary`). The harness still parses that summary the same way if individual assertions use `eq`, `neq`, `isTrue`/`isFalse`, ordering helpers, or `throws` (all update the same `Suite.counts`). If any assertion printed a failure (✗), lists those descriptions per backend and, when both backends had failures, a sorted `comm` diff of descriptions that appear on only one side.
- **Exit code:** 0 only if **both** runs exited 0; otherwise 1.

### 2.6 Compiler options (diagnostics)

When the compiler is invoked (e.g. by `run`, `build`, or directly), it accepts:

- **`--format=json`** — Emit diagnostics in machine-readable form (JSON Lines, one JSON object per diagnostic on stderr). See [10-compile-diagnostics.md](10-compile-diagnostics.md) §7 for the exact format. When omitted, diagnostics are printed in human-readable form per §6.

### 2.7 JVM backend limitations

- **Namespace-qualified ADT constructors** (`M.Ctor` / `M.Ctor(…)` after `import * as M`, 07 §2.3) are **not** supported on the JVM compile path. The compiler must fail with a clear diagnostic (stable code `compile:jvm_namespace_constructor`, 10 §4). Use the **VM** target (`kestrel run`, default) or expose a normal exported function in the dependency that performs the construction.

---

## 3. Implementation Responsibilities

| Component | Language | Role |
|-----------|----------|------|
| **`kestrel` script** | **Bash** | Entry-point wrapper: parse subcommand and options, decide what to run, check freshness (binary older than source or missing ⇒ compile), invoke compiler, VM, or disassembler. |
| **Compile** | **TypeScript** | `compiler` (node `dist/cli.js`): parses `.ks`, typechecks ([06-typesystem.md](06-typesystem.md)), emits `.kbc` ([03-bytecode-format.md](03-bytecode-format.md)). |
| **Run (vm)** | **Zig** | VM (`vm/zig-out/bin/kestrel`): loads `.kbc` and executes per [04-bytecode-isa.md](04-bytecode-isa.md) and [05-runtime-model.md](05-runtime-model.md). |
| **Run (jvm)** | **Java** | JVM (`java`): loads generated `.class` files and executes the entry main class on top of `kestrel-runtime.jar`. |
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
- [08-tests.md](08-tests.md) – Test harnesses: **`cd compiler && npm test`** runs parse, typecheck, and runtime conformance corpora under `tests/conformance/` (Vitest integration tests). **`scripts/run-e2e.sh`** drives the compiler (`dist/cli.js`) and Zig VM on `tests/e2e/scenarios/negative/*.ks` (expect failure) and `tests/e2e/scenarios/positive/*.ks` (stdout vs `*.expected`); it does **not** replace the conformance runtime tree (see 08 §3.3).
- [10-compile-diagnostics.md](10-compile-diagnostics.md) – Compile-time diagnostics and error reporting (format, API, CLI)
