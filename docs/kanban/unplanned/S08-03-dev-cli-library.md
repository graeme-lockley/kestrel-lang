# kestrel:dev/cli — CLI argument parser library

## Sequence: S08-03
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/unplanned/E08-source-formatter.md)
- Companion stories: S08-01, S08-02, S08-04, S08-05, S08-06, S08-07

## Summary

Create `stdlib/kestrel/dev/cli.ks` — a self-describing CLI argument parser for Kestrel tools. It provides declarative `CliSpec`, `CliOption`, and `CliArg` ADTs along with `parse`, `run`, `help`, and `version` functions. Tools built on this library automatically get `--help` and `--version` handling without any per-tool code.

This is a pure Kestrel library; no TypeScript, Java, or compiler changes are required.

## Current State

No CLI argument parsing library exists in the stdlib. Each tool (currently only the test runner in `scripts/run_tests.ks`) parses `argv` manually. The E08 formatter and test tool need a shared, declarative approach.

## Relationship to other stories

- **Depends on** S08-01 (namespace restructure) because `cli.ks` will import from `kestrel:data/string`, `kestrel:data/list`, `kestrel:data/dict`, `kestrel:data/option`, `kestrel:data/result`.
- **Required by** S08-06 (kestrel:tools/test) and S08-07 (kestrel:tools/format).
- **Independent of** S08-04 (prettyprinter) and S08-05 (parser).

## Goals

1. Implement the `CliSpec`, `CliOption`, `CliOptionKind`, `CliArg`, `ParsedArgs`, and `CliError` types.
2. Implement `parse : CliSpec -> List<String> -> Result<ParsedArgs, CliError>`.
3. Implement `run : CliSpec -> (ParsedArgs -> Task<Int>) -> List<String> -> Task<Int>` — handles `--help` and `--version` automatically.
4. Implement `help : CliSpec -> String` — renders formatted help from the spec.
5. Implement `version : CliSpec -> String` — renders `name vX.Y.Z`.

## Acceptance Criteria

- A tool can declare a `CliSpec` and call `Cli.run spec argv handler` with `--help` and `--version` working for free.
- `Cli.parse` returns `Ok(ParsedArgs)` for valid argv; `Err(CliError)` for unknown options or missing required arguments.
- `Cli.help spec` produces the canonical help format shown in the epic:
  ```
  name version — description
  
  Usage:
    usage string
  
  Options:
    -h, --help     Show this help message and exit
    -V, --version  Show version and exit
        --check    ...
  
  Arguments:
    files...  ...
  ```
- All unit tests for `kestrel:dev/cli` pass.

## Spec References

- `docs/specs/02-stdlib.md` — stdlib public API
- `docs/specs/09-tools.md` — tool invocation and CLI conventions

## Risks / Notes

- `CliOptionKind` is a union type: `Flag | Value(String)`. `Flag` options produce `"true"` in `ParsedArgs.options`; `Value` options produce the argument string.
- Short flags (e.g. `-h`) are aliases for their long form; both map to the same `ParsedArgs.options` key (the long name).
- `--help` and `--version` are reserved; the library intercepts them before calling the user handler. Tools must not declare them in their `CliSpec`.
- Variadic positional args are collected as a list in `ParsedArgs.positional`; only the last `CliArg` can be variadic.
- Error messages from `parse` should be actionable (e.g. "unknown option: --foo; run with --help for usage").
