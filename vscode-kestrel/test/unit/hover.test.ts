import { describe, expect, it, vi } from 'vitest';

import * as bridge from '../../src/server/compiler-bridge';
import { buildHover } from '../../src/server/providers/hover';

describe('buildHover', () => {
  it('returns markdown hover when a type is found', async () => {
    const typeSpy = vi.spyOn(bridge, 'hoverTypeAtOffset').mockResolvedValue('Int');
    const docSpy = vi.spyOn(bridge, 'hoverDocAtOffset').mockResolvedValue(null);

    const hover = await buildHover('val x = 1', {}, { line: 0, character: 1 });

    expect(hover).not.toBeNull();
    expect(hover?.contents).toEqual({ kind: 'markdown', value: '```kestrel\nInt\n```' });
    typeSpy.mockRestore();
    docSpy.mockRestore();
  });

  it('returns null when no hover type is found', async () => {
    const typeSpy = vi.spyOn(bridge, 'hoverTypeAtOffset').mockResolvedValue(null);
    const docSpy = vi.spyOn(bridge, 'hoverDocAtOffset').mockResolvedValue('ignored');

    const hover = await buildHover('val x = 1', {}, { line: 0, character: 1 });

    expect(hover).toBeNull();
    typeSpy.mockRestore();
    docSpy.mockRestore();
  });

  it('appends doc-comment markdown under the type when available', async () => {
    const typeSpy = vi.spyOn(bridge, 'hoverTypeAtOffset').mockResolvedValue('(String) -> Int');
    const docSpy = vi
      .spyOn(bridge, 'hoverDocAtOffset')
      .mockResolvedValue('Converts a decimal string to an integer.');

    const hover = await buildHover('fun parseInt(s: String): Int = 0', {}, { line: 0, character: 5 });

    expect(hover).not.toBeNull();
    expect(hover?.contents).toEqual({
      kind: 'markdown',
      value:
        '```kestrel\n(String) -> Int\n```\n---\nConverts a decimal string to an integer.',
    });

    typeSpy.mockRestore();
    docSpy.mockRestore();
  });
});
