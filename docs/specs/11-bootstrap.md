# 11 – Bootstrap and Self-Hosting

Version: 1.0

---

This document specifies the Kestrel bootstrap system: the process by which the TypeScript compiler produces bootstrap artifacts, `kestrel bootstrap` installs self-hosted compiler classes, and runtime gates enforce self-hosted mode for normal command execution.

---

## 1. Overview

Kestrel is a self-hosted language: the compiler is written in Kestrel and compiles to JVM bytecode. To break the chicken-and-egg cycle, a TypeScript compiler bootstraps the first generation of self-hosted compiler classes.

**Current invariant:** `kestrel bootstrap` installs classes from the bootstrap JAR and does not invoke the TypeScript compiler directly. After bootstrap, the Bash shim delegates normal commands to `kestrel/tools/Cli.class`, and the Kestrel CLI orchestrates command execution.

### 1.1 Architecture Stages

```
┌─────────────────────────┐
│  TypeScript Compiler     │  compiler/dist/cli.js
│  (Node.js seed)          │
└────────────┬────────────┘
             │ 1. build-bootstrap-jar.sh
             │    compiles cli-entry.ks + cli.ks → .class files → JAR
             ▼
┌─────────────────────────┐
│  Bootstrap JAR           │  ~/.kestrel/maven/lang/kestrel/compile/1.0/compile-1.0.jar
│  (Maven cache)           │  includes Cli_entry.class, Cli_main.class, tools/Cli.class
└────────────┬────────────┘
             │ 2. kestrel-self bootstrap
             │    extracts JAR into self-hosted cache
             ▼
┌─────────────────────────┐
│  Self-Hosted Classes     │  ~/.kestrel/self/
│  (Cli_entry, Cli_main,   │
│   tools/Cli, etc.)       │
└────────────┬────────────┘
             │ 3. Normal commands (via ./kestrel-self)
             │    shim execs java ... <resolved tools.Cli> ...
             ▼
┌─────────────────────────┐
│  User Programs           │  run, build <script>, test, dis, fmt, doc, lock, status
│  (driven by Kestrel CLI) │
└─────────────────────────┘
```

### 1.2 Self-Hosted Compiler Entry Points

- **`stdlib/kestrel/tools/compiler/cli-entry.ks`**: Executable entry point compiled to `Cli_entry.class`. Imports and invokes `main()` from `cli-main.ks`.
- **`stdlib/kestrel/tools/compiler/cli-main.ks`**: Command dispatcher. Parses CLI commands (`run`, `build`, `dis`, `test`, `fmt`, `doc`, `lock`) and either handles them directly (e.g. `build` calls `Driver.compileFile()` without forwarding to the shell wrapper) or delegates non-build commands to the shell wrapper (`./kestrel`) for commands that need full CLI orchestration.
- **`stdlib/kestrel/tools/cli.ks`**: Self-hosted CLI shim target compiled to `kestrel/tools/Cli.class`. After bootstrap, `scripts/kestrel` delegates normal commands to this class via `exec java`.

### 1.3 Clean-Machine Install Flow

The supported clean-machine path is:

1. `./scripts/build-bootstrap-jar.sh`
2. `./kestrel-self bootstrap`
3. `./kestrel status`

Expected outcome:

- Maven cache contains bootstrap/runtime jars under `~/.kestrel/maven/lang/kestrel/...`.
- Self-hosted cache (`~/.kestrel/self/`) contains extracted self-hosted classes including `kestrel/tools/Cli.class`.
- `kestrel status` reports both cache presence.

### 1.4 Developer Re-Compile Flow

- Rebuild seed toolchain and runtime JAR: `./kestrel build` (no script argument).
- Rebuild CLI class only: `./kestrel build stdlib/kestrel/tools/cli.ks`.

The first command updates TypeScript compiler output and runtime artifacts; the second refreshes `kestrel/tools/Cli.class` in the JVM cache without requiring a full re-bootstrap.

---

## 2. Directory Layout

### 2.1 JVM Class Caches

Two separate cache directories exist under `~/.kestrel/`:

- **TypeScript compiler cache:** `~/.kestrel/ts/` by default. Override with `KESTREL_TS_CACHE`.
  Contains `.class` files compiled by the TypeScript bootstrap compiler for user programs.
  `KESTREL_JVM_CACHE` is a deprecated alias for `KESTREL_TS_CACHE` (one-release window).
- **Self-hosted compiler cache:** `~/.kestrel/self/` by default. Override with `KESTREL_SELF_CACHE`.
  Contains self-hosted compiler classes (seeded by `./kestrel-self bootstrap`) plus `.class`
  files compiled by the self-hosted compiler for user programs run via `./kestrel-self`.

