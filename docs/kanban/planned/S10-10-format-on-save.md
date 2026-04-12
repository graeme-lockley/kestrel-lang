# VSCode Extension: Format on Save (requires E08)

## Sequence: S10-10
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E10 VSCode Extension — Language Server and Editor Integration](../epics/unplanned/E10-vscode-extension-language-server.md)
- Companion stories: S10-01, S10-02, S10-03, S10-04, S10-05, S10-06, S10-07, S10-08, S10-09, S10-11, S10-12

## Summary

Implement `textDocument/formatting` and `textDocument/rangeFormatting` by invoking `kestrel fmt --stdin` as a subprocess and returning the resulting text edits. When `editor.formatOnSave` is enabled in VS Code, the active `.ks` file is formatted automatically on save. E08 (Source Formatter epic) is complete and `kestrel fmt --stdin` is available.

## Current State

No formatting provider exists. E08 introduces `kestrel fmt` with `--stdin` mode (reads source from stdin, writes formatted source to stdout). The formatter's behavior, indentation style, and line length are defined in E08. The extension project structure (S10-01) supports adding new providers.

## Relationship to other stories

- **Depends on S10-09** — the `kestrel.executable` setting introduced in S10-09 is used by the formatter subprocess.
- **Depends on S10-02** (document-manager) for the cached source text.
- Independent of S10-03 through S10-09 in terms of code, but logically polishes the Tier 1 experience.

## Goals

1. Add `vscode-kestrel/src/server/providers/formatting.ts`: spawns `kestrel fmt --stdin`, pipes the document source to stdin, reads formatted output from stdout, diffs against original to produce a minimal `TextEdit[]` array (full-file replace is acceptable as a first implementation).
2. Handle formatter exit codes: non-zero means the file could not be formatted (parse error); return an empty edit array and log a warning rather than corrupting the file.
3. Register `documentFormattingProvider: true` and `documentRangeFormattingProvider: true` in server capabilities (range formatting calls full-file format and returns edits only within the requested range).
4. Add a VS Code setting `kestrel.formatter.enabled` (default `true`) that allows users to disable the formatter without changing `editor.formatOnSave`.
5. Add a VS Code setting `kestrel.executable` (default `kestrel`) that points to the `kestrel` binary; both the formatter and the test CodeLens launcher use this path.
6. Unit test: mock `kestrel fmt --stdin` subprocess, verify that a source with trailing whitespace produces the correct `TextEdit` to remove it.

## Acceptance Criteria

- With `editor.formatOnSave: true`, saving a `.ks` file with inconsistent formatting produces a formatted file.
- A file with a parse error is not modified by format-on-save.
- `kestrel.executable` setting is respected; pointing it to a non-existent path disables formatting gracefully (warning, no error popup).
- Format command is exposed in the VS Code command palette as "Format Document".

## Spec References

- `docs/specs/09-tools.md` §2.5 `kestrel fmt` — usage, flags (`--stdin`, `--check`), exit codes (added by S08-07).

## Risks / Notes

- The `kestrel fmt` subprocess launch path must use `kestrel.executable` setting (from S10-09) rather than a hard-coded `kestrel`. This setting should be read at the time of each format invocation, not at server startup.
- Full-file `TextEdit` replace is the simplest approach but causes the cursor to jump to line 0 in some VS Code versions. Producing a diff-based minimal edit set avoids this; a library like `diff` (npm) can generate line-level diffs cheaply.

## Impact analysis

| Area | Change |
|------|--------|
| Formatting provider | Add `vscode-kestrel/src/server/providers/formatting.ts` invoking `kestrel fmt --stdin` and translating output to `TextEdit[]`. |
| LSP server wiring | Register document/range formatting capabilities and handlers in `vscode-kestrel/src/server/server.ts`. |
| Client settings | Plumb `kestrel.executable` and new `kestrel.formatter.enabled` from extension configuration to server initialization options. |
| Extension manifest | Add `kestrel.formatter.enabled` configuration contribution in `vscode-kestrel/package.json`. |
| Tests | Add unit tests for formatter success, no-op, and failed subprocess behavior. |

## Tasks

- [ ] Add formatting provider implementation in `vscode-kestrel/src/server/providers/formatting.ts` using `kestrel fmt --stdin`.
- [ ] Wire `documentFormattingProvider` and `documentRangeFormattingProvider` in `vscode-kestrel/src/server/server.ts`.
- [ ] Plumb executable and formatter enabled settings through `vscode-kestrel/src/extension.ts` initialization options.
- [ ] Add `kestrel.formatter.enabled` setting to `vscode-kestrel/package.json` contributions.
- [ ] Add `vscode-kestrel/test/unit/formatting.test.ts` for success/no-op/error cases.
- [ ] Run `cd vscode-kestrel && npm run compile && npm test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit | `vscode-kestrel/test/unit/formatting.test.ts` | Verify formatted output produces a text edit when source changes. |
| Vitest unit | `vscode-kestrel/test/unit/formatting.test.ts` | Verify identical output returns no edits. |
| Vitest unit | `vscode-kestrel/test/unit/formatting.test.ts` | Verify formatter failure returns empty edits without throwing. |

## Documentation and specs to update

- [ ] `docs/specs/09-tools.md` — verify formatter CLI invocation semantics remain aligned; no new textual changes expected.
- [ ] `vscode-kestrel/README.md` — include formatter setting notes.
