import { describe, expect, it } from 'vitest';

import { printType } from '../../src/types/print.js';
import { tBool, tInt } from '../../src/types/internal.js';

describe('printType', () => {
  it('prints primitive types', () => {
    expect(printType(tInt)).toBe('Int');
    expect(printType(tBool)).toBe('Bool');
  });

  it('prints arrow and app types', () => {
    const t = {
      kind: 'arrow' as const,
      params: [{ kind: 'app' as const, name: 'Option', args: [tInt] }],
      return: tBool,
    };
    expect(printType(t)).toBe('(Option<Int>) -> Bool');
  });

  it('prints tuple and record types', () => {
    const tuple = { kind: 'tuple' as const, elements: [tInt, tBool] };
    const record = {
      kind: 'record' as const,
      fields: [{ name: 'value', mut: false, type: tuple }],
    };
    expect(printType(record)).toBe('{ value: (Int, Bool) }');
  });

  it('prints schemes without quantifier syntax', () => {
    const scheme = {
      kind: 'scheme' as const,
      vars: [0],
      body: {
        kind: 'arrow' as const,
        params: [{ kind: 'var' as const, id: 0 }],
        return: { kind: 'var' as const, id: 0 },
      },
    };
    expect(printType(scheme)).toBe("('a) -> 'a");
  });
});
