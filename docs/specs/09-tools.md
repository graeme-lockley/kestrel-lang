# 09 – Developer Tools and CLI

Version: 1.0

---

This document specifies the Kestrel developer toolchain: the unified `kestrel` CLI and its subcommands. Implementors and users invoke the CLI to build, run, and inspect Kestrel programs.

---

## 1. Entry Point

- **Name:** `kestrel`
- **Usage:** `kestrel <command> [options]`
- **Location:** A single entry point at the repository root (`./kestrel` or `scripts/kestrel`) exposes all commands. The root script delegates to `scripts/kestrel`.
- **Topology:** In `self-hosted` mode (see `kestrel status`), `scripts/kestrel` dispatches normal commands (`run`, `dis`, `build`, `test`, `fmt`, `doc`, `lock`) directly to bootstrap-generated self-hosted compiler classes in `~/.kestrel/bootstrap/self-hosted/` by default. Set `KESTREL_BOOTSTRAP_ROOT` to override the bootstrap artifact root.
- **Fallback:** Normal command execution does not fall back to the TypeScript compiler path when bootstrap state is missing. Users must restore self-hosted artifacts with `./scripts/build-bootstrap-jar.sh` and `./kestrel bootstrap`.
- **Dependencies:** Requires `node`, `java`, and `javac` on `PATH` for full toolchain flows. Normal post-bootstrap command execution does not invoke the bootstrap JAR.

---

## 2. Commands

### 2.1 run

**Usage:** `kestrel run [--exit-wait|--exit-no-wait] [--refresh] [--allow-http] [--clean] <script[.ks]|kestrel:module/path> [args...]`

- **Effect:** Compiles the named Kestrel script (and its constituent packages) if the target binary is stale or missing, then executes it via the JVM runtime.
- **Module specifiers:** In addition to file paths, `kestrel run` accepts stdlib module specifiers of the form `kestrel:<module/path>` (e.g. `kestrel run kestrel:tools/test`, `kestrel run kestrel:tools/format`). The specifier is resolved to the physical stdlib file (`$KESTREL_ROOT/stdlib/kestrel/<module/path>.ks`) before compilation. If the specifier names a module that does not exist, an error is printed and the command exits non-zero. File-path invocations are unaffected.
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
- **Mode behavior:** In `self-hosted` mode, this command is dispatched through self-hosted compiler classes by default. In `bootstrap-required` mode, script compilation fails with a remediation hint until bootstrap artifacts are restored.
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

### 2.3.0 Bootstrap compiler JAR packaging

**Usage:** `./scripts/build-bootstrap-jar.sh`

- **Purpose:** Build a canonical bootstrap compiler JAR artifact from the TypeScript compiler output for use by `kestrel bootstrap` seeding flows.
- **Output directory:** `~/.kestrel/bootstrap/compiler/` by default. Set `KESTREL_BOOTSTRAP_ROOT` to override.
- **Artifacts:**
  - `compiler-bootstrap.jar`
  - `compiler-bootstrap.meta` (checksum, revision, timestamp metadata)
- **Policy:** This JAR is a bootstrap-only artifact and is not part of normal `kestrel build/run/test` steady-state command execution.

### 2.3.1 Stage-0 bootstrap verification

**Usage:** `./scripts/bootstrap-stage0.sh [sample.ks]`

- **Purpose:** Validate Stage-0 bootstrap wiring by compiling the self-hosted compiler CLI entrypoint with the TypeScript compiler, then comparing semantic output of a non-trivial sample against a TypeScript-compiled baseline.
- **Default sample:** `samples/mandelbrot.ks`.
- **Prerequisites:** `node`, `java`, and `javac` on `PATH`.
- **Artifacts:** Writes temporary verification outputs under `.kestrel/bootstrap-stage0/`.
- **Success criteria:** Exits 0 and prints `PASS` when baseline and post-bootstrap runtime outputs match.
- **Current limitation:** The Stage-0 compiled CLI invocation in this flow is a build-command smoke check; sample compilation for semantic comparison still uses the canonical `./kestrel build` path while self-hosted argument forwarding stabilizes.

