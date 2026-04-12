import type { CodeLens, Position, Range } from 'vscode-languageserver/node';

function makeRange(line: number, character: number): Range {
  const pos: Position = { line, character };
  return { start: pos, end: pos };
}

export function collectTestCodeLenses(uri: string, source: string): CodeLens[] {
  const out: CodeLens[] = [];
  const lines = source.split('\n');

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i] ?? '';
    const m = line.match(/\btest\s*\(\s*"([^"]+)"/);
    if (m == null) {
      continue;
    }

    const testName = m[1] ?? '';
    const col = m.index ?? 0;
    const range = makeRange(i, col);

    out.push({
      range,
      command: {
        title: '▶ Run test',
        command: 'kestrel.runTest',
        arguments: [testName, uri],
      },
    });

    out.push({
      range,
      command: {
        title: '▶ Debug test',
        command: 'kestrel.debugTest',
        arguments: [testName, uri],
      },
    });
  }

  return out;
}
