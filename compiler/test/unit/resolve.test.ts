import { describe, it, expect } from 'vitest';
import { resolveSpecifier } from '../../src/resolve.js';
import { resolve } from 'path';

describe('resolve', () => {
  // Project root: from compiler/ go up to repo root (where stdlib lives)
  const projectRoot = resolve(process.cwd(), '..');
  const stdlibDir = resolve(projectRoot, 'stdlib');

  it('resolves kestrel:string to stdlib path', () => {
    const fromFile = resolve(projectRoot, 'main.ks');
    const r = resolveSpecifier('kestrel:string', { fromFile, stdlibDir });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.path).toContain('stdlib');
      expect(r.path).toContain('kestrel');
      expect(r.path).toContain('string.ks');
    }
  });

  it('resolves relative path ./double_helper.ks', () => {
    const fromFile = resolve(projectRoot, 'tests/fixtures/two_module.ks');
    const r = resolveSpecifier('./double_helper.ks', { fromFile, stdlibDir });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.path).toContain('double_helper.ks');
    }
  });

  it('rejects unknown stdlib specifier', () => {
    const fromFile = resolve(projectRoot, 'main.ks');
    const r = resolveSpecifier('kestrel:nonexistent', { fromFile, stdlibDir });
    expect(r.ok).toBe(false);
  });
});