### 2.3.2 Stage-1 bootstrap verification

**Usage:** `./scripts/bootstrap-stage1.sh [sample.ks]`

- **Purpose:** Validate Stage-1 bootstrap wiring against the Stage-0 baseline by generating a Stage-1 candidate CLI artifact, running build-command smoke checks, and comparing semantic sample output.
- **Default sample:** `samples/mandelbrot.ks`.
- **Prerequisites:** `node`, `java`, and `javac` on `PATH`.
- **Artifacts:** Writes temporary verification outputs under `.kestrel/bootstrap-stage1/` and reuses Stage-0 outputs from `.kestrel/bootstrap-stage0/`.
- **Success criteria:** Exits 0 and prints `PASS` when Stage-1 semantic output matches Stage-0 baseline.
- **Status:** Stage-1 script verifies semantic parity against the Stage-0 baseline and acts as an additional bootstrap regression check.

### 2.3.3 bootstrap

**Usage:** `kestrel bootstrap`

- **Purpose:** Seed self-hosted compiler classes using the bootstrap compiler JAR.
- **Prerequisites:**
  - Runtime JAR exists at `runtime/jvm/kestrel-runtime.jar`.
  - Bootstrap compiler JAR exists at `~/.kestrel/bootstrap/compiler/compiler-bootstrap.jar` by default (produced by `./scripts/build-bootstrap-jar.sh`).
- **Output directory:** `~/.kestrel/bootstrap/self-hosted/` by default.
- **Execution model:** Runs the bootstrap compiler entry class (`Cli_entry`) on the JVM with classpath `kestrel-runtime.jar:compiler-bootstrap.jar` to compile `stdlib/kestrel/tools/compiler/cli-entry.ks` and its dependencies into self-hosted class artifacts.
- **Validation:** Fails if required compiler entry classes (`Cli_entry.class`, `Cli_main.class`) are missing from bootstrap output.
- **Failure diagnostics:** Emits explicit errors for missing runtime artifact, missing bootstrap JAR, and bootstrap compilation failures.
- **Idempotence:** Repeated invocations refresh bootstrap output classes deterministically in place.

### 2.3.4 status

**Usage:** `kestrel status`

- **Purpose:** Report active compiler mode and bootstrap provenance state.
- **Mode values:**
  - `self-hosted` — bootstrap state file exists and points to valid self-hosted compiler classes.
  - `bootstrap-required` — bootstrap state missing/invalid or output classes unavailable.
- **State file:** `~/.kestrel/bootstrap/state.env` by default.
- **Schema fields:**
  - `schema`
  - `mode`
  - `updated_utc`
  - `bootstrap_jar`
  - `bootstrap_jar_sha256`
  - `git_revision`
  - `output_classes`
  - `entry_source`
- **Recovery guidance:** When mode is `bootstrap-required`, command prints a remediation hint to run `./scripts/build-bootstrap-jar.sh` and `./kestrel bootstrap`.
- **CI contract:** Post-bootstrap CI checks should assert `compiler mode: self-hosted` before running normal `build`/`run`/`test` smoke commands.

### 2.4 test

**Usage:** `kestrel test [--verbose|--summary] [--clean] [--refresh] [--allow-http] [files...]`

