import { describe, expect, it, vi } from 'vitest';

import * as bridge from '../../src/server/compiler-bridge';
import { collectInlayHints } from '../../src/server/providers/inlayHints';

describe('collectInlayHints', () => {
  it('adds inlay hints for untyped val declarations', async () => {
    const spy = vi.spyOn(bridge, 'inferredTypeText').mockResolvedValue('Int');

    const ast = {
      kind: 'Program',
      body: [
        {
          kind: 'ValDecl',
          name: 'x',
          span: { line: 1, column: 5 },
          value: { kind: 'LiteralExpr' },
        },
      ],
    };

    const hints = await collectInlayHints(ast);
    expect(hints).toHaveLength(1);
    expect(hints[0]?.label).toBe(': Int');
    spy.mockRestore();
  });

  it('does not add hints for explicitly typed val declarations', async () => {
    const spy = vi.spyOn(bridge, 'inferredTypeText').mockResolvedValue('Int');

    const ast = {
      kind: 'Program',
      body: [
        {
          kind: 'ValDecl',
          name: 'x',
          span: { line: 1, column: 5 },
          type: { kind: 'PrimType', name: 'Int' },
          value: { kind: 'LiteralExpr' },
        },
      ],
    };

    const hints = await collectInlayHints(ast);
    expect(hints).toHaveLength(0);
    spy.mockRestore();
  });
});
