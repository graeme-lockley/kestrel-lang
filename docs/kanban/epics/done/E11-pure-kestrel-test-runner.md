# Epic E11: Pure-Kestrel Test Runner

## Status

Done

## Summary

The `kestrel test` command is currently implemented as a mixed bash/Kestrel system: a substantial bash function (`_run_unit_tests`) compiles `kestrel:tools/test-runner` with hand-separated compiler flags, then launches it via a raw `java -cp ... MainClass "" "" "$ROOT" args...` invocation that embeds a positional-argument convention for the project root. This contrasts with `kestrel fmt`, which was fully migrated to Kestrel in E08: `cmd_fmt` is three lines (`ensure_tools`, build-check, `exec kestrel run format.ks "$@"`) and `format.ks` handles everything in-process using `kestrel:dev/cli`.

This epic closes that gap by filling two stdlib holes and rewriting `test-runner.ks` as a proper `kestrel:dev/cli` entry point, so that `cmd_test` in `scripts/kestrel` can become an identical three-line alias.

## Stories

1. ✅ [S11-01 — `getEnv` in `kestrel:sys/process`: expose environment variables to Kestrel programs](../../done/S11-01-getenv-in-sys-process.md)
2. ✅ [S11-02 — `kestrel:io/fs` file management: `fileExists`, `deleteFile`, `renameFile`](../../done/S11-02-io-fs-file-management.md)
3. ✅ [S11-03 — Rewrite `kestrel:tools/test-runner` as a `kestrel:dev/cli` entry point](../../done/S11-03-rewrite-test-runner.md)
4. ✅ [S11-04 — Simplify bash `cmd_test` to match `cmd_fmt`](../../done/S11-04-simplify-cmd-test.md)

## Dependencies

- E08 (Source Formatter) — `kestrel:dev/cli` must be in place (it is; E08 is done).
- E08 — The `./kestrel run kestrel:module/specifier` form must work (it does; E08 S08-02 is done).

## Epic Completion Criteria

- The end-to-end wall-clock time of `kestrel test` (measured from CLI entry to process exit on a warm cache, full test suite) is no slower than the equivalent bash-driven invocation. Benchmark both before and after S11-04 and record results in the story's Build notes.
- `cmd_test` in `scripts/kestrel` is structurally identical to `cmd_fmt`: three lines — `ensure_tools`, a compiler-built check, and `exec "$ROOT/kestrel" run "kestrel:tools/test" "$@"`.
- `_run_unit_tests` is deleted from `scripts/kestrel`.
- `kestrel:tools/test` accepts `--verbose`, `--summary`, `--clean`, `--refresh`, `--allow-http` via `kestrel:dev/cli`; these flags are forwarded correctly to the inner `kestrel run` subprocess for the generated runner.
- `kestrel:sys/process` exports `getEnv(String) -> Option<String>` backed by `KRuntime`; `getProcess().env` returns the actual process environment.
- `kestrel:io/fs` exports `fileExists`, `deleteFile`, and `renameFile`; `kestrel:tools/test/runner` uses `renameFile` instead of the `sh -c "cmp -s ... && rm ... || mv ..."` subprocess trick.
- All existing `./kestrel test` behaviours are preserved: default discovery (`tests/unit/` + `stdlib/kestrel/` up to 3 levels), explicit file/directory arguments, `--verbose` / `--summary` / `--generate` output modes, `--clean` cache invalidation.
- All test suites pass: `cd compiler && npm test`, `./kestrel test`.

## Implementation Approach

### Why `kestrel test` is harder than `kestrel fmt`

`kestrel fmt` operates entirely in-process: it reads files, formats them, and writes results without spawning any subprocess. `kestrel test` has a fundamental **two-stage compilation** problem:

1. Stage 1 — `test-runner.ks` discovers test files and generates `.kestrel_test_runner.ks`.
2. Stage 2 — compile and execute that generated Kestrel file.

Stage 2 requires the Kestrel compiler and JVM runtime. Currently stage 2 is handled by spawning `./scripts/kestrel run .kestrel_test_runner.ks` from within `test-runner.ks`. The `fmt` model cannot eliminate this subprocess, but it can **normalise** the launch: instead of bash doing the compilation, `./kestrel run` handles it, and `test-runner.ks` spawns the inner subprocess itself via `kestrel:sys/process.runProcessStream`.

### What is missing from stdlib today

| Gap | Where used today | Proposed fix |
|-----|-----------------|--------------|
| `getEnv(String) -> Option<String>` | Kestrel code cannot read env vars; `getProcess().env` always returns `[]` | Add `extern fun getEnv(String): Option<String>` backed by `KRuntime.getEnv(String)`; fix `getProcess()` implementation |
| `renameFile(String, String) -> Task<Result<Unit, FsError>>` | `test-runner.ks` uses `runProcess("sh", ["-c", "cmp -s ... && rm ... \|\| mv ..."])` for atomic replace | Add to `kestrel:io/fs` backed by `Files.move(..., ATOMIC_MOVE)` |
| `deleteFile(String) -> Task<Result<Unit, FsError>>` | Not needed directly yet, but paired with `renameFile` for completeness | Add to `kestrel:io/fs` backed by `Files.deleteIfExists` |
| `fileExists(String) -> Task<Bool>` | Not needed directly yet, but useful for skip-if-unchanged guard | Add to `kestrel:io/fs` backed by `Files.exists` |

### Kestrel executable path discovery

`test-runner.ks` currently hardcodes `"./scripts/kestrel"`. With this epic:

- The bash wrapper sets `KESTREL_BIN="$ROOT/kestrel"` before `exec`.
- `test-runner.ks` reads `getEnv("KESTREL_BIN")` and falls back to `"${proc.cwd}/kestrel"`.
- This removes the `./scripts/kestrel` hardcode and works correctly when invoked from any directory.

### Project root discovery

Currently, bash passes `"" "" "$ROOT"` as the first three JVM args so `kestrel:tools/test` can read `args[2]` as the project root. With the new launch convention (`./kestrel run kestrel:tools/test "$@"`), `getArgs()` returns only the user-supplied arguments. `kestrel:tools/test` switches to `getProcess().cwd` as the project root (correct when `kestrel test` is run from the project root, which is the documented convention).

### Compiler-flag forwarding

`--clean`, `--refresh`, and `--allow-http` are *compiler* flags consumed by `./kestrel run` when compiling `kestrel:tools/test`. They must also be forwarded to the inner `./kestrel run .kestrel_test_runner.ks` call so that the generated runner and the test files it imports are compiled with the same settings. `kestrel:tools/test` reads these flags from `proc.args` via `kestrel:dev/cli` and appends them to the inner subprocess command.

### After this epic

`scripts/kestrel` `cmd_test` will be:

```bash
cmd_test() {
  ensure_tools
  if compiler_build_needed; then
    build_compiler_jvm
  fi
  KESTREL_BIN="$ROOT/kestrel" exec "$ROOT/kestrel" run "kestrel:tools/test" "$@"
}
```
