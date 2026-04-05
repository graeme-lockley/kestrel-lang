import { describe, it, expect } from 'vitest';
import { serializeType, deserializeType, extractCodegenMeta, buildKtiV4 } from '../../src/kti.js';
import type { InternalType } from '../../src/types/internal.js';
import type { Program } from '../../src/ast/nodes.js';

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

const pInt: InternalType = { kind: 'prim', name: 'Int' };
const pBool: InternalType = { kind: 'prim', name: 'Bool' };
const pString: InternalType = { kind: 'prim', name: 'String' };
const pUnit: InternalType = { kind: 'prim', name: 'Unit' };

function roundTrip(t: InternalType): InternalType {
  return deserializeType(serializeType(t));
}

// ---------------------------------------------------------------------------
// SerType serialization
// ---------------------------------------------------------------------------

describe('serializeType', () => {
  it('serializes prim', () => {
    expect(serializeType(pInt)).toEqual({ k: 'prim', n: 'Int' });
    expect(serializeType(pBool)).toEqual({ k: 'prim', n: 'Bool' });
  });

  it('serializes var', () => {
    expect(serializeType({ kind: 'var', id: 3 })).toEqual({ k: 'var', id: 3 });
  });

  it('serializes arrow', () => {
    const t: InternalType = { kind: 'arrow', params: [pInt, pBool], return: pString };
    const s = serializeType(t) as Record<string, unknown>;
    expect(s['k']).toBe('arrow');
    expect(s['ps']).toHaveLength(2);
    expect(s['r']).toEqual({ k: 'prim', n: 'String' });
  });

  it('serializes record (closed)', () => {
    const t: InternalType = { kind: 'record', fields: [{ name: 'x', mut: false, type: pInt }] };
    const s = serializeType(t) as Record<string, unknown>;
    expect(s['k']).toBe('record');
    expect((s['fs'] as unknown[]).length).toBe(1);
    expect(s['row']).toBeNull();
  });

  it('serializes record (with row)', () => {
    const rowVar: InternalType = { kind: 'var', id: 99 };
    const t: InternalType = { kind: 'record', fields: [], row: rowVar };
    const s = serializeType(t) as Record<string, unknown>;
    expect(s['row']).toEqual({ k: 'var', id: 99 });
  });

  it('serializes app', () => {
    const t: InternalType = { kind: 'app', name: 'List', args: [pInt] };
    const s = serializeType(t) as Record<string, unknown>;
    expect(s['k']).toBe('app');
    expect(s['n']).toBe('List');
    expect((s['as'] as unknown[]).length).toBe(1);
  });

  it('serializes tuple', () => {
    const t: InternalType = { kind: 'tuple', elements: [pInt, pBool] };
    const s = serializeType(t) as Record<string, unknown>;
    expect(s['k']).toBe('tuple');
    expect((s['es'] as unknown[]).length).toBe(2);
  });

  it('serializes union', () => {
    const t: InternalType = { kind: 'union', left: pInt, right: pBool };
    const s = serializeType(t) as Record<string, unknown>;
    expect(s['k']).toBe('union');
  });

  it('serializes inter', () => {
    const t: InternalType = { kind: 'inter', left: pInt, right: pBool };
    const s = serializeType(t) as Record<string, unknown>;
    expect(s['k']).toBe('inter');
  });

  it('serializes scheme', () => {
    const t: InternalType = {
      kind: 'scheme',
      vars: [0, 1],
      body: { kind: 'arrow', params: [{ kind: 'var', id: 0 }], return: { kind: 'var', id: 1 } },
    };
    const s = serializeType(t) as Record<string, unknown>;
    expect(s['k']).toBe('scheme');
    expect(s['vs']).toEqual([0, 1]);
  });

  it('throws for namespace type', () => {
    const t: InternalType = { kind: 'namespace', bindings: new Map() };
    expect(() => serializeType(t)).toThrow('namespace type cannot be serialized');
  });
});

// ---------------------------------------------------------------------------
// SerType deserialization round-trips
// ---------------------------------------------------------------------------

