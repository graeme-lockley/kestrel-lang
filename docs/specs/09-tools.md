# 09 – Developer Tools and CLI

Version: 1.0

---

This document specifies the Kestrel developer toolchain: the unified `kestrel` CLI and its subcommands. Implementors and users invoke the CLI to build, run, and inspect Kestrel programs.

---

## 1. Entry Point

- **Name:** `kestrel`
- **Usage:** `kestrel <command> [options]`
- **Location:** A single entry point at the repository root (`./kestrel` or `scripts/kestrel`) exposes all commands. The root script delegates to `scripts/kestrel`.
- **Dependencies:** Requires `node`, `java`, and `javac` on `PATH` to build and run. The CLI builds the compiler (TypeScript) on demand when it is missing or when `build` is invoked.

---

## 2. Commands

### 2.1 run

**Usage:** `kestrel run [--exit-wait|--exit-no-wait] <script[.ks]> [args...]`

- **Effect:** Compiles the named Kestrel script (and its constituent packages) if the target binary is stale or missing, then executes it via the JVM runtime.
- **Target:** JVM is the only execution target; compiled `.class` files are generated for the Java Virtual Machine.
- **Freshness:** The script is compiled when (a) the generated `.class` files do not exist, or (b) the entry `.ks` is newer than the main generated class, or (c) a `.class.deps` file exists beside that class and any listed dependency path is newer.
- **Cache:**
  - Compiled `.class` files are stored under `~/.kestrel/jvm/`, mirroring the absolute path of the source. For example, `/Users/me/proj/foo.ks` → `~/.kestrel/jvm/Users/me/proj/foo.class`. This avoids cluttering the project directory. Override with `KESTREL_JVM_CACHE` (e.g. `KESTREL_JVM_CACHE=/tmp/jvm kestrel run foo.ks`).
- **Execution:** `kestrel` runs `java` with a classpath containing `kestrel-runtime.jar` and the JVM cache root, and uses a main class derived from the entry source file path (strip leading `/`, remove `.ks`, capitalize the last path segment; convert `/` to `.` for the Java binary name). Entry-point discovery is implementation-defined, but the derived class name is stable for a given absolute source path.
- **Exit mode flags:**
  - **`--exit-wait` (default):** wait for pending async runtime work to quiesce before process exit, then perform orderly executor shutdown.
  - **`--exit-no-wait`:** exit after `main` returns; pending async tasks are abandoned and virtual threads may be interrupted via immediate shutdown.
  - Supplying both flags in one invocation is a CLI error with non-zero exit.
- **Run help:** `kestrel run --help` prints run-specific usage and describes both exit mode flags.
- **Errors:** Compile errors are reported on stderr; the process exits non-zero. Diagnostic format and behaviour are specified in [10-compile-diagnostics.md](10-compile-diagnostics.md). JVM runtime errors (e.g. uncaught exception) produce non-zero exit as per the runtime model.

### 2.2 dis

**Usage:** `kestrel dis [--verbose|--code-only] <script[.ks]>`

- **Effect:** Compiles the named script if needed (same freshness rules as `run`; output cached under `~/.kestrel/jvm/` as for `run`), then runs `javap` against the generated main class.
- **Output modes:**
  - **Default:** `javap -c -l`.
  - **`--verbose`:** `javap -verbose -c -l`.
  - **`--code-only`:** `javap -c`.
- **Format:** Output is the standard `javap` listing for JVM classfiles.
- **Purpose:** Inspection and debugging of compiled JVM bytecode.

### 2.3 build

**Usage:** `kestrel build [script[.ks]]`

- **Effect:** Builds the compiler so that it is up-to-date. If a script path is provided, also compiles that script to a `.class` file using the same cache and freshness rules as `run`.
- **Build steps:** `cd compiler && npm run build`. Compiler output is `compiler/dist/`.

### 2.4 test

**Usage:** `kestrel test [--verbose|--summary] [files...]`

- **Effect:** Runs the Kestrel unit test suite via [`scripts/run_tests.ks`](../../scripts/run_tests.ks), which compiles dependencies, writes a generated runner (e.g. `.kestrel_test_runner.ks` under the project root), and executes it on the JVM runtime. If no file arguments are given, the runner discovers all `*.test.ks` under `tests/unit/` and `stdlib/kestrel/`. With file arguments, only those tests run (paths relative to the current working directory). **`--verbose` and `--summary` together** are rejected with a non-zero exit before tests run (see [02-stdlib.md](02-stdlib.md) **kestrel:test**).
- **Output:** While compiling, the compiler may print short “Compiling …” lines. Test output comes from **`kestrel:test`**: default **compact** mode prints a nested tree (group summaries, green ✓ counts, dim timing, etc.); **`--verbose`** prints per-assertion lines; **`--summary`** suppresses passing chrome. The run ends with a blank line and a total line such as green `N passed (…ms)` or red `M failed, N passed (…ms)` from `printSummary`.
- **Exit code:** 0 if all tests passed; 1 if any test failed, did not compile, or flag validation failed.

### 2.5 (reserved)

### 2.6 Compiler options (diagnostics)

When the compiler is invoked (e.g. by `run`, `build`, or directly), it accepts:

- **`--format=json`** — Emit diagnostics in machine-readable form (JSON Lines, one JSON object per diagnostic on stderr). See [10-compile-diagnostics.md](10-compile-diagnostics.md) §7 for the exact format. When omitted, diagnostics are printed in human-readable form per §6.

### 2.7 JVM backend limitations

- **Namespace-qualified ADT constructors** (`M.Ctor` / `M.Ctor(…)` after `import * as M`, 07 §2.3) are **not** supported on the JVM compile path. The compiler must fail with a clear diagnostic (stable code `compile:jvm_namespace_constructor`, 10 §4). Expose a normal exported function in the dependency that performs the construction.

---

## 3. Implementation Responsibilities

| Component | Language | Role |
|-----------|----------|------|
| **`kestrel` script** | **Bash** | Entry-point wrapper: parse subcommand and options, decide what to run, check freshness (binary older than source or missing ⇒ compile), invoke compiler or `javap`. |
| **Compile** | **TypeScript** | `compiler` (node `dist/cli.js`): parses `.ks`, typechecks ([06-typesystem.md](06-typesystem.md)), emits `.class` files for JVM execution. |
| **Run (jvm)** | **Java** | JVM (`java`): loads generated `.class` files and executes the entry main class on top of `kestrel-runtime.jar`. |
| **Disassembler** | **JDK tool** | `javap`: disassembles generated `.class` files. |

---

## 4. Relation to Other Specs

- [01-language.md](01-language.md) – Source language parsed by compiler
- [02-stdlib.md](02-stdlib.md) – Standard library available at runtime
- [06-typesystem.md](06-typesystem.md) – Type checking during compile
- [07-modules.md](07-modules.md) – Module resolution (future multi-file support)
- [08-tests.md](08-tests.md) – Test harnesses: **`cd compiler && npm test`** runs parse, typecheck, and runtime conformance corpora under `tests/conformance/` (Vitest integration tests). **`scripts/run-e2e.sh`** drives the compiler (`dist/cli.js`) and JVM runtime on `tests/e2e/scenarios/negative/*.ks` (expect failure) and `tests/e2e/scenarios/positive/*.ks` (stdout vs `*.expected`); it does **not** replace the conformance runtime tree (see 08 §3.3).
- [10-compile-diagnostics.md](10-compile-diagnostics.md) – Compile-time diagnostics and error reporting (format, API, CLI)
