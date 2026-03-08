import { describe, it, expect } from 'vitest';
import { compileFile } from '../../src/compile-file.js';
import { resolve } from 'path';
import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';

/** Read imported function table from .kbc (03 §6.6). Matches VM load.zig section 2 parsing. */
function readImportedFunctionTable(kbc: Uint8Array): { importIndex: number; functionIndex: number }[] {
  const dv = new DataView(kbc.buffer, kbc.byteOffset, kbc.byteLength);
  if (kbc.length < 36) return [];
  const section2Start = dv.getUint32(16, true);
  let o = section2Start;
  if (o + 8 > kbc.length) return [];
  const nGlobals = dv.getUint32(o, true);
  const fnCount = dv.getUint32(o + 4, true);
  o += 8 + fnCount * 24;
  if (o + 4 > kbc.length) return [];
  const typeCount = dv.getUint32(o, true);
  o += 4;
  if (o + (typeCount + 1) * 4 > kbc.length) return [];
  const blobLen = dv.getUint32(o + typeCount * 4, true);
  o += (typeCount + 1) * 4 + blobLen;
  o = (o + 3) & ~3;
  if (o + 4 > kbc.length) return [];
  const exportedTypeCount = dv.getUint32(o, true);
  o += 4 + exportedTypeCount * 8;
  if (o + 4 > kbc.length) return [];
  const importCount = dv.getUint32(o, true);
  o += 4 + importCount * 4;
  if (o + 4 > kbc.length) return [];
  const importedFnCount = dv.getUint32(o, true);
  o += 4;
  const entries: { importIndex: number; functionIndex: number }[] = [];
  for (let i = 0; i < importedFnCount && o + 8 <= kbc.length; i++) {
    entries.push({
      importIndex: dv.getUint32(o, true),
      functionIndex: dv.getUint32(o + 4, true),
    });
    o += 8;
  }
  return entries;
}

describe('compileFile', () => {
  const root = resolve(process.cwd(), '..');
  const opts = { projectRoot: root };

  it('compiles single-file program', () => {
    const p = resolve(root, 'tests/unit/empty.ks');
    const r = compileFile(p, opts);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.kbc.length).toBeGreaterThan(0);
      expect(r.kbc[0]).toBe(0x4b); // KBC1 magic
    }
  });

  it('compiles two-module program with local import', () => {
    const p = resolve(root, 'tests/fixtures/two_module.ks');
    const r = compileFile(p, opts);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.kbc.length).toBeGreaterThan(0);
    }
  });

  it('export var: importer bytecode has getter and setter in imported function table', () => {
    const outDir = join(tmpdir(), `kestrel-export-var-${Date.now()}`);
    mkdirSync(outDir, { recursive: true });
    const pkgPath = join(outDir, 'export_var_pkg.ks');
    const importerPath = join(outDir, 'import_assign_var.ks');
    const root = resolve(process.cwd(), '..');
    const fixtureDir = resolve(root, 'tests/fixtures');
    const pkgSource = readFileSync(join(fixtureDir, 'export_var_pkg.ks'), 'utf-8');
    const importerSource = readFileSync(join(fixtureDir, 'import_assign_var.ks'), 'utf-8');
    writeFileSync(pkgPath, pkgSource);
    writeFileSync(importerPath, importerSource);

    const getOutputPaths = (sourcePath: string) => {
      const base = sourcePath.replace(/\.ks$/, '');
      return { kbc: base + '.kbc', kti: base + '.kti' };
    };
    const compileOpts = { projectRoot: outDir, getOutputPaths };
    const importerResult = compileFile(importerPath, compileOpts);
    expect(importerResult.ok).toBe(true);
    if (!importerResult.ok) return;
    const kbc = importerResult.kbc;
    const imported = readImportedFunctionTable(kbc);
    expect(imported.length).toBeGreaterThanOrEqual(2);
    const getterEntry = imported[0];
    const setterEntry = imported[1];
    expect(getterEntry).toBeDefined();
    expect(setterEntry).toBeDefined();
    expect(getterEntry!.importIndex).toBe(setterEntry!.importIndex);
    expect(getterEntry!.functionIndex).not.toBe(setterEntry!.functionIndex);
    rmSync(outDir, { recursive: true, force: true });
  });

  it('reports module not found for bad path', () => {
    const p = resolve(root, 'tests/e2e/scenarios/nonexistent.ks');
    const r = compileFile(p, opts);
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.diagnostics.some((d) => d.message.includes('Cannot read') || d.message.includes('not found'))).toBe(true);
    }
  });
});
