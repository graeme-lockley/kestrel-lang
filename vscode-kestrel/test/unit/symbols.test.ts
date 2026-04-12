import { describe, expect, it } from 'vitest';

import { collectDocumentSymbols } from '../../src/server/providers/symbols';

describe('collectDocumentSymbols', () => {
  it('collects top-level declarations', () => {
    const ast = {
      kind: 'Program',
      body: [
        { kind: 'FunDecl', name: 'add', span: { line: 1, column: 1, endLine: 2, endColumn: 1 } },
        { kind: 'ValDecl', name: 'answer', span: { line: 3, column: 1, endLine: 3, endColumn: 10 } },
      ],
    };

    const symbols = collectDocumentSymbols(ast);
    expect(symbols.map((s) => s.name)).toEqual(['add', 'answer']);
  });

  it('nests ADT constructors under type symbols', () => {
    const ast = {
      kind: 'Program',
      body: [
        {
          kind: 'TypeDecl',
          name: 'Option',
          span: { line: 1, column: 1, endLine: 4, endColumn: 1 },
          body: {
            kind: 'ADTBody',
            constructors: [
              { name: 'Some', span: { line: 2, column: 3, endLine: 2, endColumn: 8 } },
              { name: 'None', span: { line: 3, column: 3, endLine: 3, endColumn: 8 } },
            ],
          },
        },
      ],
    };

    const symbols = collectDocumentSymbols(ast);
    expect(symbols).toHaveLength(1);
    expect(symbols[0]?.children?.map((c) => c.name)).toEqual(['Some', 'None']);
  });
});
