/**
 * Re-exports and export-set conflicts (07 §3.2–§3.4).
 */
import { describe, it, expect } from 'vitest';
import { compileFile } from '../../src/compile-file.js';
import { join } from 'path';
import { mkdirSync, writeFileSync, rmSync, utimesSync, statSync } from 'fs';
import { tmpdir } from 'os';
import { CODES } from '../../src/diagnostics/types.js';

describe('re-export conflicts and merging', () => {
  const mkOut = () => join(tmpdir(), `kestrel-reexport-${Date.now()}-${Math.random().toString(36).slice(2)}`);

  it('conflict: two export * both export the same name', () => {
    const outDir = mkOut();
    mkdirSync(outDir, { recursive: true });
    writeFileSync(join(outDir, 'a.ks'), 'export fun foo(): Int = 1\n');
    writeFileSync(join(outDir, 'b.ks'), 'export fun foo(): Int = 2\n');
    writeFileSync(
      join(outDir, 'barrel.ks'),
      'export * from "./a.ks"\nexport * from "./b.ks"\n'
    );
    const r = compileFile(join(outDir, 'barrel.ks'), { projectRoot: outDir });
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.diagnostics.some((d) => d.code === CODES.export.reexport_conflict)).toBe(true);
      expect(r.diagnostics.some((d) => d.message.includes('foo'))).toBe(true);
    }
    rmSync(outDir, { recursive: true, force: true });
  });

  it('conflict: export * overlaps export { } from another specifier', () => {
    const outDir = mkOut();
    mkdirSync(outDir, { recursive: true });
    writeFileSync(join(outDir, 'a.ks'), 'export fun foo(): Int = 1\n');
    writeFileSync(join(outDir, 'b.ks'), 'export fun bar(): Int = 2\n');
    writeFileSync(
      join(outDir, 'barrel.ks'),
      'export * from "./a.ks"\nexport { bar as foo } from "./b.ks"\n'
    );
    const r = compileFile(join(outDir, 'barrel.ks'), { projectRoot: outDir });
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.diagnostics.some((d) => d.code === CODES.export.reexport_conflict)).toBe(true);
    }
    rmSync(outDir, { recursive: true, force: true });
  });

  it('conflict: local export and re-export same name', () => {
    const outDir = mkOut();
    mkdirSync(outDir, { recursive: true });
    writeFileSync(join(outDir, 'a.ks'), 'export fun foo(): Int = 1\n');
    writeFileSync(
      join(outDir, 'barrel.ks'),
      'export fun foo(): Int = 2\nexport * from "./a.ks"\n'
    );
    const r = compileFile(join(outDir, 'barrel.ks'), { projectRoot: outDir });
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.diagnostics.some((d) => d.code === CODES.export.reexport_conflict)).toBe(true);
    }
    rmSync(outDir, { recursive: true, force: true });
  });

  it('no conflict: export * and export { x } from the same specifier', () => {
    const outDir = mkOut();
    mkdirSync(outDir, { recursive: true });
    writeFileSync(join(outDir, 'm.ks'), 'export fun x(): Int = 1\nexport fun y(): Int = 2\n');
    writeFileSync(
      join(outDir, 'barrel.ks'),
      'export * from "./m.ks"\nexport { x } from "./m.ks"\n'
    );
    const getOutputPaths = (p: string) => {
      const base = p.replace(/\.ks$/, '');
      return { kbc: base + '.kbc', kti: base + '.kti' };
    };
    const r = compileFile(join(outDir, 'barrel.ks'), { projectRoot: outDir, getOutputPaths });
    expect(r.ok).toBe(true);
    rmSync(outDir, { recursive: true, force: true });
  });

  it('rename resolves conflict: foo as fooA and foo as fooB', () => {
    const outDir = mkOut();
    mkdirSync(outDir, { recursive: true });
    writeFileSync(join(outDir, 'a.ks'), 'export fun foo(): Int = 1\n');
    writeFileSync(join(outDir, 'b.ks'), 'export fun foo(): Int = 2\n');
    writeFileSync(
      join(outDir, 'barrel.ks'),
      'export { foo as fooA } from "./a.ks"\nexport { foo as fooB } from "./b.ks"\n'
    );
    writeFileSync(
      join(outDir, 'main.ks'),
      'import { fooA, fooB } from "./barrel.ks"\nexport fun run(): Int = fooA() + fooB()\n'
    );
    const r = compileFile(join(outDir, 'main.ks'), { projectRoot: outDir });
    expect(r.ok).toBe(true);
    rmSync(outDir, { recursive: true, force: true });
  });

  it('invalid external name in export { … } from', () => {
    const outDir = mkOut();
    mkdirSync(outDir, { recursive: true });
    writeFileSync(join(outDir, 'm.ks'), 'export fun x(): Int = 1\n');
    writeFileSync(join(outDir, 'barrel.ks'), 'export { notThere } from "./m.ks"\n');
    const r = compileFile(join(outDir, 'barrel.ks'), { projectRoot: outDir });
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.diagnostics.some((d) => d.code === CODES.export.not_exported)).toBe(true);
    }
    rmSync(outDir, { recursive: true, force: true });
  });

  it('transitive export *: importer sees symbol defined in leaf module', () => {
    const outDir = mkOut();
    mkdirSync(outDir, { recursive: true });
    writeFileSync(join(outDir, 'c.ks'), 'export fun leaf(): Int = 42\n');
    writeFileSync(join(outDir, 'b.ks'), 'export * from "./c.ks"\n');
    writeFileSync(join(outDir, 'a.ks'), 'export * from "./b.ks"\n');
    writeFileSync(
      join(outDir, 'main.ks'),
      'import { leaf } from "./a.ks"\nexport fun run(): Int = leaf()\n'
    );
    const r = compileFile(join(outDir, 'main.ks'), { projectRoot: outDir });
    expect(r.ok).toBe(true);
    rmSync(outDir, { recursive: true, force: true });
  });

  it('re-export opaque type, exported ADT, and val (namespace + type sanity)', () => {
    const outDir = mkOut();
    mkdirSync(outDir, { recursive: true });
    writeFileSync(
      join(outDir, 'lib.ks'),
      `opaque type OpaqueT = Int
export type Color = Red | Green(Int)
export val exportedVal: Int = 7
`
    );
    writeFileSync(join(outDir, 'barrel.ks'), 'export * from "./lib.ks"\n');
    writeFileSync(
      join(outDir, 'main.ks'),
      `import * as B from "./barrel.ks"
export fun run(): Int = B.exportedVal
`
    );
    const r = compileFile(join(outDir, 'main.ks'), { projectRoot: outDir });
    expect(r.ok).toBe(true);
    rmSync(outDir, { recursive: true, force: true });
  });

  it('barrel .kti-only: downstream typechecks using fresh barrel .kti', () => {
    const outDir = mkOut();
    mkdirSync(outDir, { recursive: true });
    writeFileSync(join(outDir, 'lib.ks'), 'export fun f(): Int = 99\n');
    writeFileSync(join(outDir, 'barrel.ks'), 'export * from "./lib.ks"\n');
    const getOutputPaths = (sourcePath: string) => {
      const base = sourcePath.replace(/\.ks$/, '');
      return { kbc: base + '.kbc', kti: base + '.kti' };
    };
    const barrelPath = join(outDir, 'barrel.ks');
    const libPath = join(outDir, 'lib.ks');
    const br = compileFile(barrelPath, { projectRoot: outDir, getOutputPaths });
    expect(br.ok).toBe(true);
    writeFileSync(libPath, '<<< invalid');
    const future = new Date(Date.now() + 120_000);
    const past = new Date(Date.now() - 120_000);
    utimesSync(barrelPath.replace(/\.ks$/, '.kti'), future, future);
    utimesSync(barrelPath.replace(/\.ks$/, '.kbc'), future, future);
    utimesSync(libPath, past, past);
    expect(statSync(barrelPath.replace(/\.ks$/, '.kti')).mtimeMs >= statSync(libPath).mtimeMs).toBe(true);
    writeFileSync(
      join(outDir, 'consumer.ks'),
      'import { f } from "./barrel.ks"\nexport fun run(): Int = f()\n'
    );
    const cr = compileFile(join(outDir, 'consumer.ks'), { projectRoot: outDir, getOutputPaths });
    expect(cr.ok).toBe(true);
    rmSync(outDir, { recursive: true, force: true });
  });

  it('resolves re-export-only specifier without import declaration', () => {
    const outDir = mkOut();
    mkdirSync(outDir, { recursive: true });
    writeFileSync(join(outDir, 'lib.ks'), 'export fun g(): Int = 3\n');
    writeFileSync(join(outDir, 'only_re.ks'), 'export * from "./lib.ks"\n');
    const r = compileFile(join(outDir, 'only_re.ks'), { projectRoot: outDir });
    expect(r.ok).toBe(true);
    rmSync(outDir, { recursive: true, force: true });
  });
});
