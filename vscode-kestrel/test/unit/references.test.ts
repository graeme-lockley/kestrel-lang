import { describe, expect, it } from 'vitest';

import { findReferences } from '../../src/server/providers/references';

describe('findReferences', () => {
  it('collects references across workspace files', () => {
    const workspaceIndex = {
      decls: [],
      declsByName: new Map(),
      exportedNames: [],
      sourcesByUri: new Map([
        ['file:///tmp/a.ks', 'export fun add(a: Int, b: Int): Int = a + b\n'],
        ['file:///tmp/b.ks', 'val n = add(1, 2)\n'],
      ]),
    };

    const refs = findReferences('val n = add(1, 2)\n', { line: 0, character: 9 }, workspaceIndex);
    const uris = new Set(refs.map((r) => r.uri));

    expect(uris.has('file:///tmp/a.ks')).toBe(true);
    expect(uris.has('file:///tmp/b.ks')).toBe(true);
    expect(refs.length).toBeGreaterThanOrEqual(2);
  });
});
