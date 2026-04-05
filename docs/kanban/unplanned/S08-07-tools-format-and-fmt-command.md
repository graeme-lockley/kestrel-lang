# kestrel:tools/format + kestrel fmt command

## Sequence: S08-07
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/unplanned/E08-source-formatter.md)
- Companion stories: S08-01, S08-02, S08-03, S08-04, S08-05, S08-06

## Summary

Create `stdlib/kestrel/tools/format.ks` — the opinionated Kestrel source code formatter — and add `kestrel fmt` as a thin CLI alias for `./kestrel run kestrel:tools/format`. The formatter reads source files, parses them with `kestrel:dev/parser`, converts the AST to a `Doc` IR using `kestrel:dev/text/prettyprinter`, and renders at 120 columns. It writes the formatted result back to the file, or to stdout when `--stdin` is used.

## Current State

No source formatter exists for Kestrel. All formatting is manual.

## Relationship to other stories

- **Depends on** S08-01 (namespace restructure) — imports from `kestrel:data/*`, `kestrel:io/*`.
- **Depends on** S08-02 (module-specifier support) — `./kestrel run kestrel:tools/format` must work.
- **Depends on** S08-03 (dev/cli) — uses `Cli.run` with its `CliSpec`.
- **Depends on** S08-04 (prettyprinter) — uses the `Doc` IR for rendering.
- **Depends on** S08-05 (dev/parser) — uses `lex` and `parse` to read source.
- **Final story in E08.**

## Goals

1. Implement `stdlib/kestrel/tools/format.ks` with:
   - `CliSpec` and `main : List<String> -> Task<Int>` using `Cli.run`.
   - `format : String -> Result<String, FormatError>` — formats source text.
   - `formatFile : String -> Task<Result<Unit, FormatError>>` — reads, formats, writes.
2. Implement all formatting rules from the epic:
   | Rule | Value |
   |------|-------|
   | Line width | 120 characters |
   | Indent unit | 2 spaces |
   | `fun` body | Always break after `=`; body indented 2 |
   | `match` arms | Each arm on its own line; multiline body indented 2 |
   | `if`/`else` | Inline when ≤ 120; break branches otherwise |
   | Record literals | Inline when short; one field per line when long |
   | List literals | Inline when short; one element per line when long |
   | Function call args | Inline when short; one per line when long |
   | Pipeline `\|>` | Each step on its own line |
   | Imports | All specs on one line when short; one spec per line when long |
   | Trailing newline | Always exactly one |
3. Add `kestrel fmt` alias in `scripts/kestrel`.
4. Add `kestrel fmt --check` mode: exit non-zero without modifying files.
5. Add stdin/stdout mode when `--stdin` is given.

## Acceptance Criteria

- `kestrel fmt hello.ks` reformats `hello.ks` in-place.
- `kestrel fmt --check hello.ks` exits 0 if already formatted, 1 if not, without modifying the file.
- `cat hello.ks | kestrel fmt --stdin` reads from stdin, writes formatted output to stdout.
- When no args and no `--stdin`, print usage/help.
- Formatter is **idempotent**: `format(format(source)) == format(source)` — verified by a test that formats every file in `stdlib/kestrel/` twice and asserts the second pass is identical.
- All files in `tests/conformance/`, `tests/unit/`, `stdlib/kestrel/` pass through the formatter without changing runtime output (run tests before and after formatting; both must pass).
- `./kestrel run kestrel:tools/format --help` prints auto-generated help from `CliSpec`.
- `kestrel fmt --version` prints `format 0.1.0`.
- `cd compiler && npm test` passes.
- `./scripts/kestrel test` passes.
- `./scripts/run-e2e.sh` passes (both positive and negative E2E scenarios).

## Spec References

- `docs/specs/01-language.md` — formatting rules align with language grammar
- `docs/specs/02-stdlib.md` — stdlib public API
- `docs/specs/09-tools.md` — `kestrel fmt` CLI reference

## Risks / Notes

- The formatter outputs source code regenerated from the AST + comment tokens. Comments that appear between tokens must be re-attached to AST nodes (most likely as leading/trailing trivia). This is the hardest part of the formatter.
- Test idempotency by formatting all stdlib files and checking the second pass produces no diff.
- The `--check` flag is important for CI: `kestrel fmt --check ./**/*.ks` should pass in CI after the formatter is applied.
- If `kestrel:dev/parser` does not preserve all whitespace/comment tokens (from S08-05), source round-trip is lossless only for the structured layout. Comments that appear in unusual positions may be re-located. Document any such limitations in the spec.
- `FormatError` should include a parse error message and the failing file path.
- Start with declarations and simple expressions; layer in complex forms (match, record, pipeline) as the test corpus grows.
