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

**Usage:** `kestrel run [--exit-wait|--exit-no-wait] [--refresh] [--allow-http] [--clean] <script[.ks]> [args...]`

- **Effect:** Compiles the named Kestrel script (and its constituent packages) if the target binary is stale or missing, then executes it via the JVM runtime.
- **Target:** JVM is the only execution target; compiled `.class` files are generated for the Java Virtual Machine.
- **Freshness:** The script is compiled when (a) the generated `.class` files do not exist, or (b) the entry `.ks` is newer than the main generated class, or (c) a `.class.deps` file exists beside that class and any listed dependency path is newer.
- **URL dependencies:** If any module in the dependency graph contains URL specifiers (`https://`), they are resolved using the URL import cache (see §2.9). On cache miss the source is fetched transparently before compilation proceeds. `--refresh` forces all URL dependencies to be re-fetched even if already cached.
- **`--allow-http`:** Accept `http://` URL specifiers in addition to `https://`. Without this flag, `http://` imports are a compile error.
- **`--clean`:** Delete all `.kti` incremental-compilation cache files from the output directory (recursively) before compiling. Forces a full recompile from source for all packages in the dependency graph. If no output directory is configured, silently ignored. `--clean --refresh` combines both: deletes `.kti` files and re-fetches URL dependencies.
- **Cache:**
  - Compiled `.class` files are stored under `~/.kestrel/jvm/`, mirroring the absolute path of the source. For example, `/Users/me/proj/foo.ks` → `~/.kestrel/jvm/Users/me/proj/foo.class`. This avoids cluttering the project directory. Override with `KESTREL_JVM_CACHE` (e.g. `KESTREL_JVM_CACHE=/tmp/jvm kestrel run foo.ks`).
- **Execution:** `kestrel` runs `java` with a classpath containing `kestrel-runtime.jar` and the JVM cache root, and uses a main class derived from the entry source file path (strip leading `/`, remove `.ks`, capitalize the last path segment; convert `/` to `.` for the Java binary name). Entry-point discovery is implementation-defined, but the derived class name is stable for a given absolute source path.
- **Maven classpath:** when modules in the run graph emit `.kdeps` sidecars (from `maven:` imports), `kestrel run` reads those sidecars transitively, appends resolved jars to the JVM classpath, and validates coordinate version consistency.
- **Dependency conflicts:** if two modules require different versions of the same Maven coordinate (`groupId:artifactId`), `kestrel run` reports a conflict and exits non-zero before launching the JVM.
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

**Usage:** `kestrel build [--refresh] [--allow-http] [--status] [--clean] [script[.ks]]`

- **Effect:** Builds the compiler so that it is up-to-date. If a script path is provided, also compiles that script to a `.class` file using the same cache and freshness rules as `run`.
- **Build steps:** `cd compiler && npm run build`. Compiler output is `compiler/dist/`.
- **URL dependencies:** Same on-demand fetch behaviour as `run` (see §2.9). `--refresh` and `--allow-http` have the same meaning as for `run`.
- **`--clean`:** Same as for `run`: delete all `.kti` incremental-cache files from the output directory before compiling. If no output directory is configured, silently ignored.
- **`--status`:** When `--status` is provided, the compiler is built (if needed) but the script is **not** compiled or run. Instead, the full transitive dependency graph is resolved and a pretty-printed report is printed to stdout showing the cache state of every URL dependency. Exit 0 on success.

  Report format example:
  ```
  Dependencies for hello.ks
  ─────────────────────────────────────────────────────────
  https://example.com/lib.ks          ✓ cached   3 days ago
  https://other.com/util.ks           ✓ cached   9 days ago  ⚠ stale
  https://new.com/mod.ks              ✗ not cached
  ─────────────────────────────────────────────────────────
  3 URL dependencies  (1 stale, 1 not cached)
  ```

  Columns are aligned. Stale entries (older than `KESTREL_CACHE_TTL`) are marked ⚠. Entries not yet cached are marked ✗. Local (path/stdlib) dependencies are omitted from this report.
- **`--status` with `--refresh`:** Not a valid combination; exits non-zero with a usage error.

### 2.4 test

**Usage:** `kestrel test [--verbose|--summary] [--clean] [--refresh] [--allow-http] [files...]`

