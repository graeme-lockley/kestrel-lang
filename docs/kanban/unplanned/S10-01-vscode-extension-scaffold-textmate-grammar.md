# VSCode Extension: Project Scaffold and TextMate Grammar

## Sequence: S10-01
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E10 VSCode Extension — Language Server and Editor Integration](../epics/unplanned/E10-vscode-extension-language-server.md)
- Companion stories: S10-02, S10-03, S10-04, S10-05, S10-06, S10-07, S10-08, S10-09, S10-10, S10-11, S10-12

## Summary

Bootstrap the `vscode-kestrel/` directory with the VS Code extension manifest, TypeScript build configuration, and a TextMate grammar (`kestrel.tmLanguage.json`) plus language configuration (`language-configuration.json`). The extension activates on `*.ks` files and provides syntax highlighting, bracket matching, comment toggling, and basic indentation — everything before an LSP server is involved.

## Current State

No `vscode-kestrel/` directory exists. Kestrel `.ks` files open in VS Code with no syntax highlighting. All keywords, literals, operators, and type names are rendered as plain text.

## Relationship to other stories

- **Prerequisite for all other S10 stories** — the project scaffold (package.json, tsconfig.json, dist/ pipeline) is needed before the LSP client/server can be implemented.
- S10-02 (LSP server skeleton) adds the server module inside the directory created here.

## Goals

1. Create `vscode-kestrel/package.json` as a valid VS Code extension manifest declaring the `kestrel` language, `.ks` file association, and activation event.
2. Write `syntaxes/kestrel.tmLanguage.json` covering: keywords (`fun val var type match if else while break continue async await export import from exception is opaque extern`), type-position names (PascalCase identifiers), ADT constructors (PascalCase in expression position), operators (`|>`, `::`, `->`, `=>`), string/char literals, numeric literals, `//` and `/* */` comments, template string interpolation, and `///`/`//!` doc-comment tokens.
3. Write `language-configuration.json` with bracket pairs `()`, `[]`, `{}`, comment tokens `//` and `/* */`, and auto-close rules.
4. Provide `tsconfig.json`, a minimal `src/extension.ts` that activates (logs a message), and an `npm run compile` build script using `tsc`.
5. Produce a `vscode-kestrel/README.md` documenting installation from `.vsix` and development workflow.
6. Grammar tests (snapshot / manual): keywords render as keyword scope; `True`/`False` as constant.language; type names as entity.name.type; string literals as string.quoted.

## Acceptance Criteria

- `vscode-kestrel/` contains `package.json`, `tsconfig.json`, `src/extension.ts`, `syntaxes/kestrel.tmLanguage.json`, `language-configuration.json`, and `README.md`.
- Running `npm install && npm run compile` inside `vscode-kestrel/` succeeds with no errors.
- Installing the resulting `.vsix` (or using the extension development host) causes `.ks` files to have syntax coloring for all listed constructs.
- No LSP server is started; the extension is pure grammar + language config at this stage.

## Spec References

- `docs/specs/09-tools.md` — will need an "Editor Integration" section (added in a later story).

## Risks / Notes

- TextMate grammar precision: over-eager rules can mis-color user-defined names. The grammar should use scoping rules that do not try to be too smart about context (the semantic token provider in S10-06 will do the precise coloring).
- The extension should be structured from the start to support the LSP client/server split (`vscode-languageclient` on the extension host, `vscode-languageserver` on the server process) so that S10-02 can add the server without restructuring.
- VS Code Marketplace publish (`vsce package`) is deferred to S10-09; this story only needs `npm run compile` to work.