describe('deserializeType round-trips', () => {
  it('prim round-trip', () => {
    expect(roundTrip(pInt)).toEqual(pInt);
    expect(roundTrip(pUnit)).toEqual(pUnit);
  });

  it('var round-trip', () => {
    const t: InternalType = { kind: 'var', id: 7 };
    expect(roundTrip(t)).toEqual(t);
  });

  it('arrow round-trip', () => {
    const t: InternalType = { kind: 'arrow', params: [pInt], return: pBool };
    expect(roundTrip(t)).toEqual(t);
  });

  it('record (closed) round-trip', () => {
    const t: InternalType = { kind: 'record', fields: [{ name: 'x', mut: false, type: pInt }] };
    const rt = roundTrip(t) as { kind: 'record'; fields: typeof t.fields; row?: InternalType };
    expect(rt.fields).toEqual(t.fields);
    expect(rt.row).toBeUndefined();
  });

  it('record (with row) round-trip', () => {
    const rowVar: InternalType = { kind: 'var', id: 5 };
    const t: InternalType = { kind: 'record', fields: [], row: rowVar };
    const rt = roundTrip(t) as { kind: 'record'; fields: []; row?: InternalType };
    expect(rt.row).toEqual(rowVar);
  });

  it('app round-trip', () => {
    const t: InternalType = { kind: 'app', name: 'Maybe', args: [pString] };
    expect(roundTrip(t)).toEqual(t);
  });

  it('tuple round-trip', () => {
    const t: InternalType = { kind: 'tuple', elements: [pInt, pBool, pString] };
    expect(roundTrip(t)).toEqual(t);
  });

  it('union round-trip', () => {
    const t: InternalType = { kind: 'union', left: pInt, right: pBool };
    expect(roundTrip(t)).toEqual(t);
  });

  it('inter round-trip', () => {
    const t: InternalType = { kind: 'inter', left: pInt, right: pBool };
    expect(roundTrip(t)).toEqual(t);
  });

  it('scheme round-trip', () => {
    const v0: InternalType = { kind: 'var', id: 0 };
    const t: InternalType = {
      kind: 'scheme',
      vars: [0],
      body: { kind: 'app', name: 'List', args: [v0] },
    };
    expect(roundTrip(t)).toEqual(t);
  });
});

// ---------------------------------------------------------------------------
// extractCodegenMeta
// ---------------------------------------------------------------------------

function makeProgram(body: Program['body']): Program {
  return { kind: 'Program', imports: [], topLevelDecls: [], body } as unknown as Program;
}

