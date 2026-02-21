import { describe, it, expect } from 'vitest';
import { writeTypesFile, readTypesFile, isTypesFileFresh } from '../../src/types-file.js';
import { writeFileSync, mkdirSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';

describe('types-file', () => {
  const dir = join(tmpdir(), `kestrel-types-file-${Date.now()}`);

  it('writes and reads types file with function exports', () => {
    mkdirSync(dir, { recursive: true });
    const path = join(dir, 'pkg.kti');
    const exports = new Map<string, { function_index: number; arity: number; type: import('../../src/types/internal.js').InternalType }>();
    exports.set('length', {
      function_index: 0,
      arity: 1,
      type: { kind: 'arrow', params: [{ kind: 'prim', name: 'String' }], return: { kind: 'prim', name: 'Int' } },
    });
    writeTypesFile(path, exports);
    const read = readTypesFile(path);
    expect(read.size).toBe(1);
    const lengthExport = read.get('length');
    expect(lengthExport).toBeDefined();
    expect(lengthExport?.kind).toBe('function');
    expect(lengthExport?.function_index).toBe(0);
    expect(lengthExport?.arity).toBe(1);
    expect(lengthExport?.type.kind).toBe('arrow');
    if (lengthExport?.type.kind === 'arrow') {
      expect(lengthExport.type.return.kind).toBe('prim');
    }
    rmSync(dir, { recursive: true, force: true });
  });

  it('isTypesFileFresh returns true when .kti is newer than .ks', () => {
    mkdirSync(dir, { recursive: true });
    const ktiPath = join(dir, 'x.kti');
    const ksPath = join(dir, 'x.ks');
    writeFileSync(ksPath, 'export fun f(): Int = 1');
    writeTypesFile(ktiPath, new Map());
    expect(isTypesFileFresh(ktiPath, ksPath)).toBe(true);
    rmSync(dir, { recursive: true, force: true });
  });
});
