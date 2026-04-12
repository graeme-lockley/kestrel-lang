import { describe, expect, it } from 'vitest';

import { buildRenameEdit } from '../../src/server/providers/rename';

describe('buildRenameEdit', () => {
  it('renames declaration and references across files', () => {
    const workspaceIndex = {
      decls: [
        {
          name: 'add',
          kind: 'fun',
          exported: true,
          uri: 'file:///tmp/a.ks',
          line: 1,
          column: 12,
          endLine: 1,
          endColumn: 15,
        },
      ],
      declsByName: new Map([
        ['add', [{
          name: 'add',
          kind: 'fun',
          exported: true,
          uri: 'file:///tmp/a.ks',
          line: 1,
          column: 12,
          endLine: 1,
          endColumn: 15,
        }]],
      ]),
      exportedNames: ['add'],
      sourcesByUri: new Map([
        ['file:///tmp/a.ks', 'export fun add(a: Int, b: Int): Int = a + b\n'],
        ['file:///tmp/b.ks', 'val n = add(1, 2)\n'],
      ]),
    };

    const edit = buildRenameEdit('val n = add(1, 2)\n', { line: 0, character: 9 }, 'sum', workspaceIndex);
    expect(edit).not.toBeNull();
    expect(Object.keys(edit?.changes ?? {})).toContain('file:///tmp/a.ks');
    expect(Object.keys(edit?.changes ?? {})).toContain('file:///tmp/b.ks');
  });

  it('rejects invalid identifiers', () => {
    const workspaceIndex = {
      decls: [],
      declsByName: new Map(),
      exportedNames: [],
      sourcesByUri: new Map([['file:///tmp/a.ks', 'val n = add(1, 2)\n']]),
    };

    const edit = buildRenameEdit('val n = add(1, 2)\n', { line: 0, character: 9 }, '1bad', workspaceIndex);
    expect(edit).toBeNull();
  });
});
