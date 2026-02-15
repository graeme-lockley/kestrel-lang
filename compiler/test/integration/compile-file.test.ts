import { describe, it, expect } from 'vitest';
import { compileFile } from '../../src/compile-file.js';
import { resolve } from 'path';

describe('compileFile', () => {
  const root = resolve(process.cwd(), '..');

  it('compiles single-file program', () => {
    const p = resolve(root, 'tests/e2e/scenarios/empty.ks');
    const r = compileFile(p);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.kbc.length).toBeGreaterThan(0);
      expect(r.kbc[0]).toBe(0x4b); // KBC1 magic
    }
  });

  it('compiles two-module program with local import', () => {
    const p = resolve(root, 'tests/e2e/scenarios/two_module.ks');
    const r = compileFile(p);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.kbc.length).toBeGreaterThan(0);
    }
  });

  it('reports module not found for bad path', () => {
    const p = resolve(root, 'tests/e2e/scenarios/nonexistent.ks');
    const r = compileFile(p);
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.errors.some((e) => e.includes('Cannot read') || e.includes('not found'))).toBe(true);
    }
  });
});
