# kestrel run: module-specifier support

## Sequence: S08-02
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/unplanned/E08-source-formatter.md)
- Companion stories: S08-01, S08-03, S08-04, S08-05, S08-06, S08-07

## Summary

`kestrel run` currently accepts only file paths (e.g. `./kestrel run hello.ks`). This story extends the `run` sub-command to also accept stdlib module specifiers (e.g. `./kestrel run kestrel:tools/test`), resolving them to the physical stdlib file before compilation and execution. This lets tools in `kestrel:tools/*` be invoked directly without requiring a wrapper `.ks` file.

This is a pure bash-script change to `scripts/kestrel`; no TypeScript or Java changes are required.

## Current State

`cmd_run()` in `scripts/kestrel` calls `resolve_script "$1"` which checks only whether the argument is a file path or can have `.ks` appended. If the argument starts with `kestrel:`, `resolve_script` returns an empty string and the command exits with "script not found".

```bash
resolve_script() {
  local arg="$1"
  if [ -f "$arg" ]; then echo "$arg"; return; fi
  if [[ "$arg" == *.ks ]]; then echo ""; return; fi
  if [ -f "${arg}.ks" ]; then echo "${arg}.ks"; return; fi
  echo ""
}
```

## Relationship to other stories

- **Required by** S08-06 (kestrel:tools/test) and S08-07 (kestrel:tools/format) to allow `./kestrel run kestrel:tools/test` and `./kestrel run kestrel:tools/format`.
- **Independent of** S08-01 (namespace restructure) — the resolver already handles sub-paths via file-existence fallback (S04-02).

## Goals

1. `./kestrel run kestrel:tools/test [args...]` resolves the specifier to `$ROOT/stdlib/kestrel/tools/test.ks` and runs it.
2. Unknown `kestrel:` specifiers produce a clear error "stdlib module not found: kestrel:X".
3. All existing file-path invocations continue to work.
4. `./kestrel run kestrel:tools/format --help` works once S08-07 creates the file.

## Acceptance Criteria

- `./kestrel run kestrel:tools/test` runs the test tool (after S08-06 creates it).
- `./kestrel run kestrel:no_such_module` prints an error and exits non-zero.
- All existing `kestrel run <file.ks>` invocations are unaffected.
- `kestrel run` with no argument still shows usage.

## Spec References

- `docs/specs/09-tools.md` — `kestrel run` sub-command documentation

## Risks / Notes

- The `resolve_script` function is used by `cmd_run`, `cmd_dis`, and `cmd_build`. Only `cmd_run` should accept module specifiers — `cmd_dis` and `cmd_build` remain file-path-only.
- `main_class_for` uses the file path to derive the JVM class name. When a module specifier is resolved to a physical file, this function still works correctly (path-based).
- The `jvm_class_dir_for` function also uses the file path; it works normally once the specifier is resolved.