- **Effect:** Runs the Kestrel unit test suite via [`kestrel:tools/test`](../../stdlib/kestrel/tools/test.ks) (invoked as `./kestrel run kestrel:tools/test "$@"`), which delegates to `kestrel:tools/test/discovery` and `kestrel:tools/test/runner`, writes a generated runner (`.kestrel_test_runner.ks` under the current working directory / project root) and executes it. If no file arguments are given, the runner discovers all `*.test.ks` under `tests/unit/` and `stdlib/kestrel/` (up to 3 directory levels) via `kestrel:io/fs` `listDir` calls; discovery failures terminate with a non-zero exit before test execution. With file arguments, only those tests run (paths relative to the current working directory).
- **Project root:** The project root is `getProcess().cwd` — the working directory when `kestrel test` is invoked. Always run `kestrel test` from the project root.
- **Kestrel binary:** `kestrel:tools/test` locates the Kestrel binary via the `KESTREL_BIN` environment variable. `cmd_test` sets `KESTREL_BIN="$ROOT/kestrel"` before exec. Fallback is `${proc.cwd}/kestrel`.
- **`--clean`:** Forwarded to the inner `./kestrel run .kestrel_test_runner.ks` invocation, clearing compiler cache for test files. Also passed as flag to `test-runner.ks` via `proc.args`.
- **`--refresh`:** Re-fetch all URL dependencies. Forwarded to the inner compilation.
- **`--allow-http`:** Accept `http://` URL specifiers. Forwarded to the inner compilation.
- **`--generate`:** Write `.kestrel_test_runner.ks` and exit without running tests. Useful for inspecting the generated source.
- **Output:** While compiling, the compiler may print short "Compiling …" lines. Test output comes from **`kestrel:dev/test`**: **compact** (default) prints each top-level suite name first, then silent sub-group `name (N✓ Tms)` summaries, then a dim count footer; **`--verbose`** prints per-assertion ✓ lines inside each group plus timing footers; **`--summary`** prints one `name (N✓ Tms)` compact line per top-level suite with no assertion detail. Any mode ends with a blank line and a total line such as green `N passed (…ms)` or red `M failed, N passed (…ms)` from `printSummary`.
- **Exit code:** 0 if all tests passed; 1 if any test failed or did not compile.

### 2.5 fmt

```
kestrel fmt [--check] [--stdin] [files-or-dirs...]
```

Formats one or more Kestrel source files in-place using the opinionated formatter (`stdlib/kestrel/tools/format.ks`). The formatter renders at 120 columns with 2-space indentation.

**File/directory arguments:**

- If no positional arguments are provided (and `--stdin` is not set), `fmt` recursively collects all `*.ks` files under the current working directory, skipping hidden directories (those whose name starts with `.`) and `node_modules`.
- If one or more arguments are provided, each is treated as either a file path (passed through directly) or a directory path (recursed into to find all `*.ks` files). Shell glob expansion (e.g. `stdlib/**/*.ks` in zsh with `globstar`) works naturally since the shell expands patterns before passing them to `fmt`.

**Flags:**

| Flag | Long | Description |
|------|------|-------------|
| `-c` | `--check` | Check-only mode: print each non-conforming file path and exit non-zero if any file is not formatted; do not modify files |
| | `--stdin` | Read source from stdin, write formatted output to stdout |
| `-h` | `--help` | Print usage and exit 0 |
| `-V` | `--version` | Print `kestrel fmt v0.1.0` and exit 0 |

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | All files formatted successfully (or all files already formatted in `--check` mode) |
| 1 | One or more files failed to format, or one or more files are not formatted (`--check` mode) |

**Formatting rules (summary):**

- Line width: 120 characters
- Indent unit: 2 spaces
- `fun` body: when the body is a block expression (`{ … }`), the opening `{` follows `=` on the same line and the block content is indented by 2 from the function signature; otherwise the body breaks to the next line indented by 2
- `match` arms: pattern and `=>` on one line, body on next line indented by 2; when the arm body is a block expression the `{` follows `=>` on the same line and block content is indented by 2
- `if/else` chain: if the entire chain (including all `else if`/`else` branches) fits on one line it is kept inline; otherwise each branch always breaks — `then` body indented by 2, `else`/`else if` at the same column as `if`, `else` body indented by 2. When any branch body is a block expression the chain always breaks (blocks cannot render inline). Block `{` always stays on the same line as `if (…)` / `else`.
- Pipelines (`|>`) always break: each step on its own line indented by 2
- ADT type with ≥2 constructors: each constructor on its own line with `| ` prefix
- Blank line between each top-level declaration
- Always exactly one trailing newline

**Known limitations:**

- Comments that appear inside expressions or function bodies are not preserved; only leading comments immediately before a top-level declaration are re-attached in the output.

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

### 2.10 doc

```
kestrel doc [--port PORT] [--project-root PATH]
```

