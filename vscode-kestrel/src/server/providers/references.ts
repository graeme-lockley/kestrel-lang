import type { Location, Position } from 'vscode-languageserver/node';

import { resolveWorkspaceSymbolAtOffset, type WorkspaceIndex } from '../compiler-bridge';

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

export function findReferences(
  uri: string,
  source: string,
  position: Position,
  workspaceIndex: WorkspaceIndex,
): Location[] {
  const resolved = resolveWorkspaceSymbolAtOffset(uri, source, offsetFromPosition(source, position), workspaceIndex);
  if (resolved == null) {
    return [];
  }

  return resolved.occurrences.flatMap((occurrence) => {
    const occurrenceSource = workspaceIndex.sourcesByUri.get(occurrence.uri);
    if (occurrenceSource == null) {
      return [];
    }
    return [{
      uri: occurrence.uri,
      range: {
        start: offsetToPosition(occurrenceSource, occurrence.start),
        end: offsetToPosition(occurrenceSource, occurrence.end),
      },
    }];
  });
}