describe('extractCodegenMeta', () => {
  it('captures exported FunDecl arities and async flags', () => {
    const prog = makeProgram([
      { kind: 'FunDecl', exported: true, async: false, name: 'add', params: [{}, {}], returnType: {}, body: {} } as unknown as Program['body'][0],
      { kind: 'FunDecl', exported: true, async: true, name: 'fetch', params: [{}], returnType: {}, body: {} } as unknown as Program['body'][0],
    ]);
    const exports = new Map<string, InternalType>([['add', pInt], ['fetch', pInt]]);
    const meta = extractCodegenMeta(prog, exports, new Map(), new Map());
    expect(meta.funArities['add']).toBe(2);
    expect(meta.funArities['fetch']).toBe(1);
    expect(meta.asyncFunNames).toContain('fetch');
    expect(meta.asyncFunNames).not.toContain('add');
  });

  it('captures VarDecl and ValDecl', () => {
    const prog = makeProgram([
      { kind: 'VarDecl', name: 'counter', type: undefined, value: {} } as unknown as Program['body'][0],
      { kind: 'ValDecl', name: 'pi', type: undefined, value: {} } as unknown as Program['body'][0],
    ]);
    const exports = new Map<string, InternalType>([['counter', pInt], ['pi', pInt]]);
    const meta = extractCodegenMeta(prog, exports, new Map(), new Map());
    expect(meta.varNames).toContain('counter');
    expect(meta.varNames).not.toContain('pi');
    expect(meta.valOrVarNames).toContain('counter');
    expect(meta.valOrVarNames).toContain('pi');
  });

  it('captures exported ADT TypeDecl constructors for non-opaque types', () => {
    const prog = makeProgram([
      {
        kind: 'TypeDecl',
        visibility: 'export',
        name: 'Color',
        body: {
          kind: 'ADTBody',
          constructors: [
            { name: 'Red', params: [] },
            { name: 'Green', params: [{}] },
          ],
        },
      } as unknown as Program['body'][0],
    ]);
    const exportedTypeAliases = new Map<string, InternalType>([['Color', { kind: 'app', name: 'Color', args: [] }]]);
    const vis = new Map([['Color', 'export' as const]]);
    const meta = extractCodegenMeta(prog, new Map(), exportedTypeAliases, vis);
    expect(meta.adtConstructors).toHaveLength(1);
    expect(meta.adtConstructors[0]?.typeName).toBe('Color');
    expect(meta.adtConstructors[0]?.constructors).toHaveLength(2);
    expect(meta.adtConstructors[0]?.constructors[1]?.params).toBe(1);
  });

  it('excludes opaque ADT from adtConstructors', () => {
    const prog = makeProgram([
      {
        kind: 'TypeDecl',
        visibility: 'opaque',
        name: 'Secret',
        body: { kind: 'ADTBody', constructors: [{ name: 'Mk', params: [] }] },
      } as unknown as Program['body'][0],
    ]);
    const exportedTypeAliases = new Map<string, InternalType>([['Secret', { kind: 'app', name: 'Secret', args: [] }]]);
    const vis = new Map([['Secret', 'opaque' as const]]);
    const meta = extractCodegenMeta(prog, new Map(), exportedTypeAliases, vis);
    expect(meta.adtConstructors).toHaveLength(0);
  });

  it('captures exported ExceptionDecl', () => {
    const prog = makeProgram([
      { kind: 'ExceptionDecl', name: 'MyError', exported: true, fields: [{}, {}] } as unknown as Program['body'][0],
    ]);
    const exports = new Map<string, InternalType>([['MyError', pUnit]]);
    const meta = extractCodegenMeta(prog, exports, new Map(), new Map());
    expect(meta.exceptionDecls).toHaveLength(1);
    expect(meta.exceptionDecls[0]?.name).toBe('MyError');
    expect(meta.exceptionDecls[0]?.arity).toBe(2);
  });

  it('skips non-exported names', () => {
    const prog = makeProgram([
      { kind: 'FunDecl', exported: false, async: false, name: 'internal', params: [{}], returnType: {}, body: {} } as unknown as Program['body'][0],
    ]);
    const exports = new Map<string, InternalType>(); // internal is NOT in exports
    const meta = extractCodegenMeta(prog, exports, new Map(), new Map());
    expect(meta.funArities['internal']).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// buildKtiV4
// ---------------------------------------------------------------------------

describe('buildKtiV4', () => {
  it('produces a version 4 KtiV4 with required fields', () => {
    const prog = makeProgram([
      { kind: 'FunDecl', exported: true, async: false, name: 'greet', params: [{}], returnType: {}, body: {} } as unknown as Program['body'][0],
    ]);
    const exports = new Map<string, InternalType>([['greet', { kind: 'arrow', params: [pString], return: pString }]]);
    const kti = buildKtiV4({
      program: prog,
      source: 'export fun greet(s: String) -> String = s',
      depPaths: [],
      depSourceHashes: new Map(),
      exports,
      exportedTypeAliases: new Map(),
      exportedConstructors: new Map(),
      exportedTypeVisibility: new Map(),
    });
    expect(kti.version).toBe(4);
    expect(typeof kti.sourceHash).toBe('string');
    expect(kti.sourceHash).toHaveLength(64);
    expect(kti.functions['greet']).toBeDefined();
    expect(kti.functions['greet']?.kind).toBe('function');
    expect(kti.codegenMeta.funArities['greet']).toBe(1);
    expect(kti.depHashes).toEqual({});
  });

  it('includes dep hashes when provided', () => {
    const prog = makeProgram([]);
    const depHashes = new Map([
      ['/abs/dep.ks', 'abc123def456789012345678901234567890123456789012345678901234567a'],
    ]);
    const kti = buildKtiV4({
      program: prog,
      source: '',
      depPaths: ['/abs/dep.ks'],
      depSourceHashes: depHashes,
      exports: new Map(),
      exportedTypeAliases: new Map(),
      exportedConstructors: new Map(),
      exportedTypeVisibility: new Map(),
    });
    expect(kti.depHashes['/abs/dep.ks']).toBe('abc123def456789012345678901234567890123456789012345678901234567a');
  });
});