- **Effect:** Runs the Kestrel unit test suite via [`scripts/run_tests.ks`](../../scripts/run_tests.ks), which compiles dependencies, writes a generated runner (e.g. `.kestrel_test_runner.ks` under the project root), and executes it on the JVM runtime. If no file arguments are given, the runner discovers all `*.test.ks` under `tests/unit/` and `stdlib/kestrel/` via awaited `kestrel:fs` `listDir` calls; discovery failures terminate with a non-zero exit before test execution. With file arguments, only those tests run (paths relative to the current working directory).
- **`--clean`:** Delete all `.kti` incremental-cache files before compiling the test runner, forcing a full recompile from source. Has the same semantics as `--clean` for `run` and `build`.
- **`--refresh`:** Re-fetch all URL dependencies before compiling. Same semantics as `--refresh` for `run` and `build`.
- **`--allow-http`:** Accept `http://` URL specifiers. Same semantics as `--allow-http` for `run` and `build`.
- **Output:** While compiling, the compiler may print short "Compiling …" lines. Test output comes from **`kestrel:test`**: **compact** (default) prints each top-level suite name first, then silent sub-group `name (N✓ Tms)` summaries, then a dim count footer; **`--verbose`** prints per-assertion ✓ lines inside each group plus timing footers; **`--summary`** prints one `name (N✓ Tms)` compact line per top-level suite with no assertion detail. Any mode ends with a blank line and a total line such as green `N passed (…ms)` or red `M failed, N passed (…ms)` from `printSummary`.
- **Exit code:** 0 if all tests passed; 1 if any test failed or did not compile.

### 2.5 (reserved)

### 2.6 Compiler options (diagnostics)

When the compiler is invoked (e.g. by `run`, `build`, or directly), it accepts:

- **`--format=json`** — Emit diagnostics in machine-readable form (JSON Lines, one JSON object per diagnostic on stderr). See [10-compile-diagnostics.md](10-compile-diagnostics.md) §7 for the exact format. When omitted, diagnostics are printed in human-readable form per §6.

### 2.7 JVM backend limitations

- **Namespace-qualified ADT constructors** (`M.Ctor` / `M.Ctor(…)` after `import * as M`, 07 §2.3) are **not** supported on the JVM compile path. The compiler must fail with a clear diagnostic (stable code `compile:jvm_namespace_constructor`, 10 §4). Expose a normal exported function in the dependency that performs the construction.

### 2.8 Maven cache and sidecars

- **`maven:` import declaration:** `import "maven:groupId:artifactId:version"` is a compile-time classpath declaration.
- **Cache location:** downloaded jars are cached at `~/.kestrel/maven/<groupId path>/<artifactId>/<version>/<artifactId>-<version>.jar`.
- **Cache override:** set `KESTREL_MAVEN_CACHE` to change the local Maven cache root.
- **Repository override:** set `KESTREL_MAVEN_REPO` to change the Maven repository root (default `https://repo1.maven.org/maven2`).
- **Offline mode:** set `KESTREL_MAVEN_OFFLINE=1` (or `true`) to disable downloads and fail on cache miss.
- **Sidecar format:** for modules with `maven:` imports, the compiler emits `<ClassName>.kdeps` alongside `<ClassName>.class`, recording Maven coordinates, resolved jar paths, and checksums.

### 2.9 URL import cache

- **Cache root:** `~/.kestrel/cache/` by default; overridable via `KESTREL_CACHE`. Created on first use.
- **Cache layout:** `<cacheRoot>/<sha256-of-url>/source.ks` where the directory name is the lowercase hex SHA-256 of the URL string.
- **On-demand fetch:** When a URL specifier is encountered during compilation and no cached copy exists, the source is fetched over HTTPS and written to the cache. Compilation then proceeds using the cached file. This is fully transparent to the user.
- **Cache hit:** Cached file is used directly; no network request.
- **`--refresh`:** All URL dependencies are re-fetched and the cache updated before compilation.
- **Staleness threshold:** `KESTREL_CACHE_TTL` environment variable (seconds, default `604800` = 7 days). Stale entries are used for compilation; `kestrel build --status` flags them. Only `--refresh` triggers a re-download.
- **`KESTREL_CACHE_TTL`:** Override staleness threshold in seconds.
- **SSRF / security:** `https://` only by default. `http://` accepted only with `--allow-http`. Redirects to a different host are not followed.

---

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
