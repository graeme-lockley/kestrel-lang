import { describe, expect, it, vi } from 'vitest';

import * as bridge from '../../src/server/compiler-bridge';
import { provideSignatureHelp } from '../../src/server/providers/signatureHelp';

describe('provideSignatureHelp', () => {
  it('builds signature and active parameter for second argument', async () => {
    const spy = vi.spyOn(bridge, 'inferredTypeText').mockResolvedValue('Int');
    const source = 'fun add(a: Int, b: Int): Int = a + b\nval x = add(1, 2)\n';
    const ast = {
      kind: 'Program',
      body: [
        {
          kind: 'FunDecl',
          name: 'add',
          params: [{ name: 'a' }, { name: 'b' }],
          returnType: { kind: 'PrimType', name: 'Int' },
        },
      ],
    };

    const sig = await provideSignatureHelp(ast, source, { line: 1, character: 14 });
    expect(sig?.activeParameter).toBe(1);
    expect(sig?.signatures[0]?.label.startsWith('add(')).toBe(true);
    spy.mockRestore();
  });

  it('returns null when no matching function declaration exists', async () => {
    const source = 'val x = unknown(1)\n';
    const ast = { kind: 'Program', body: [] };
    const sig = await provideSignatureHelp(ast, source, { line: 0, character: 14 });
    expect(sig).toBeNull();
  });
});
