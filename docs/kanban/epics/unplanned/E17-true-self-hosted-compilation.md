# Epic E17: True Self-Hosted Compilation

## Status

Unplanned

## Summary

Today `kestrel status` reports "self-hosted" and the CLI is written in Kestrel, yet every actual
compilation of a `.ks` file still shells out to `node compiler/dist/cli.js` (the TypeScript
bootstrap compiler). The Node runtime is therefore a hidden runtime dependency even after
bootstrap.

This epic wires all the already-implemented Kestrel compiler pieces into a real
`Driver.compileFile` implementation and then switches `cli.ks` to call that driver in-process
instead of spawning Node. When the epic is complete, every Kestrel program can be compiled and run
using only the JVM — Node is no longer a runtime dependency.

The individual pieces already exist in Kestrel:
- Front-end: `kestrel:dev/parser/lexer`, `kestrel:dev/parser/parser`
- Type checker: `kestrel:dev/typecheck/typecheck`
- Code generator: `kestrel:tools/compiler/codegen` (`jvmCodegen`)
- Class file serialiser: `kestrel:tools/compiler/classfile` (`cfToBytes`)
- KTI reader/writer: `kestrel:tools/compiler/kti`
- Module resolver: `kestrel:tools/compiler/resolve`

What is missing is the **driver** that orchestrates these pieces together into an incremental,
multi-module, caching compilation pipeline, and the **wiring** in `cli.ks` that calls it instead
of Node. The TypeScript reference implementation is `compiler/src/compile-file-jvm.ts`.

Stories must be **fine-grained** — each one adds exactly one pipeline capability and is
independently testable. No story should touch more than one concern at a time.

## Stories (ordered — implement sequentially)

1. [S17-01] Single-file happy-path compilation in driver
   — Read source, lex, parse, typecheck (no imports), `jvmCodegen`, write `.class` file(s) to
   `outDir`. No KTI, no incremental, no deps. `compileFile` returns `ok=True` for valid source.

2. [S17-02] Diagnostic propagation through `CompileResult`
   — Surface parse errors and typecheck `Diagnostic` list through `CompileResult.diagnostics`
   and render them to stderr in the same format as the TS compiler. `compileFile` returns
   `ok=False` with populated diagnostics for invalid source.

3. [S17-03] Source hashing and KTI write after successful compile
   — Compute SHA-256 source hash, call `Kti.buildKtiV4`, call `Kti.writeKtiFile` to persist
   the `.kti` cache file alongside `.class` output. No freshness check yet — always rewrite.

4. [S17-04] Single-file freshness check (skip recompile if fresh)
   — Before compiling a single file with no deps, attempt to read its `.kti` file; if
   `Driver.isFresh` returns `True` (source hash and dep hashes match), skip recompile entirely
   and return `ok=True`. Write unit tests verifying the skip path and the recompile path.

5. [S17-05] Direct dependency path resolution from a single source file
   — Call `Resolve.uniqueDependencyPaths` on the parsed program to obtain the flat list of
   `ResolvedDep` values for direct imports. No multi-module compile yet; just prove the paths
   are correctly resolved for stdlib and relative specifiers.

6. [S17-06] Cross-module KTI type loading for the typechecker
   — Before typechecking a module, read the `.kti` files of each resolved direct dependency
   and reconstruct the `importBindings` snapshot that the typechecker needs. Handle the case
   where a dependency `.kti` is absent (dependency must be compiled first; return an error).

7. [S17-07] Topological dependency ordering and cycle detection
   — Build a full import graph (recursively from the entry file), topologically sort it, detect
   circular imports, and compile each module in dependency order. Each module is compiled
   once per invocation (deduplicated by absolute path).

8. [S17-08] Multi-module incremental compilation (graph-wide freshness)
   — Apply the single-file freshness check (S17-04) across the full dependency graph. Only
   recompile modules whose source has changed or whose dependencies have changed. Dep hashes
   are SHA-256 hashes of direct dependency `.kti` contents, matching the TS compiler's scheme.

9. [S17-09] URL dependency fetch integration
   — For `https://` (and optionally `http://` with `--allow-http`) specifiers, call
   `Resolve.fetchUrl` to populate the URL cache before attempting to resolve the path. Wire
   `--refresh` flag to force re-fetch. Verify cached-hit path skips the network.

10. [S17-10] `.class.deps` sidecar file writing
    — After compiling a module, write `<ClassName>.class.deps` listing the absolute paths of
    all direct and transitive source dependencies. This file is used by `cli.ks` for mtime-
    based staleness checks (legacy freshness path). Format: one absolute path per line.

