# vscode-kestrel

VS Code extension scaffold for Kestrel `.ks` files.

## Features

- Language registration for `.ks` files
- TextMate syntax grammar (`syntaxes/kestrel.tmLanguage.json`)
- Language configuration (`language-configuration.json`)
- Extension activation entry point (`src/extension.ts`)
- LSP-backed diagnostics, hover, definition, symbols, folding, semantic tokens, inlay hints
- Quick-fix code actions for `type:unknown_variable` and `type:non_exhaustive_match`
- Test CodeLens commands for `test("name", ...)` calls

## Development

```bash
cd vscode-kestrel
npm install
npm run compile
npm test
```

## Run in VS Code Extension Host

1. Open this repository in VS Code.
2. Open the `vscode-kestrel` folder as the workspace root or keep it in the multi-root workspace.
3. Press `F5` to launch an Extension Development Host.
4. Open any `.ks` file and verify highlighting and editor behavior.

## Packaging

```bash
cd vscode-kestrel
npm run package
```

This emits a `.vsix` package in `vscode-kestrel/` suitable for local install in VS Code.
