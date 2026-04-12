import type { Location, Position, Range } from 'vscode-languageserver/node';

import type { WorkspaceIndex } from '../compiler-bridge';

function rangeFromSpan(span: { line: number; column: number; endLine?: number; endColumn?: number }): Range {
  const startLine = Math.max(0, span.line - 1);
  const startChar = Math.max(0, span.column - 1);
  const endLine = Math.max(0, (span.endLine ?? span.line) - 1);
  const endChar = Math.max(startChar + 1, (span.endColumn ?? span.column + 1) - 1);
  return {
    start: { line: startLine, character: startChar },
    end: { line: endLine, character: endChar },
  };
}

function offsetFromPosition(source: string, pos: Position): number {
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

function identifierAt(source: string, offset: number): string | null {
  if (offset < 0 || offset > source.length) {
    return null;
  }

  const isWord = (ch: string) => /[A-Za-z0-9_]/.test(ch);
  let left = offset;
  let right = offset;

  while (left > 0 && isWord(source[left - 1] ?? '')) {
    left--;
  }
  while (right < source.length && isWord(source[right] ?? '')) {
    right++;
  }

  if (left === right) {
    return null;
  }
  const ident = source.slice(left, right);
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(ident)) {
    return null;
  }
  return ident;
}

function declarationRanges(ast: unknown): Map<string, Range> {
  const out = new Map<string, Range>();
  const program = ast as { body?: unknown[]; imports?: unknown[] };

  for (const imp of program.imports ?? []) {
    if (imp == null || typeof imp !== 'object') continue;
    const n = imp as { kind?: string; specs?: Array<{ local?: string }>; span?: { line: number; column: number; endLine?: number; endColumn?: number } };
    if (n.kind === 'NamedImport' && Array.isArray(n.specs) && n.span != null) {
      const r = rangeFromSpan(n.span);
      for (const spec of n.specs) {
        if (spec.local != null) {
          out.set(spec.local, r);
        }
      }
    }
  }

  for (const node of program.body ?? []) {
    if (node == null || typeof node !== 'object') continue;
    const d = node as {
      kind?: string;
      name?: string;
      span?: { line: number; column: number; endLine?: number; endColumn?: number };
      body?: { kind?: string; constructors?: Array<{ name?: string; span?: { line: number; column: number; endLine?: number; endColumn?: number } }> };
    };

    if (d.name != null && d.span != null) {
      out.set(d.name, rangeFromSpan(d.span));
    }

    if (d.kind === 'TypeDecl' && d.body?.kind === 'ADTBody') {
      for (const ctor of d.body.constructors ?? []) {
        if (ctor.name != null && ctor.span != null) {
          out.set(ctor.name, rangeFromSpan(ctor.span));
        }
      }
    }
  }

  return out;
}

export function findDefinition(
  ast: unknown | null,
  source: string,
  uri: string,
  position: Position,
  workspaceIndex?: WorkspaceIndex,
): Location | null {
  if (ast == null) {
    return null;
  }

  const offset = offsetFromPosition(source, position);
  const ident = identifierAt(source, offset);
  if (ident == null) {
    return null;
  }

  const ranges = declarationRanges(ast);
  const range = ranges.get(ident);
  if (range != null) {
    return { uri, range };
  }

  const workspaceDecl = workspaceIndex?.declsByName.get(ident)?.[0];
  if (workspaceDecl == null) {
    return null;
  }

  return {
    uri: workspaceDecl.uri,
    range: {
      start: {
        line: Math.max(0, workspaceDecl.line - 1),
        character: Math.max(0, workspaceDecl.column - 1),
      },
      end: {
        line: Math.max(0, workspaceDecl.endLine - 1),
        character: Math.max(0, workspaceDecl.endColumn - 1),
      },
    },
  };
}
