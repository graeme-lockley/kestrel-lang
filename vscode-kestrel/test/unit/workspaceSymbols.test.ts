import { describe, expect, it } from 'vitest';

import { collectWorkspaceSymbols } from '../../src/server/providers/workspaceSymbols';

describe('collectWorkspaceSymbols', () => {
  it('returns top-level symbols across files and supports query filtering', () => {
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
        {
          name: 'answer',
          kind: 'val',
          exported: true,
          uri: 'file:///tmp/b.ks',
          line: 2,
          column: 5,
          endLine: 2,
          endColumn: 11,
        },
      ],
      declsByName: new Map(),
      exportedNames: [],
      sourcesByUri: new Map(),
    };

    const all = collectWorkspaceSymbols(workspaceIndex, '');
    const filtered = collectWorkspaceSymbols(workspaceIndex, 'add');

    expect(all).toHaveLength(2);
    expect(filtered).toHaveLength(1);
    expect(filtered[0]?.name).toBe('add');
  });
});
