import type { Location, Position, Range } from 'vscode-languageserver/node';

import type { WorkspaceIndex } from '../compiler-bridge';

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
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(ident) ? ident : null;
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

function findIdentifierRanges(source: string, ident: string): Range[] {
  const out: Range[] = [];
  if (ident.length === 0) {
    return out;
  }

  const re = new RegExp(`\\b${ident}\\b`, 'g');
  let match: RegExpExecArray | null;
  while ((match = re.exec(source)) != null) {
    const start = match.index;
    const end = start + ident.length;
    out.push({
      start: offsetToPosition(source, start),
      end: offsetToPosition(source, end),
    });
  }
  return out;
}

export function findReferences(
  source: string,
  position: Position,
  workspaceIndex: WorkspaceIndex,
): Location[] {
  const offset = offsetFromPosition(source, position);
  const ident = identifierAt(source, offset);
  if (ident == null) {
    return [];
  }

  const out: Location[] = [];
  for (const [uri, fileSource] of workspaceIndex.sourcesByUri) {
    const ranges = findIdentifierRanges(fileSource, ident);
    for (const range of ranges) {
      out.push({ uri, range });
    }
  }
  return out;
}
