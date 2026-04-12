import { describe, expect, it } from 'vitest';

import { collectFoldingRanges } from '../../src/server/providers/folding';

describe('collectFoldingRanges', () => {
  it('collects folding ranges from block/type spans', () => {
    const ast = {
      kind: 'Program',
      body: [
        { kind: 'FunDecl', name: 'x', span: { line: 1, endLine: 4 }, body: { kind: 'BlockExpr', span: { line: 1, endLine: 4 } } },
        { kind: 'TypeDecl', name: 'Option', span: { line: 5, endLine: 8 } },
      ],
    };

    const ranges = collectFoldingRanges(ast, '');
    expect(ranges.some((r) => r.startLine === 0 && r.endLine === 3)).toBe(true);
    expect(ranges.some((r) => r.startLine === 4 && r.endLine === 7)).toBe(true);
  });

  it('collects multiline block comment folding ranges', () => {
    const source = 'val x = 1\n/* a\n b\n*/\nval y = 2\n';
    const ranges = collectFoldingRanges(null, source);
    expect(ranges.some((r) => r.startLine === 1 && r.endLine === 3)).toBe(true);
  });
});
