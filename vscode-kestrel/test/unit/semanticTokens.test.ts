import { describe, expect, it } from 'vitest';

import { collectSemanticTokens } from '../../src/server/providers/semanticTokens';

describe('collectSemanticTokens', () => {
  it('emits semantic tokens for basic source', async () => {
    const source = 'fun add(a: Int): Int = a\nval x = add(1)\n';
    const tokens = await collectSemanticTokens(source);
    expect(tokens.data.length).toBeGreaterThan(0);
  });
});
