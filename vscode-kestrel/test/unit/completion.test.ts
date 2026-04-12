import { describe, expect, it } from 'vitest';

import { collectCompletions } from '../../src/server/providers/completion';

describe('collectCompletions', () => {
  it('includes keywords, imports, and declarations', () => {
    const ast = {
      kind: 'Program',
      imports: [{ kind: 'NamedImport', specs: [{ local: 'println' }] }],
      body: [
        { kind: 'FunDecl', name: 'add', params: [{ name: 'a' }, { name: 'b' }] },
        { kind: 'ValDecl', name: 'answer' },
        {
          kind: 'TypeDecl',
          name: 'Option',
          body: { kind: 'ADTBody', constructors: [{ name: 'Some' }, { name: 'None' }] },
        },
      ],
    };

    const items = collectCompletions(ast);
    const labels = new Set(items.map((i) => i.label));

    expect(labels.has('fun')).toBe(true);
    expect(labels.has('println')).toBe(true);
    expect(labels.has('add')).toBe(true);
    expect(labels.has('answer')).toBe(true);
    expect(labels.has('Some')).toBe(true);
    expect(labels.has('a')).toBe(true);
  });

  it('includes exported names from workspace index', () => {
    const items = collectCompletions(null, ['println', 'parseInt']);
    const labels = new Set(items.map((i) => i.label));
    expect(labels.has('println')).toBe(true);
    expect(labels.has('parseInt')).toBe(true);
  });
});
