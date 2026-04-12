import { describe, expect, it } from 'vitest';

import { collectTestCodeLenses } from '../../src/server/providers/codeLens';

describe('collectTestCodeLenses', () => {
  it('creates run/debug lenses for each test call', () => {
    const source = [
      'test("adds", () => 1)',
      'val x = 1',
      'test("multiplies", () => 2)',
      '',
    ].join('\n');

    const lenses = collectTestCodeLenses('file:///tmp/sample.ks', source);
    expect(lenses).toHaveLength(4);
    expect(lenses[0]?.command?.command).toBe('kestrel.runTest');
    expect(lenses[1]?.command?.command).toBe('kestrel.debugTest');
    expect(lenses[0]?.command?.arguments?.[0]).toBe('adds');
    expect(lenses[2]?.command?.arguments?.[0]).toBe('multiplies');
  });

  it('ignores non-test calls', () => {
    const source = 'println("hello")\n';
    const lenses = collectTestCodeLenses('file:///tmp/sample.ks', source);
    expect(lenses).toHaveLength(0);
  });
});
