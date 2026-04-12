import { describe, expect, it } from 'vitest';

import { findDefinition } from '../../src/server/providers/definition';

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

  it('resolves definitions from workspace index when not local', () => {
    const source = 'import { parseInt } from "kestrel:data/string"\nval x = parseInt("1")\n';
    const ast = { kind: 'Program', imports: [], body: [] };
    const workspaceIndex = {
      decls: [],
      exportedNames: ['parseInt'],
      sourcesByUri: new Map<string, string>(),
      declsByName: new Map([
        ['parseInt', [{
          name: 'parseInt',
          kind: 'fun',
          exported: true,
          uri: 'file:///tmp/string.ks',
          line: 4,
          column: 12,
          endLine: 4,
          endColumn: 20,
        }]],
      ]),
    };

    const def = findDefinition(ast, source, 'file:///tmp/main.ks', { line: 1, character: 12 }, workspaceIndex);
    expect(def?.uri).toBe('file:///tmp/string.ks');
    expect(def?.range.start.line).toBe(3);
  });
});