11. [S17-11] Maven `.kdeps` sidecar handling
    — Detect `maven:` specifiers in source, write `<ClassName>.kdeps` sidecar alongside
    `.class` output (group:artifact:version, one per line). Driver does not download JARs;
    it records coordinates. `cli.ks` (and `kestrel:tools/cli/maven`) reads these sidecars
    to build the JVM classpath.

12. [S17-12] Wire `cli.ks` `compileScript` to call the Kestrel driver in-process
    — Replace the `runProcessStream("node", [compilerCli, ...])` call in `cli.ks` with a
    direct in-process call to `Driver.compileFile`. Remove the `compilerCli` parameter from
    `compileScript` and all call sites. The Node path must no longer be reachable for normal
    compilation. `cli-main.ks` build scaffold is superseded by this wiring.

13. [S17-13] End-to-end validation without Node; CI gate and spec update
    — Rename `compiler/` to verify the full test suite (1855+ tests) passes with Node
    unreachable. Add a CI step that runs `mv compiler compiler_DISABLED && ./kestrel test`
    and must exit 0. Restore `compiler/`. Update `docs/specs/11-bootstrap.md` and
    `docs/specs/12-agent-enablement-and-knowledge.md` to reflect the JVM-only runtime path.
    Update README "What you need" — Node becomes a maintainer-only build dependency.

## Dependencies

- **E14** (Self-Hosting Compiler, done) — provides all individual compiler pieces:
  parser, typechecker, codegen, classfile writer, KTI, resolver.
- **E15** (Bootstrap JAR Self-Hosting Handoff, done) — establishes the bootstrap flow and
  `~/.kestrel/jvm` cache layout that `compileFile` must write into.
- **E16** (Kestrel CLI in Kestrel, in epics/unplanned with all stories ticked) — provides
  `stdlib/kestrel/tools/cli.ks`; S17-12 modifies `compileScript` directly in that file.
- **E12** (Full Process Environment, done) — `getEnv`, `mkdirAll`, `readText`, `writeBytes`
  are all required by the driver.
- **Spec 12** (Agent Enablement, docs/specs/12-agent-enablement-and-knowledge.md) — Phase 3
  (minimal dependency installer) is blocked on this epic; completing E17 unblocks it.

## Implementation Approach

The implementation follows the TypeScript reference in `compiler/src/compile-file-jvm.ts`
exactly, but expressed in Kestrel and using the already-ported Kestrel stdlib modules. No new
language features or stdlib primitives are required.

Each story corresponds to one vertical slice of `compile-file-jvm.ts`:
- S17-01–S17-04 cover the single-file path (lines ~40–120 of the TS reference).
- S17-05–S17-08 cover the multi-module graph path (the outer loop in `compileJvmMultiModule`).
- S17-09 covers URL fetch (the `fetchUrlDeps` helper).
- S17-10–S17-11 cover sidecar emission.
- S17-12 covers the CLI wiring (the call site in `cli.ks`).
- S17-13 is the validation gate.

**Key implementation invariants to preserve (match TS compiler exactly):**
- Source hash: SHA-256 of raw source bytes, hex-encoded.
- Dep hashes: SHA-256 of each direct dependency's `.kti` file bytes.
- `isFresh` check: `kti.sourceHash == srcHash && kti.depHashes == depHashes`.
- Output path derivation: same scheme as `cli.ks` `classOutputPath` (strip leading `/`,
  replace `.ks` with `.class`, mirror under `jvmCache`).
- `.class.deps` format: one absolute source path per line, no trailing newline.

## Epic Completion Criteria

- `Driver.compileFile` correctly compiles any Kestrel source file (with transitive imports,
  URL deps, Maven deps, and incremental freshness checks) to `.class` output in the JVM cache.
- `cli.ks` `compileScript` calls `Driver.compileFile` in-process; no `node` subprocess is
  spawned during compilation.
- All existing Kestrel tests pass without `compiler/dist/cli.js` present:
  `mv compiler compiler_DISABLED && ./kestrel test` exits 0.
- Node is documented as a maintainer-only build dependency; the README "What you need" section
  lists only Java for normal use.
- `docs/specs/11-bootstrap.md` is updated to reflect that runtime compilation uses the
  self-hosted Kestrel driver.
- `docs/specs/12-agent-enablement-and-knowledge.md` Phase 3 prerequisite is unblocked.
- CI includes a no-Node compilation gate that fails if Node is implicitly required at runtime.
