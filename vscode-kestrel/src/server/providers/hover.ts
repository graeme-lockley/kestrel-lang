import type { Hover, Position } from 'vscode-languageserver/node';

import { hoverTypeAtOffset } from '../compiler-bridge';

function offsetFromPosition(source: string, pos: Position): number {
  let line = 0;
  let column = 0;

  for (let i = 0; i < source.length; i++) {
    if (line === pos.line && column === pos.character) {
      return i;
    }
    const ch = source.charCodeAt(i);
    if (ch === 10) {
      line++;
      column = 0;
    } else {
      column++;
    }
  }

  return source.length;
}

export async function buildHover(source: string, ast: unknown | null, position: Position): Promise<Hover | null> {
  const offset = offsetFromPosition(source, position);
  const typeText = await hoverTypeAtOffset(ast, offset);
  if (typeText == null) {
    return null;
  }

  return {
    contents: {
      kind: 'markdown',
      value: `\`\`\`kestrel\n${typeText}\n\`\`\``,
    },
  };
}
