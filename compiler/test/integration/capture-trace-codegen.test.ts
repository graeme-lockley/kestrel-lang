import { describe, it, expect } from 'vitest';
import { compile, emitKbc } from '../../src/index.js';

describe('__capture_trace bytecode', () => {
  it('emits CALL with fn_id 0xFFFFFF27', () => {
    const src = 'val _ = __capture_trace(42)';
    const r = compile(src, { sourceFile: 'T.ks' });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const kbc = emitKbc(r.ast, { sourceFile: 'T.ks' });
    let found = false;
    for (let i = 0; i + 4 <= kbc.length; i++) {
      if (kbc[i] === 0x27 && kbc[i + 1] === 0xff && kbc[i + 2] === 0xff && kbc[i + 3] === 0xff) {
        found = true;
        break;
      }
    }
    expect(found).toBe(true);
  });
});
