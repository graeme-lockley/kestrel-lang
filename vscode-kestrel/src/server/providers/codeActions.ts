import {
  CodeActionKind,
  type CodeAction,
  type Diagnostic,
  type Position,
  type TextEdit,
} from 'vscode-languageserver/node';

import type { CompilerDiagnostic } from '../document-manager';

const TIER1_IMPORT_INDEX: Record<string, string> = {
  println: 'kestrel:io/console',
  print: 'kestrel:io/console',
  eprintln: 'kestrel:io/console',
  Option: 'kestrel:data/option',
  Result: 'kestrel:data/result',
  List: 'kestrel:data/list',
};

function toCode(diag: Diagnostic): string {
  if (typeof diag.code === 'string') {
    return diag.code;
  }
  return '';
}

function positionToOffset(source: string, pos: Position): number {
  let line = 0;
  let col = 0;
  for (let i = 0; i < source.length; i++) {
    if (line === pos.line && col === pos.character) {
      return i;
    }
    if (source.charCodeAt(i) === 10) {
      line++;
      col = 0;
    } else {
      col++;
    }
  }
  return source.length;
}

function offsetToPosition(source: string, offset: number): Position {
  let line = 0;
  let col = 0;
  for (let i = 0; i < offset && i < source.length; i++) {
    if (source.charCodeAt(i) === 10) {
      line++;
      col = 0;
    } else {
      col++;
    }
  }
  return { line, character: col };
}

function insertionAfterImports(source: string): Position {
  const lines = source.split('\n');
  let lastImport = -1;
  for (let i = 0; i < lines.length; i++) {
    if (/^\s*import\s+/.test(lines[i] ?? '')) {
      lastImport = i;
    }
  }
  if (lastImport < 0) {
    return { line: 0, character: 0 };
  }
  return { line: lastImport + 1, character: 0 };
}

function unknownName(message: string): string | null {
  const m = message.match(/Unknown variable\s+[`'"]?([A-Za-z_][A-Za-z0-9_]*)/i);
  return m?.[1] ?? null;
}

function missingConstructors(hint: string | undefined): string[] {
  if (hint == null || hint.length === 0) {
    return [];
  }
  const part = hint.includes(':') ? hint.slice(hint.indexOf(':') + 1) : hint;
  const matches = part.match(/[A-Z][A-Za-z0-9_]*/g) ?? [];
  const out: string[] = [];
  for (const name of matches) {
    if (!out.includes(name)) {
      out.push(name);
    }
  }
  return out;
}

function findCompilerDiagnostic(lsp: Diagnostic, compilerDiagnostics: CompilerDiagnostic[]): CompilerDiagnostic | null {
  const code = toCode(lsp);
  return (
    compilerDiagnostics.find((d) => d.code === code && d.message === lsp.message) ??
    compilerDiagnostics.find((d) => d.code === code) ??
    null
  );
}

function addImportAction(uri: string, source: string, diag: Diagnostic): CodeAction | null {
  const name = unknownName(diag.message);
  if (name == null) {
    return null;
  }
  const moduleName = TIER1_IMPORT_INDEX[name];
  if (moduleName == null) {
    return null;
  }

  const existing = new RegExp(`import\\s*\\{[^}]*\\b${name}\\b[^}]*\\}\\s*from\\s*"[^"]+"`);
  if (existing.test(source)) {
    return null;
  }

  const insertPos = insertionAfterImports(source);
  const importLine = `import { ${name} } from "${moduleName}"\n`;
  const edit: TextEdit = {
    range: { start: insertPos, end: insertPos },
    newText: importLine,
  };

  return {
    title: `Import ${name} from "${moduleName}"`,
    kind: CodeActionKind.QuickFix,
    diagnostics: [diag],
    edit: { changes: { [uri]: [edit] } },
  };
}

function exhaustivenessAction(
  uri: string,
  source: string,
  diag: Diagnostic,
  compilerDiag: CompilerDiagnostic | null,
): CodeAction | null {
  const ctors = missingConstructors(compilerDiag?.hint);
  if (ctors.length === 0) {
    return null;
  }

  const endOffset = positionToOffset(source, diag.range.end);
  const closeOffset = source.indexOf('}', endOffset);
  if (closeOffset < 0) {
    return null;
  }

  const lineStart = source.lastIndexOf('\n', closeOffset - 1) + 1;
  const indent = (source.slice(lineStart, closeOffset).match(/^\s*/) ?? [''])[0] ?? '';
  const armIndent = `${indent}  `;
  const bodyIndent = `${indent}    `;

  const newArms = ctors
    .map((c) => `${armIndent}| ${c}(_) => ${bodyIndent}"TODO"`)
    .join('\n');

  const insertPos = offsetToPosition(source, closeOffset);
  const edit: TextEdit = {
    range: { start: insertPos, end: insertPos },
    newText: `\n${newArms}\n`,
  };

  return {
    title: 'Add missing match arms',
    kind: CodeActionKind.QuickFix,
    diagnostics: [diag],
    edit: { changes: { [uri]: [edit] } },
  };
}

export function collectCodeActions(
  uri: string,
  source: string,
  diagnostics: Diagnostic[],
  compilerDiagnostics: CompilerDiagnostic[],
): CodeAction[] {
  const out: CodeAction[] = [];

  for (const diag of diagnostics) {
    const code = toCode(diag);
    if (code === 'type:unknown_variable') {
      const action = addImportAction(uri, source, diag);
      if (action != null) {
        out.push(action);
      }
      continue;
    }

    if (code === 'type:non_exhaustive_match') {
      const compilerDiag = findCompilerDiagnostic(diag, compilerDiagnostics);
      const action = exhaustivenessAction(uri, source, diag, compilerDiag);
      if (action != null) {
        out.push(action);
      }
    }
  }

  return out;
}
