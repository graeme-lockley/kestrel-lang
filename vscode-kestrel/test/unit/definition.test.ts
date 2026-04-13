import { describe, expect, it } from 'vitest';

import { compileWorkspace } from '../../src/server/compiler-bridge';
import { findDefinition } from '../../src/server/providers/definition';
import { createTempWorkspace } from './workspaceTestUtils';

describe('findDefinition', () => {
  it('resolves top-level function definitions', () => {
    const source = 'fun add(a: Int, b: Int): Int = a + b\nval x = add(1, 2)\n';
    const ast = {
      kind: 'Program',
      imports: [],
      body: [
        { kind: 'FunDecl', name: 'add', span: { line: 1, column: 1, endLine: 1, endColumn: 4 } },
      ],
    };

    const def = findDefinition(ast, source, 'file:///tmp/test.ks', { line: 1, character: 9 });
    expect(def?.range.start.line).toBe(0);
    expect(def?.range.start.character).toBe(0);
  });

  it('returns null when symbol is unresolved', () => {
    const source = 'val x = unknown\n';
    const ast = { kind: 'Program', imports: [], body: [] };
    const def = findDefinition(ast, source, 'file:///tmp/test.ks', { line: 0, character: 10 });
    expect(def).toBeNull();
  });

  it('resolves imported named symbols to their defining file instead of the import statement', async () => {
    const workspace = createTempWorkspace({
      'stdlib/kestrel/data/string.ks': '/// Converts text to an integer\nexport fun parseInt(s: String): Int = 0\n',
      'main.ks': 'import { parseInt } from "kestrel:data/string"\nval x = parseInt("1")\n',
    });

    try {
      const workspaceIndex = await compileWorkspace(workspace.rootDir);
      const source = 'import { parseInt } from "kestrel:data/string"\nval x = parseInt("1")\n';
      const ast = workspaceIndex.modulesByUri.get(workspace.uriFor('main.ks'))?.ast ?? null;

      const def = findDefinition(ast, source, workspace.uriFor('main.ks'), { line: 1, character: 9 }, workspaceIndex);
      expect(def?.uri).toBe(workspace.uriFor('stdlib/kestrel/data/string.ks'));
      expect(def?.range.start.line).toBe(1);
      expect(def?.range.start.character).toBe(11);
    } finally {
      workspace.dispose();
    }
  });
});
