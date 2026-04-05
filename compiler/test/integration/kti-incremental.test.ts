/**
 * Integration tests for .kti-based incremental compilation.
 *
 * Tests that:
 * 1. A second build on an unchanged project skips recompiling leaf packages
 *    (they are loaded from .kti instead).
 * 2. Modifying a dep source triggers recompile of that dep and its dependents.
 * 3. A corrupt .kti file is silently ignored and triggers a full recompile.
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdirSync, writeFileSync, readFileSync, rmSync, readdirSync } from 'fs';
import { join } from 'path';
import { fileURLToPath } from 'node:url';
import { compileFileJvm } from '../../src/compile-file-jvm.js';

const compilerRoot = fileURLToPath(new URL('../..', import.meta.url));
const kestrelRoot = join(compilerRoot, '..');
const stdlibDir = join(kestrelRoot, 'stdlib');
// ---------------------------------------------------------------------------

const leafSrc = `
export fun double(x: Int): Int = x + x
`;

const mainSrc = `
import { double } from "./leaf.ks"

val result = double(5)
`;

// ---------------------------------------------------------------------------
// Setup helpers
// ---------------------------------------------------------------------------

function makeProject(tmpDir: string) {
  mkdirSync(tmpDir, { recursive: true });
  const leafPath = join(tmpDir, 'leaf.ks');
  const mainPath = join(tmpDir, 'main.ks');
  writeFileSync(leafPath, leafSrc.trim());
  writeFileSync(mainPath, mainSrc.trim());
  return { leafPath, mainPath };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('kti incremental compilation', () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = join(compilerRoot, 'test', 'integration', '_tmp_kti_incr_' + Date.now());
    mkdirSync(tmpDir, { recursive: true });
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('second build does not recompile leaf when source is unchanged', () => {
    const { mainPath } = makeProject(tmpDir);

    // First build
    const compiled1: string[] = [];
    const out1 = compileFileJvm(mainPath, {
      projectRoot: kestrelRoot,
      stdlibDir,
      getClassOutputDir: () => tmpDir,
      onCompilingFile: (p) => compiled1.push(p),
    });
    expect(out1.ok).toBe(true);

    // Second build — leaf.ks should be loaded from .kti
    const compiled2: string[] = [];
    const out2 = compileFileJvm(mainPath, {
      projectRoot: kestrelRoot,
      stdlibDir,
      getClassOutputDir: () => tmpDir,
      onCompilingFile: (p) => compiled2.push(p),
    });
    expect(out2.ok).toBe(true);

    // leaf.ks must NOT appear in second build's compiled list
    const leafPath = join(tmpDir, '..', 'leaf.ks'); // absolute path stored by compileOne
    const leafRecompiled = compiled2.some((p) => p.includes('leaf.ks'));
    expect(leafRecompiled, 'leaf.ks should be loaded from .kti on second build').toBe(false);
  });

  it('.kti file exists after first build', () => {
    const { mainPath } = makeProject(tmpDir);

    const out = compileFileJvm(mainPath, {
      projectRoot: kestrelRoot,
      stdlibDir,
      getClassOutputDir: () => tmpDir,
    });
    expect(out.ok).toBe(true);

    // Find any .kti files in tmpDir (they may be in path-based subdirectories)
    const allFiles = readdirSync(tmpDir, { recursive: true }) as string[];
    const ktiFiles = allFiles.filter((f) => String(f).endsWith('.kti'));
    expect(ktiFiles.length).toBeGreaterThan(0);

    // Each .kti should parse as version 4
    for (const f of ktiFiles) {
      const content = JSON.parse(readFileSync(join(tmpDir, String(f)), 'utf-8'));
      expect(content.version).toBe(4);
      expect(typeof content.sourceHash).toBe('string');
      expect(content.sourceHash).toHaveLength(64);
    }
  });

  it('modifying a dep triggers recompile of dep and dependent', () => {
    const { mainPath, leafPath } = makeProject(tmpDir);

    // First build
    const out1 = compileFileJvm(mainPath, {
      projectRoot: kestrelRoot,
      stdlibDir,
      getClassOutputDir: () => tmpDir,
    });
    if (!out1.ok) throw new Error('Build 1 failed: ' + out1.diagnostics.map((d) => d.message).join('\n'));
    expect(out1.ok).toBe(true);
    writeFileSync(leafPath, leafSrc.trim() + '\n// changed\n');

    // Second build — leaf and main must both be recompiled
    const compiled2: string[] = [];
    const out2 = compileFileJvm(mainPath, {
      projectRoot: kestrelRoot,
      stdlibDir,
      getClassOutputDir: () => tmpDir,
      onCompilingFile: (p) => compiled2.push(p),
    });
    expect(out2.ok).toBe(true);

    const leafRecompiled = compiled2.some((p) => p.includes('leaf.ks'));
    expect(leafRecompiled, 'leaf.ks must be recompiled when its source changes').toBe(true);
    const mainRecompiled = compiled2.some((p) => p.includes('main.ks'));
    expect(mainRecompiled, 'main.ks must be recompiled when its dep changes').toBe(true);
  });

  it('corrupt .kti triggers a successful full recompile (failsafe)', () => {
    const { mainPath } = makeProject(tmpDir);

    // First build
    const out1 = compileFileJvm(mainPath, {
      projectRoot: kestrelRoot,
      stdlibDir,
      getClassOutputDir: () => tmpDir,
    });
    expect(out1.ok).toBe(true);

    // Corrupt all .kti files
    for (const f of readdirSync(tmpDir).filter((f) => f.endsWith('.kti'))) {
      writeFileSync(join(tmpDir, f), '{ this is garbage }');
    }

    // Second build should still succeed
    const out2 = compileFileJvm(mainPath, {
      projectRoot: kestrelRoot,
      stdlibDir,
      getClassOutputDir: () => tmpDir,
    });
    expect(out2.ok).toBe(true);
  });
});
