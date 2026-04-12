import { describe, expect, it, vi } from 'vitest';

import * as bridge from '../../src/server/compiler-bridge';
import { buildHover } from '../../src/server/providers/hover';

describe('buildHover', () => {
  it('returns markdown hover when a type is found', async () => {
    const spy = vi.spyOn(bridge, 'hoverTypeAtOffset').mockResolvedValue('Int');

    const hover = await buildHover('val x = 1', {}, { line: 0, character: 1 });

    expect(hover).not.toBeNull();
    expect(hover?.contents).toEqual({ kind: 'markdown', value: '```kestrel\nInt\n```' });
    spy.mockRestore();
  });

  it('returns null when no hover type is found', async () => {
    const spy = vi.spyOn(bridge, 'hoverTypeAtOffset').mockResolvedValue(null);

    const hover = await buildHover('val x = 1', {}, { line: 0, character: 1 });

    expect(hover).toBeNull();
    spy.mockRestore();
  });
});