Starts a local HTTP documentation browser server powered by `stdlib/kestrel/tools/doc.ks`. On startup the server discovers and extracts doc-comments from all stdlib `kestrel:*` modules and any project `.ks` files found under `--project-root`, builds a search index, and begins serving HTML pages on the specified port.

**Flags:**

| Flag | Long | Description |
|------|------|-------------|
| `-p PORT` | `--port PORT` | Port to listen on (default: `7070`) |
| | `--project-root PATH` | Root directory to scan for project modules (default: current working directory) |
| `-h` | `--help` | Print usage and exit 0 |
| `-V` | `--version` | Print version and exit 0 |

**Routes served:**

| Method | Path | Response |
|--------|------|----------|
| `GET` | `/` | 302 redirect to `/docs/` |
| `GET` | `/docs/` | HTML module list page (all discovered modules) |
| `GET` | `/docs/<module-spec>` | HTML module detail page; 404 if not found |
| `GET` | `/api/search?q=<query>` | JSON array of `SearchResult` objects |
| `GET` | `/api/index` | JSON dump of the full search index |
| `GET` | `/api/reload-token` | Plain-text monotonic integer; increments after each live reload |
| `GET` | `/docs/static/style.css` | Embedded CSS for the documentation browser |
| `GET` | `/docs/static/search.js` | Embedded JavaScript for the search widget and live-reload polling |

**Module discovery:**

- **Stdlib modules:** All `*.ks` files (excluding `*.test.ks`) under `$KESTREL_ROOT/stdlib/kestrel/` are loaded. Specifiers are derived by stripping the `stdlib/kestrel/` prefix and `.ks` suffix then prepending `kestrel:`.
- **Project modules:** All `*.ks` files (excluding `*.test.ks`) under `--project-root` that are not already covered by the stdlib tree are loaded. Specifiers use the `project:` prefix followed by the path relative to the project root.
- Files and directories whose base name starts with `.` or equals `node_modules` are skipped.
- Extraction failures (e.g. parse errors in a file) are silently dropped; the module is simply absent from the index.

**Live reload:**

After the server starts, background watcher tasks monitor `$KESTREL_ROOT/stdlib/kestrel/` and `--project-root` for file-system changes (using `kestrel:io/fs.watchDir` with a 500 ms debounce). When `.ks` files change:

1. Only the affected modules are re-extracted.
2. The in-memory `DocIndex` is rebuilt.
3. The `/api/reload-token` counter increments.

The served JavaScript polls `/api/reload-token` every second; when the token changes, the browser calls `location.reload()`. Round-trip latency is typically under 2 seconds on a developer laptop. If a watched directory fails to open (e.g. it does not exist), the server logs a warning and continues serving the stale index.

**Startup message:**

On successful server start the tool prints:
```
Docs available at http://localhost:<port>/docs/
```

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | Server started and running (process does not exit unless killed) |
| 1 | Invalid flag / argument, or server failed to bind |

---

## 3. Editor Integration (VS Code)

Kestrel provides a VS Code extension (`vscode-kestrel/`) that hosts a language server and editor tooling for `.ks` files.

- Extension entrypoint: `vscode-kestrel/dist/src/extension.js`
- Language server entrypoint: `vscode-kestrel/dist/src/server/server.js`
- Protocol baseline: Language Server Protocol 3.17-compatible request/notification surface (using `vscode-languageserver` 9.x)

Supported capabilities in the current integration:

- `textDocument/publishDiagnostics`
- `textDocument/hover`
- `textDocument/documentSymbol`
- `textDocument/foldingRange`
- `textDocument/definition`
- `textDocument/completion`
- `textDocument/signatureHelp`
- `textDocument/semanticTokens/full`
- `textDocument/inlayHint`
- `textDocument/codeAction` (quick fixes)
- `textDocument/codeLens` (test lenses)

Supported settings:

- `kestrel.executable` — path or command name for the `kestrel` CLI used by extension commands.
- `kestrel.lsp.debounceMs` — debounce delay (ms) for on-change diagnostics scheduling in the language server.

The extension also contributes commands and task definitions for editor workflows:

- `kestrel.runTest`
- `kestrel.debugTest`
- task type `kestrel` with task kinds `run` and `test`

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
