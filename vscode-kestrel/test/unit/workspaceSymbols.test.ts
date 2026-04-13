import { describe, expect, it } from 'vitest';

import type { WorkspaceIndex } from '../../src/server/compiler-bridge';
import { collectWorkspaceSymbols } from '../../src/server/providers/workspaceSymbols';

describe('collectWorkspaceSymbols', () => {
  it('returns top-level symbols across files and supports query filtering', () => {
    const workspaceIndex: WorkspaceIndex = {
      decls: [
        {
          name: 'add',
          kind: 'fun',
          exported: true,
          uri: 'file:///tmp/a.ks',
          bindingKey: 'file:///tmp/a.ks:11:14:add',
          start: 11,
          end: 14,
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
          bindingKey: 'file:///tmp/b.ks:4:10:answer',
          start: 4,
          end: 10,
          line: 2,
          column: 5,
          endLine: 2,
          endColumn: 11,
        },
      ],
      declsByName: new Map(),
      declsByUri: new Map(),
      exportedNames: [],
      sourcesByUri: new Map(),
      modulesByUri: new Map(),
      bindingDeclarations: new Map(),
      bindingOccurrences: new Map(),
    };

    const all = collectWorkspaceSymbols(workspaceIndex, '');
    const filtered = collectWorkspaceSymbols(workspaceIndex, 'add');

    expect(all).toHaveLength(2);
    expect(filtered).toHaveLength(1);
    expect(filtered[0]?.name).toBe('add');
  });
});
