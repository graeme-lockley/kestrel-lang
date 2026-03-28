import { describe, it, expect } from 'vitest';
import { compileFile } from '../../src/compile-file.js';
import { resolve } from 'path';
import { readFileSync, writeFileSync, mkdirSync, rmSync, utimesSync, statSync } from 'fs';
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

  it('compiles program with namespace import and emits imported function table', () => {
    const outDir = join(tmpdir(), `kestrel-namespace-${Date.now()}`);
    mkdirSync(outDir, { recursive: true });
    const mainPath = join(outDir, 'main.ks');
    const root = resolve(process.cwd(), '..');
    const source = `import * as Str from "kestrel:string"
val x = Str.length("hi")`;
    writeFileSync(mainPath, source);
    const getOutputPaths = (sourcePath: string) => {
      const base = sourcePath.replace(/\.ks$/, '');
      return { kbc: base + '.kbc', kti: base + '.kti' };
    };
    const compileOpts = { projectRoot: root, getOutputPaths };
    const result = compileFile(mainPath, compileOpts);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.kbc.length).toBeGreaterThan(0);
    const imported = readImportedFunctionTable(result.kbc);
    expect(imported.length).toBeGreaterThanOrEqual(1);
    rmSync(outDir, { recursive: true, force: true });
  });

  it('namespace-qualified exported ADT constructor compiles (CONSTRUCT_IMPORT path)', () => {
    const outDir = join(tmpdir(), `kestrel-ns-ctor-${Date.now()}`);
    mkdirSync(outDir, { recursive: true });
    const rootProj = resolve(process.cwd(), '..');
    const libSrc = readFileSync(join(rootProj, 'tests/fixtures/opaque_pkg/lib.ks'), 'utf-8');
    writeFileSync(join(outDir, 'lib.ks'), libSrc);
    const importerPath = join(outDir, 'importer.ks');
    writeFileSync(
      importerPath,
      `import * as Lib from "./lib.ks"
export fun run(): Int = Lib.publicTokenToInt(Lib.PubNum(9))`
    );
    const getOutputPaths = (sourcePath: string) => {
      const base = sourcePath.replace(/\.ks$/, '');
      return { kbc: base + '.kbc', kti: base + '.kti' };
    };
    const r = compileFile(importerPath, { projectRoot: outDir, getOutputPaths });
    expect(r.ok).toBe(true);
    rmSync(outDir, { recursive: true, force: true });
  });

  it('namespace constructor: importer compiles when dependency is .kti-only (stale .ks ignored)', () => {
    const outDir = join(tmpdir(), `kestrel-ns-kti-${Date.now()}`);
    mkdirSync(outDir, { recursive: true });
    const rootProj = resolve(process.cwd(), '..');
    const libPath = join(outDir, 'lib.ks');
    const libSrc = readFileSync(join(rootProj, 'tests/fixtures/opaque_pkg/lib.ks'), 'utf-8');
    writeFileSync(libPath, libSrc);
    const getOutputPaths = (sourcePath: string) => {
      const base = sourcePath.replace(/\.ks$/, '');
      return { kbc: base + '.kbc', kti: base + '.kti' };
    };
    const libCompile = compileFile(libPath, { projectRoot: outDir, getOutputPaths });
    expect(libCompile.ok).toBe(true);
    writeFileSync(libPath, 'this is not valid kestrel source {{{');
    const ktiPath = libPath.replace(/\.ks$/, '.kti');
    const kbcPath = libPath.replace(/\.ks$/, '.kbc');
    const future = new Date(Date.now() + 120_000);
    const past = new Date(Date.now() - 120_000);
    utimesSync(ktiPath, future, future);
    utimesSync(kbcPath, future, future);
    utimesSync(libPath, past, past);
    expect(statSync(ktiPath).mtimeMs >= statSync(libPath).mtimeMs).toBe(true);
    const importerPath = join(outDir, 'importer.ks');
    writeFileSync(
      importerPath,
      `import * as Lib from "./lib.ks"
export fun run(): Int = Lib.publicTokenToInt(Lib.PubPair(2, 3))`
    );
    const r = compileFile(importerPath, { projectRoot: outDir, getOutputPaths });
    expect(r.ok).toBe(true);
    rmSync(outDir, { recursive: true, force: true });
  });

  it('rejects opaque ADT constructor through namespace', () => {
    const outDir = join(tmpdir(), `kestrel-ns-opaque-ctor-${Date.now()}`);
    mkdirSync(outDir, { recursive: true });
    const rootProj = resolve(process.cwd(), '..');
    writeFileSync(join(outDir, 'lib.ks'), readFileSync(join(rootProj, 'tests/fixtures/opaque_pkg/lib.ks'), 'utf-8'));
    const mainPath = join(outDir, 'main.ks');
    writeFileSync(mainPath, `import * as Lib from "./lib.ks"\nval _ = Lib.SecNum(1)`);
    const r = compileFile(mainPath, { projectRoot: outDir });
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.diagnostics.some((d) => d.message.includes('does not export') || d.message.includes('SecNum'))).toBe(true);
    }
    rmSync(outDir, { recursive: true, force: true });
  });

  it('rejects unknown namespace constructor name', () => {
    const outDir = join(tmpdir(), `kestrel-ns-bad-ctor-${Date.now()}`);
    mkdirSync(outDir, { recursive: true });
    const rootProj = resolve(process.cwd(), '..');
    writeFileSync(join(outDir, 'lib.ks'), readFileSync(join(rootProj, 'tests/fixtures/opaque_pkg/lib.ks'), 'utf-8'));
    const mainPath = join(outDir, 'main.ks');
    writeFileSync(mainPath, `import * as Lib from "./lib.ks"\nval _ = Lib.NotARealCtor(1)`);
    const r = compileFile(mainPath, { projectRoot: outDir });
    expect(r.ok).toBe(false);
    rmSync(outDir, { recursive: true, force: true });
  });

  it('type error on wrong arity for namespace constructor', () => {
    const outDir = join(tmpdir(), `kestrel-ns-arity-${Date.now()}`);
    mkdirSync(outDir, { recursive: true });
    const rootProj = resolve(process.cwd(), '..');
    writeFileSync(join(outDir, 'lib.ks'), readFileSync(join(rootProj, 'tests/fixtures/opaque_pkg/lib.ks'), 'utf-8'));
    const mainPath = join(outDir, 'main.ks');
    writeFileSync(mainPath, `import * as Lib from "./lib.ks"\nval _ = Lib.PubNum()`);
    const r = compileFile(mainPath, { projectRoot: outDir });
    expect(r.ok).toBe(false);
    rmSync(outDir, { recursive: true, force: true });
  });

  it('type error on wrong argument type for namespace constructor', () => {
    const outDir = join(tmpdir(), `kestrel-ns-argty-${Date.now()}`);
    mkdirSync(outDir, { recursive: true });
    const rootProj = resolve(process.cwd(), '..');
    writeFileSync(join(outDir, 'lib.ks'), readFileSync(join(rootProj, 'tests/fixtures/opaque_pkg/lib.ks'), 'utf-8'));
    const mainPath = join(outDir, 'main.ks');
    writeFileSync(mainPath, `import * as Lib from "./lib.ks"\nval _ = Lib.PubNum("hi")`);
    const r = compileFile(mainPath, { projectRoot: outDir });
    expect(r.ok).toBe(false);
    rmSync(outDir, { recursive: true, force: true });
  });

  it('reports type error when accessing nonexistent member on namespace', () => {
    const outDir = join(tmpdir(), `kestrel-namespace-err-${Date.now()}`);
    mkdirSync(outDir, { recursive: true });
    const mainPath = join(outDir, 'main.ks');
    const root = resolve(process.cwd(), '..');
    const source = `import * as Str from "kestrel:string"
val x = Str.nonexistent`;
    writeFileSync(mainPath, source);
    const getOutputPaths = (sourcePath: string) => {
      const base = sourcePath.replace(/\.ks$/, '');
      return { kbc: base + '.kbc', kti: base + '.kti' };
    };
    const compileOpts = { projectRoot: root, getOutputPaths };
    const result = compileFile(mainPath, compileOpts);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.diagnostics.some((d) => d.message.includes('does not export') || d.message.includes('nonexistent'))).toBe(true);
    }
    rmSync(outDir, { recursive: true, force: true });
  });
});
