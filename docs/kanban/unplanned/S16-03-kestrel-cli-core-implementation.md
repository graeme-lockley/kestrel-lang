# `kestrel:tools/cli` — core CLI implementation in Kestrel

## Sequence: S16-03
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E16 Kestrel CLI in Kestrel](../epics/unplanned/E16-kestrel-cli-in-kestrel.md)
- Companion stories: S16-01, S16-02, S16-04, S16-05

## Summary

Write `stdlib/kestrel/tools/cli.ks` (~350 lines) implementing all user-facing Kestrel CLI commands:
`run`, `dis`, `build <script>`, `status`, `test`, `fmt`, `doc`, `lock`, and the internal
`__ts-compile` gate. The entrypoint class (`kestrel.tools.Cli`) becomes the target of the trimmed
Bash shim in S16-04. This story ports every logical function from `scripts/kestrel` that is not
inherently Bash-only (ROOT resolution, no-arg `build`, `bootstrap`) into idiomatic Kestrel, relying
on S16-01 for in-process execution and S16-02 for Maven classpath resolution.

## Current State

`scripts/kestrel` holds ~640 lines of Bash implementing all commands. The existing
`stdlib/kestrel/tools/compiler/cli-main.ks` dispatches compiler commands but delegates
orchestration back to the Bash shim via `runProcessStream("./kestrel", …)`, creating a recursive
loop between them. After this story, `kestrel:tools/cli` is the terminal dispatcher — it invokes
the compiler driver directly (for `build <script>`) and runs user programs in-process (for `run`).

Key Bash logic to port:
- `needs_compile_jvm`: read `$class.deps` file, compare `Fs.stat().mtimeMs` of deps vs class file.
- `main_class_for`: derive Java class name from absolute `.ks` path (same algorithm as `resolve-maven-classpath.mjs`).
- `jvm_class_dir_for`: return `$KESTREL_JVM_CACHE` (from env).
- `compile_with_active_compiler`: invoke the self-hosted compiler driver via `kestrel:tools/compiler/driver`.
- `cmd_run`: compile-if-needed, build classpath (runtime JAR + class dir + maven jars), run in-process.
- `cmd_dis`: compile-if-needed, spawn `javap` subprocess.
- `cmd_build <script>`: compile-if-needed, print "Built …".
- `cmd_status`: check for `Cli_entry.class` in JVM cache.
- `cmd_test`, `cmd_fmt`, `cmd_doc`, `cmd_lock`: forward to existing `kestrel:tools/*` modules.
- `cmd_ts_compile`: call `node $COMPILER_CLI $entry --target jvm -o $out_dir [flags]` (gated).

Environment variables consumed (set by Bash shim):
- `KESTREL_ROOT` — repository root (replaces the shell's `$ROOT`).
- `KESTREL_JVM_CACHE` — JVM class cache root (default `~/.kestrel/jvm`).
- `KESTREL_MAVEN_CACHE` — Maven cache root (default `~/.kestrel/maven`).

## Relationship to other stories

- **Depends on S16-01** (`runInProcess`): used by `cmd_run`.
- **Depends on S16-02** (Maven classpath resolver): used by `cmd_run` and `cmd_dis`.
- **Prerequisite for S16-04** (Bash shim reduction): S16-04 wires the shim to the CLI class
  produced here.
- **Prerequisite for S16-05** (Bootstrap pipeline): `build-bootstrap-jar.sh` must compile this
  module to include it in the JAR.

## Goals

1. `stdlib/kestrel/tools/cli.ks` is created, callable as the main class `kestrel.tools.Cli` once
   compiled.
2. The module dispatches on the first argument:
   - `run [flags] <script|kestrel:spec> [args…]` — compile-if-needed, then `runInProcess`.
   - `dis [flags] <script>` — compile-if-needed, spawn `javap` via `runProcessStream`.
   - `build <script> [flags]` — compile via compiler driver, print "Built …".
   - `status` — report `self-hosted` or `bootstrap-required`.
   - `test [flags…]` — invoke `kestrel:tools/test` via `runInProcess`.
   - `fmt [flags…]` — invoke `kestrel:tools/format` via `runInProcess`.
   - `doc [flags…]` — invoke `kestrel:tools/doc` via `runInProcess`.
   - `lock <lockfile>` — stub (no-op with message).
   - `__ts-compile <entry> <outDir> [flags…]` — gated; invokes `node $COMPILER_CLI`.
   - Any unrecognised command → usage message + exit 1.
3. Incremental staleness check (`needsCompile`) uses `Fs.stat().mtimeMs` to compare the entry
   `.class` file against each dependency listed in the `.class.deps` file, replicating
   `needs_compile_jvm` exactly.
4. The `classNameFor(path: String): String` helper implements the same sanitisation and
   capitalisation algorithm as the Bash `main_class_for` and `resolve-maven-classpath.mjs`.
5. `kestrel: module specifiers` for `run` are resolved to `$KESTREL_ROOT/stdlib/kestrel/<path>.ks`.
6. Module-level unit tests (`stdlib/kestrel/tools/cli.test.ks`) cover: `classNameFor` on typical
   paths, `needsCompile` logic with mocked timestamps.

## Acceptance Criteria

- `kestrel run hello.ks` (after bootstrap) works end-to-end, delegating through the new Kestrel CLI.
- `kestrel build hello.ks`, `kestrel dis hello.ks`, `kestrel status`, `kestrel test --summary` all
  work through the new Kestrel CLI path.
- Unit tests for `classNameFor` and `needsCompile` pass.
- All E2E tests in `tests/e2e/scenarios/` pass when the Kestrel CLI is wired up.

## Spec References

- `docs/specs/09-tools.md` — all command definitions.
- `docs/specs/11-bootstrap.md` §1.2 — CLI entry-point contract.

## Risks / Notes

- **`compile_with_active_compiler` loop**: currently `cli-main.ks` calls `runProcessStream` back
  into the Bash script for most commands. After this story, `cli.ks` invokes the compiler driver
  (`kestrel:tools/compiler/driver`) directly, breaking the loop. Confirm that the compiler driver
  does not itself invoke `/kestrel run` anywhere.
- **`--exit-wait` / `--exit-no-wait`**: these flags previously affected a JVM flag
  (`-Dkestrel.exitWait=false`). With in-process execution the CLI must set the system property
  *before* loading the user class. Document the mechanism clearly.
- **`javap` path for `dis`**: `javap` is not available on all systems; the existing guard
  (`command -v javap`) should be replicated before spawning.
- **`KESTREL_ROOT` must be set**: the Kestrel CLI cannot resolve its own location; it must error
  clearly if `KESTREL_ROOT` is absent rather than silently using an empty string.
