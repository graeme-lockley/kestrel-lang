import { describe, it, expect } from 'vitest';
import { writeTypesFile, readTypesFile, isTypesFileFresh } from '../../src/types-file.js';
import type { TypesFileExportInput } from '../../src/types-file.js';
import type { InternalType } from '../../src/types/internal.js';
import { writeFileSync, mkdirSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';

/** Recursive structural equality for InternalType (var ids may differ after deserialize). */
function typeStructureEqual(a: InternalType, b: InternalType): boolean {
  if (a.kind !== b.kind) return false;
  switch (a.kind) {
    case 'var':
      return b.kind === 'var' && typeof (b as { id: number }).id === 'number';
    case 'prim':
      return b.kind === 'prim' && a.name === b.name;
    case 'arrow':
      if (b.kind !== 'arrow') return false;
      if (a.params.length !== b.params.length) return false;
      if (!typeStructureEqual(a.return, b.return)) return false;
      return a.params.every((p, i) => typeStructureEqual(p, b.params[i]!));
    case 'record':
      if (b.kind !== 'record') return false;
      if (a.fields.length !== b.fields.length) return false;
      if (!!a.row !== !!b.row) return false;
      if (a.row && b.row && !typeStructureEqual(a.row, b.row)) return false;
      return a.fields.every((f, i) => {
        const g = b.fields[i]!;
        return f.name === g.name && f.mut === g.mut && typeStructureEqual(f.type, g.type);
      });
    case 'app':
      return b.kind === 'app' && a.name === b.name && a.args.length === b.args.length &&
        a.args.every((x, i) => typeStructureEqual(x, b.args[i]!));
    case 'tuple':
      return b.kind === 'tuple' && a.elements.length === b.elements.length &&
        a.elements.every((x, i) => typeStructureEqual(x, b.elements[i]!));
    case 'union':
      return b.kind === 'union' && typeStructureEqual(a.left, b.left) && typeStructureEqual(a.right, b.right);
    case 'inter':
      return b.kind === 'inter' && typeStructureEqual(a.left, b.left) && typeStructureEqual(a.right, b.right);
    case 'scheme':
      if (b.kind !== 'scheme') return false;
      return a.vars.length === b.vars.length && typeStructureEqual(a.body, b.body);
    default:
      return false;
  }
}

describe('types-file', () => {
  const dir = join(tmpdir(), `kestrel-types-file-${Date.now()}`);

  it('writes and reads types file with function exports', () => {
    mkdirSync(dir, { recursive: true });
    const path = join(dir, 'pkg.kti');
    const exports = new Map<string, TypesFileExportInput>();
    exports.set('length', {
      kind: 'function',
      function_index: 0,
      arity: 1,
      type: { kind: 'arrow', params: [{ kind: 'prim', name: 'String' }], return: { kind: 'prim', name: 'Int' } },
    });
    writeTypesFile(path, exports);
    const read = readTypesFile(path);
    expect(read.exports.size).toBe(1);
    const lengthExport = read.exports.get('length');
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

  it('round-trips all export kinds and type alias exports', () => {
    mkdirSync(dir, { recursive: true });
    const path = join(dir, 'roundtrip.kti');
    const intPrim = { kind: 'prim' as const, name: 'Int' as const };
    const strPrim = { kind: 'prim' as const, name: 'String' as const };
    const exports = new Map<string, TypesFileExportInput>();
    exports.set('fn', {
      kind: 'function',
      function_index: 0,
      arity: 2,
      type: { kind: 'arrow', params: [intPrim, strPrim], return: intPrim },
    });
    exports.set('val', {
      kind: 'val',
      function_index: 1,
      type: strPrim,
    });
    exports.set('myVar', {
      kind: 'var',
      function_index: 2,
      setter_index: 3,
      type: intPrim,
    });
    const typeAliasExports = new Map<string, InternalType>();
    typeAliasExports.set('MyAlias', { kind: 'app', name: 'Option', args: [intPrim] });
    typeAliasExports.set('OpaqueType', { kind: 'prim', name: 'Unit' });
    const typeVisibility = new Map<string, 'local' | 'opaque' | 'export'>();
    typeVisibility.set('MyAlias', 'export');
    typeVisibility.set('OpaqueType', 'opaque');

    writeTypesFile(path, exports, typeAliasExports, typeVisibility);
    const read = readTypesFile(path);

    expect(read.exports.size).toBe(3);
    const fnExp = read.exports.get('fn');
    expect(fnExp?.kind).toBe('function');
    expect(fnExp?.function_index).toBe(0);
    expect(fnExp?.arity).toBe(2);
    expect(typeStructureEqual(fnExp!.type, exports.get('fn')!.type)).toBe(true);

    const valExp = read.exports.get('val');
    expect(valExp?.kind).toBe('val');
    expect(valExp?.function_index).toBe(1);
    expect(valExp?.arity).toBe(0);
    expect(typeStructureEqual(valExp!.type, strPrim)).toBe(true);

    const varExp = read.exports.get('myVar');
    expect(varExp?.kind).toBe('var');
    expect(varExp?.function_index).toBe(2);
    expect(varExp?.setter_index).toBe(3);
    expect(varExp?.arity).toBe(0);
    expect(typeStructureEqual(varExp!.type, intPrim)).toBe(true);

    expect(read.typeAliases.size).toBe(2);
    const aliasExp = read.typeAliases.get('MyAlias');
    expect(aliasExp?.kind).toBe('type');
    expect(aliasExp?.opaque).toBe(false);
    expect(typeStructureEqual(aliasExp!.type, typeAliasExports.get('MyAlias')!)).toBe(true);
    const opaqueExp = read.typeAliases.get('OpaqueType');
    expect(opaqueExp?.kind).toBe('type');
    expect(opaqueExp?.opaque).toBe(true);

    rmSync(dir, { recursive: true, force: true });
  });

  it('round-trips all InternalType forms (union, inter, record with row, scheme, app, tuple)', () => {
    mkdirSync(dir, { recursive: true });
    const path = join(dir, 'types.kti');
    const complexType: InternalType = {
      kind: 'scheme',
      vars: [0, 1],
      body: {
        kind: 'arrow',
        params: [
          {
            kind: 'union',
            left: { kind: 'prim', name: 'Int' },
            right: { kind: 'prim', name: 'String' },
          },
          {
            kind: 'record',
            fields: [{ name: 'x', mut: false, type: { kind: 'prim', name: 'Int' } }],
            row: { kind: 'var', id: 0 },
          },
        ],
        return: {
          kind: 'inter',
          left: { kind: 'app', name: 'Option', args: [{ kind: 'var', id: 1 }] },
          right: { kind: 'tuple', elements: [{ kind: 'prim', name: 'Bool' }, { kind: 'prim', name: 'Unit' }] },
        },
      },
    };
    const exports = new Map<string, TypesFileExportInput>();
    exports.set('complex', { kind: 'function', function_index: 0, arity: 2, type: complexType });
    writeTypesFile(path, exports);
    const read = readTypesFile(path);
    expect(read.exports.size).toBe(1);
    const exp = read.exports.get('complex');
    expect(exp).toBeDefined();
    expect(exp?.type.kind).toBe('scheme');
    if (exp?.type.kind === 'scheme') {
      expect(exp.type.vars.length).toBe(2);
      expect(exp.type.body.kind).toBe('arrow');
      if (exp.type.body.kind === 'arrow') {
        expect(exp.type.body.params.length).toBe(2);
        expect(exp.type.body.params[0]!.kind).toBe('union');
        expect(exp.type.body.params[1]!.kind).toBe('record');
        const rec = exp.type.body.params[1]!;
        if (rec.kind === 'record') {
          expect(rec.fields.length).toBe(1);
          expect(rec.row?.kind).toBe('var');
        }
        expect(exp.type.body.return.kind).toBe('inter');
      }
    }
    expect(typeStructureEqual(exp!.type, complexType)).toBe(true);
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
