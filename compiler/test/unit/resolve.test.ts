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

  it('resolves relative path ./other.ks', () => {
    const fromFile = resolve(projectRoot, 'tests/e2e/scenarios/two_module.ks');
    const r = resolveSpecifier('./lib_double.ks', { fromFile, stdlibDir });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.path).toContain('lib_double.ks');
    }
  });

  it('rejects unknown stdlib specifier', () => {
    const fromFile = resolve(projectRoot, 'main.ks');
    const r = resolveSpecifier('kestrel:nonexistent', { fromFile, stdlibDir });
    expect(r.ok).toBe(false);
  });
});
