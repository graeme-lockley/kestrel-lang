import type { Position, TextEdit, WorkspaceEdit } from 'vscode-languageserver/node';

import type { WorkspaceIndex } from '../compiler-bridge';
import { findReferences } from './references';

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

function isValidIdentifier(name: string): boolean {
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(name);
}

export function buildRenameEdit(
  source: string,
  position: Position,
  newName: string,
  workspaceIndex: WorkspaceIndex,
): WorkspaceEdit | null {
  if (!isValidIdentifier(newName)) {
    return null;
  }

  const current = identifierAt(source, offsetFromPosition(source, position));
  if (current == null || current === newName) {
    return null;
  }

  if ((workspaceIndex.declsByName.get(newName) ?? []).length > 0) {
    return null;
  }

  const refs = findReferences(source, position, workspaceIndex);
  if (refs.length === 0) {
    return null;
  }

  const changes: Record<string, TextEdit[]> = {};
  for (const ref of refs) {
    const arr = changes[ref.uri] ?? [];
    arr.push({ range: ref.range, newText: newName });
    changes[ref.uri] = arr;
  }

  return { changes };
}