**Contents of each cache:** Compiled `.class` files, `.class.deps` dependency lists, and `.kti` incremental metadata.
- **`.class.deps` format:** For each compiled module `<ClassName>`, a sidecar file `<ClassName>.class.deps` is written to `outDir`. The file contains the absolute source paths of all transitive source dependencies of that module (in DFS post-order), with the module's own path last. One absolute path per line, UTF-8 encoded, newline-terminated. Only written when a module is actually compiled (not when a fresh/incremental skip occurs).
- **Gate artifact for self-hosted cache:** `Cli_entry.class` (nested under a path derived from the source file's absolute path).

### 2.2 Maven Cache

- **Path:** `~/.kestrel/maven/` by default.
- **Override:** `KESTREL_MAVEN_CACHE` environment variable.
- **Bootstrap JAR location:** `~/.kestrel/maven/lang/kestrel/compile/1.0/compile-1.0.jar`
- **SHA1 sidecar:** `compile-1.0.jar.sha1` alongside the JAR.

### 2.3 URL Import Cache

- **Path:** `~/.kestrel/cache/` by default.
- **Override:** `KESTREL_CACHE` environment variable.
- See [09-tools.md §2.9](09-tools.md) for full URL cache specification.

### 2.4 Clean Slate

`rm -rf ~/.kestrel` removes all compiled classes, bootstrap artifacts, Maven cache, and URL cache. After a clean wipe, `kestrel run/build/test/dis` will fail until bootstrap is restored.

---

## 3. Bootstrap Flow

### 3.1 Build Bootstrap JAR

**Script:** `./scripts/build-bootstrap-jar.sh`

**Purpose:** Produce a canonical bootstrap compiler JAR from the TypeScript compiler output and install it to the Maven cache.

**Steps:**
1. Wipe `~/.kestrel` (clean slate for reproducibility).
2. Build the TypeScript compiler (`cd compiler && npm run build`).
3. Compile `stdlib/kestrel/tools/compiler/cli-entry.ks` using the TypeScript compiler:
   ```
   node compiler/dist/cli.js cli-entry.ks --target jvm -o <classes-dir>
   ```
4. Compile `stdlib/kestrel/tools/cli.ks` into the same classes directory.
5. Package all `.class` files into a JAR (`compiler-bootstrap.jar`).
6. Verify `Cli_entry.class`, `Cli_main.class`, and `tools/Cli.class` are present in the JAR.
7. Install the JAR to the Maven cache at `~/.kestrel/maven/lang/kestrel/compile/1.0/compile-1.0.jar`.
8. Compute and write a SHA1 sidecar (`compile-1.0.jar.sha1`).
9. Delete the intermediate `~/.kestrel/bootstrap/` working directory.

**Prerequisites:** `node`, `java`, `javac`, `jar` on `PATH`.

**Artifacts:** Bootstrap JAR and SHA1 sidecar in the Maven cache layout. No intermediate files remain.

**Policy:** The bootstrap JAR is a build-time-only artifact. It is not used by normal `kestrel run/build/test` command execution.

### 3.2 Bootstrap Command

**Usage:** `kestrel-self bootstrap`

**Purpose:** Seed self-hosted compiler classes into the self-hosted cache (`~/.kestrel/self/`) from the bootstrap JAR. The JAR contains the Kestrel compiler already compiled to JVM bytecode (produced by `build-bootstrap-jar.sh` using the TypeScript compiler). The bootstrap command itself does not invoke the TypeScript compiler.

**Steps:**
1. Validate runtime JAR exists in Maven cache at `~/.kestrel/maven/lang/kestrel/runtime/1.0/runtime-1.0.jar`.
2. Validate bootstrap compiler JAR exists in Maven cache at `~/.kestrel/maven/lang/kestrel/compile/1.0/compile-1.0.jar`.
3. Extract and install self-hosted compiler classes from the bootstrap JAR into the self-hosted cache.
4. Verify `Cli_entry.class` and `Cli_main.class` are present in the self-hosted cache.

**Output directory:** `~/.kestrel/self/` by default; override with `KESTREL_SELF_CACHE`.

**Deprecation:** `kestrel bootstrap` (i.e. the `./kestrel` shim, without the `-self` suffix) is a one-release deprecation shim: it prints a notice to stderr and forwards to `kestrel-self bootstrap`.

**Failure diagnostics:** Emits explicit errors for missing runtime JAR, missing bootstrap JAR, and installation failure.

**Idempotence:** Repeated invocations refresh self-hosted class files in place.

### 3.3 Status Command

**Usage:** `kestrel status`

**Purpose:** Report the presence/absence of both JVM class caches.

**Output format:**
```
TS compiler cache:          ~/.kestrel/ts   (ready|missing)
Self-hosted compiler cache: ~/.kestrel/self (ready|missing)
```

`ready` means the Cli.class for the TS cache (or `Cli_entry.class` for the self-hosted cache) is present. `missing` means it is absent.

### 3.4 `scripts/test-kestrel.sh` — Self-Hosted Compiler Test Runner

**Usage:** `./scripts/test-kestrel.sh`

**Purpose:** Run the Kestrel-compiler-specific test corpora via the self-hosted compiler toolchain.

**Tiers (in order):**

| Tier | Directory | Runner | What it checks |
|------|-----------|--------|----------------|
| parse | `tests/kconformance/parse/` | `./kestrel-self build <file>` | Compiles without error (exit 0) |
| typecheck | `tests/kconformance/typecheck/` | `./kestrel-self build <file>` | Compiles without error (exit 0) |
| runtime | `tests/kconformance/runtime/valid/` | `./kestrel run <file>` *(see note)* | Exit 0; stdout matches `// =>` goldens |
| unit | `tests/kunit/*.test.ks` | `./kestrel-self test <file>` | kestrel:dev/test suite (inactive until S17-36+) |

**Runtime tier note:** Until the self-hosted compiler's code generation for top-level programs is
complete (S17-36/S17-37/S17-38), the runtime tier runs via `./kestrel` (TypeScript compiler
path). Once self-hosted codegen is functional, it will switch to `./kestrel-self`.

**Runtime golden format:** In-file `// =>` comments mark expected stdout lines:
```
println(42)
// => 42
```
A file with no `// =>` comments asserts exit 0 only.

**Output:** Per-tier counts (`parse N, typecheck M, runtime K`) followed by a total. Exits non-zero on any failure.

**Bootstrap guard:** If `~/.kestrel/self/` lacks `Cli.class`, the script automatically runs `./kestrel-self bootstrap` before proceeding.

### Baseline population status (S17-50, 2026-04-28)

The initial baseline sweep from TS corpora to Kestrel corpora established:

- parse: 12 files
- typecheck: 37 files
- runtime: 0 files
- unit: 0 files

Notes:

- All promoted corpus files carry a one-line provenance header (`// Provenance: ...`).
- Runtime remains empty at this baseline floor; `scripts/test-kestrel.sh` still exercises the
   tier and reports `runtime: 0 files` until codegen-gap stories promote runtime-valid cases.
- Unit remains empty while self-hosted `kestrel:dev/test` execution is incomplete for `tests/unit/*`.

---

## 4. Self-Hosted Mode Gating

### 4.1 Gate Check

Before executing normal commands, `scripts/kestrel` resolves `kestrel/tools/Cli.class` under the JVM cache and exits non-zero if it cannot be found.

Once delegated, command-specific self-hosted checks (for example `Cli_entry.class` presence for status reporting and bootstrap diagnostics) are handled by Kestrel CLI code.

**Failure message:**
```
kestrel: self-hosted compiler artifacts are required for this command
   run: ./scripts/build-bootstrap-jar.sh && ./kestrel bootstrap
```

### 4.2 Commands Subject to the Gate

| Command | Gated? | Notes |
|---------|--------|-------|
| `run <script>` | Yes | Delegated to `kestrel/tools/Cli.class` |
| `build <script>` | Yes | `build` with no arguments (rebuild compiler/runtime) is not gated |
| `test` | Yes | Delegated to Kestrel CLI |
| `dis <script>` | Yes | Delegated to Kestrel CLI |
| `bootstrap` | No | Creates the gated artifacts |
| `status` | Yes | Delegated to Kestrel CLI class |
| `build` (no args) | No | Rebuilds TypeScript compiler and JVM runtime |
| `fmt` | Yes | Delegated to Kestrel CLI |
| `doc` | Yes | Delegated to Kestrel CLI |

### 4.3 Compilation Path

After passing shim-level gating, script compilation is orchestrated by the Kestrel CLI (`stdlib/kestrel/tools/cli.ks`) in self-hosted mode.

The self-hosted compiler classes (`Cli_main`) are installed and gate command availability. They are also exercised directly by bootstrap-parity tooling (for example `scripts/test-compiler-bootstrap`) via:
`java -cp <runtime>:<classes> Cli_main <command> <args>`.

### 4.4 Self-Hosted Typechecker Coverage

The self-hosted typechecker (`stdlib/kestrel/dev/typecheck/typecheck.ks`) handles all top-level declaration forms required to typecheck the Kestrel stdlib and compiler from source:

| Declaration form | Supported | Notes |
|-----------------|-----------|-------|
| `fun` / `export fun` | Yes | Full inference + generalization |
| `val` / `export val` | Yes | Full inference |
| `var` / `export var` | Yes | Full inference |
| `extern fun` / `export extern fun` | Yes | Signature-only registration; no body inference required. Exported extern funs appear in `TypecheckResult.exports` and are emitted to `.kti` files. |
| `extern type` / `export extern type` | Yes | Nominal type registration; no constructors. Exported/opaque extern types appear in `TypecheckResult.exportedTypeVisibility` and `exportedTypeAliases`, and are serialised to `.kti` files. |
| `type` / `export type` | Yes | ADT and alias registration |
| `exception` / `export exception` | Yes | Constructor registration |

Declarations not yet handled emit a diagnostic `"Unsupported top-level declaration in self-hosted checker MVP"` and are skipped without aborting the run.

---

## 5. Bootstrap Verification

### 5.1 4-Stage Parity Test

**Script:** `./scripts/test-compiler-bootstrap [kestrel-test-args...]`

**Purpose:** Verify that the self-hosted compiler can compile itself and produce functionally identical output across generations.

**Stages:**
1. **Stage 0 (TypeScript → classes):** The TypeScript compiler compiles `cli-entry.ks` into `stage0-ts/`.
2. **Path 1 (stage0 self-compiles):** The stage-0 self-hosted compiler compiles `cli-entry.ks` into `path1/`.
3. **Path 2 (path1 self-compiles):** The path-1 compiler compiles `cli-entry.ks` into `path2/`.
4. **Test (path2 runs tests):** The path-2 compiler runs the full Kestrel unit test suite.

**Working directory:** `.kestrel/compiler-bootstrap-test/` within the project root.

**Success criteria:** All 4 stages complete without error and unit tests pass. This proves the self-hosted compiler is a fixed point: compiling itself produces a compiler that behaves identically.

**Self-hosted invocation:** Stages 2 and 3 invoke the self-hosted compiler via:
```
KESTREL_JVM_CACHE=<output-dir> java -cp <runtime>:<classes> Cli_main build cli-entry.ks
```

---

## 6. CI Integration

The CI pipeline (`ci.yml`) enforces the bootstrap flow:

1. **Build TypeScript compiler** — `cd compiler && npm ci && npm run build`
2. **Run compiler unit tests** — `npm test`
3. **Build JVM runtime** — `cd runtime/jvm && ./build.sh`
4. **Bootstrap self-hosted compiler:**
   ```bash
   ./scripts/build-bootstrap-jar.sh
   ./kestrel bootstrap
   ./kestrel status  # asserts self-hosted mode
   ```
5. **E2E scenarios** — `./scripts/run-e2e.sh`
6. **Kestrel unit tests** — `./kestrel test`
7. **Bootstrap chain verification** — `./scripts/test-compiler-bootstrap --summary`
8. **Bootstrap handoff gate:**
   - Rebuild bootstrap JAR (clean-slate rebuild)
   - Re-bootstrap
   - Assert `compiler mode: self-hosted` from `kestrel status`
   - Verify `kestrel build`, `kestrel run`, and `kestrel test` work end-to-end

---

## 7. Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `KESTREL_JVM_CACHE` | `~/.kestrel/jvm` | JVM class cache root (compiled classes for all scripts and the self-hosted compiler) |
| `KESTREL_MAVEN_CACHE` | `~/.kestrel/maven` | Maven artifact cache root (bootstrap JAR installed here) |
| `KESTREL_BOOTSTRAP_ROOT` | `~/.kestrel/bootstrap` | Working directory for `build-bootstrap-jar.sh` (intermediate; deleted after JAR install) |
| `KESTREL_CACHE` | `~/.kestrel/cache` | URL import cache root |
| `KESTREL_CLI_TS_FALLBACK` | _(unset)_ | When set to `1`, bypasses the self-hosted artifact gate (`require_selfhost_compiler`). Used by `test-compiler-bootstrap` to allow isolated bootstrap chain verification with empty JVM cache directories. Not intended for normal use. |

---

## 8. Relation to Other Specs

- [01-language.md](01-language.md) – Source language compiled during bootstrap
- [06-typesystem.md](06-typesystem.md) – Type system; mentions self-hosting interoperability for compiler types
- [09-tools.md](09-tools.md) – CLI commands that depend on bootstrap state
- [10-compile-diagnostics.md](10-compile-diagnostics.md) – Diagnostic format used during bootstrap compilation
