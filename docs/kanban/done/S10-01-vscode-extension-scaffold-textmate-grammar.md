# VSCode Extension: Project Scaffold and TextMate Grammar

## Sequence: S10-01
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E10 VSCode Extension — Language Server and Editor Integration](../epics/done/E10-vscode-extension-language-server.md)
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

## Impact analysis

| Area | Change |
|------|--------|
| Extension scaffold | Add new top-level `vscode-kestrel/` TypeScript extension project with VS Code manifest, build scripts, and activation entry point. |
| Grammar and language config | Add `syntaxes/kestrel.tmLanguage.json` and `language-configuration.json` for baseline syntax coloring and editor behavior. |
| Tests | Add lightweight TextMate grammar scope tests under `vscode-kestrel/test/unit/` to validate core token scopes. |
| Docs | Add `vscode-kestrel/README.md` with local dev/build instructions. |

## Tasks

- [x] Create `vscode-kestrel/package.json` with language contribution, activation events, scripts, and extension entry point.
- [x] Create `vscode-kestrel/tsconfig.json` and `src/extension.ts` with minimal activation/deactivation functions.
- [x] Create `vscode-kestrel/syntaxes/kestrel.tmLanguage.json` with keyword/operator/literal/comment/type/constructor rules.
- [x] Create `vscode-kestrel/language-configuration.json` with bracket/comment/autoclose settings.
- [x] Create `vscode-kestrel/README.md` with development and packaging notes.
- [x] Add grammar scope tests in `vscode-kestrel/test/unit/grammar.test.ts`.
- [x] Run `cd vscode-kestrel && npm install && npm run compile && npm test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest unit | `vscode-kestrel/test/unit/grammar.test.ts` | Verify keywords use keyword scope, `True`/`False` use constant scope, and strings use string scopes. |
| Manual extension smoke | VS Code extension host | Open a `.ks` file and verify syntax highlighting and bracket/comment behavior are active. |

## Documentation and specs to update

- [x] `vscode-kestrel/README.md` — add setup, build, and extension-host run instructions.
- [x] `docs/specs/09-tools.md` — no change in this story; Editor Integration section is added in S10-09.

## Build notes

- 2026-04-12: Implemented initial `vscode-kestrel/` scaffold with language contributions, TextMate grammar, language configuration, extension entry point, and grammar unit tests.
- 2026-04-12: Verified local story checks with `cd vscode-kestrel && npm install && npm run compile && npm test`.
- 2026-04-12: Repository-level `./scripts/kestrel test` currently fails on pre-existing parse errors in `stdlib/kestrel/tools/compiler/classfile.ks` (outside S10-01 scope).
