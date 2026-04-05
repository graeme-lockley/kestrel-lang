/**
 * .kti v4 types-file format: serialization, deserialization, and writer.
 *
 * Spec: docs/specs/kti-format.md
 */
import { createHash } from 'node:crypto';
import { writeFileSync } from 'fs';
import type { InternalType } from './types/internal.js';
import type { Program, FunDecl, ExternFunDecl, TypeDecl, ExceptionDecl } from './ast/nodes.js';

// ---------------------------------------------------------------------------
// KtiV4 type definitions
// ---------------------------------------------------------------------------

export interface KtiFunctionEntry {
  kind: 'function';
  function_index: number;
  arity: number;
  type: unknown;
}

export interface KtiValEntry {
  kind: 'val';
  function_index: number;
  type: unknown;
}

export interface KtiVarEntry {
  kind: 'var';
  function_index: number;
  setter_index: number;
  type: unknown;
}

export interface KtiConstructorEntry {
  kind: 'constructor';
  adt_id: number;
  ctor_index: number;
  arity: number;
  type: unknown;
}

export type KtiExportEntry = KtiFunctionEntry | KtiValEntry | KtiVarEntry | KtiConstructorEntry;

export interface KtiTypeEntry {
  visibility: 'export' | 'opaque';
  kind: 'alias' | 'adt';
  type?: unknown;
  constructors?: { name: string; params: unknown[] }[];
  typeParams?: string[];
}

export interface KtiAdtConstructorGroup {
  typeName: string;
  constructors: { name: string; params: number }[];
}

export interface KtiExceptionEntry {
  name: string;
  arity: number;
}

export interface KtiCodegenMeta {
  funArities: Record<string, number>;
  asyncFunNames: string[];
  varNames: string[];
  valOrVarNames: string[];
  adtConstructors: KtiAdtConstructorGroup[];
  exceptionDecls: KtiExceptionEntry[];
}

export interface KtiV4 {
  version: 4;
  functions: Record<string, KtiExportEntry>;
  types: Record<string, KtiTypeEntry>;
  sourceHash: string;
  depHashes: Record<string, string>;
  codegenMeta: KtiCodegenMeta;
}

// ---------------------------------------------------------------------------
// SerType serialization / deserialization
// ---------------------------------------------------------------------------

/**
 * Serialize an `InternalType` to the `SerType` JSON encoding (kti-format.md §4).
 */
export function serializeType(t: InternalType): unknown {
  switch (t.kind) {
    case 'prim':
      return { k: 'prim', n: t.name };
    case 'var':
      return { k: 'var', id: t.id };
    case 'arrow':
      return { k: 'arrow', ps: t.params.map(serializeType), r: serializeType(t.return) };
    case 'record':
      return {
        k: 'record',
        fs: t.fields.map((f) => ({ n: f.name, mut: f.mut, t: serializeType(f.type) })),
        row: t.row != null ? serializeType(t.row) : null,
      };
    case 'app':
      return { k: 'app', n: t.name, as: t.args.map(serializeType) };
    case 'tuple':
      return { k: 'tuple', es: t.elements.map(serializeType) };
    case 'union':
      return { k: 'union', l: serializeType(t.left), r: serializeType(t.right) };
    case 'inter':
      return { k: 'inter', l: serializeType(t.left), r: serializeType(t.right) };
    case 'scheme':
      return { k: 'scheme', vs: t.vars, b: serializeType(t.body) };
    case 'namespace':
      // namespace types are scope-internal and are never exported; they must
      // not appear in a .kti file.
      throw new Error('Internal error: namespace type cannot be serialized to .kti');
  }
}

/**
 * Deserialize a `SerType` JSON object back to an `InternalType`.
 * Throws on unknown or malformed input.
 */
export function deserializeType(obj: unknown): InternalType {
  if (obj == null || typeof obj !== 'object') {
    throw new Error(`Invalid SerType: expected object, got ${typeof obj}`);
  }
  const o = obj as Record<string, unknown>;
  const k = o['k'];
  switch (k) {
    case 'prim': {
      const n = o['n'];
      if (typeof n !== 'string') throw new Error(`Invalid prim SerType: missing n`);
      return { kind: 'prim', name: n as ('Int' | 'Float' | 'Bool' | 'String' | 'Unit' | 'Char' | 'Rune') };
    }
    case 'var': {
      const id = o['id'];
      if (typeof id !== 'number') throw new Error(`Invalid var SerType: missing id`);
      return { kind: 'var', id };
    }
    case 'arrow': {
      const ps = o['ps'];
      const r = o['r'];
      if (!Array.isArray(ps)) throw new Error(`Invalid arrow SerType: missing ps`);
      return {
        kind: 'arrow',
        params: ps.map(deserializeType),
        return: deserializeType(r),
      };
    }
    case 'record': {
      const fs = o['fs'];
      const row = o['row'];
      if (!Array.isArray(fs)) throw new Error(`Invalid record SerType: missing fs`);
      return {
        kind: 'record',
        fields: fs.map((f: unknown) => {
          const ff = f as Record<string, unknown>;
          return { name: ff['n'] as string, mut: ff['mut'] as boolean, type: deserializeType(ff['t']) };
        }),
        row: row != null ? deserializeType(row) : undefined,
      };
    }
    case 'app': {
      const n = o['n'];
      const as_ = o['as'];
      if (typeof n !== 'string') throw new Error(`Invalid app SerType: missing n`);
      if (!Array.isArray(as_)) throw new Error(`Invalid app SerType: missing as`);
      return { kind: 'app', name: n, args: as_.map(deserializeType) };
    }
    case 'tuple': {
      const es = o['es'];
      if (!Array.isArray(es)) throw new Error(`Invalid tuple SerType: missing es`);
      return { kind: 'tuple', elements: es.map(deserializeType) };
    }
    case 'union': {
      return { kind: 'union', left: deserializeType(o['l']), right: deserializeType(o['r']) };
    }
    case 'inter': {
      return { kind: 'inter', left: deserializeType(o['l']), right: deserializeType(o['r']) };
    }
    case 'scheme': {
      const vs = o['vs'];
      const b = o['b'];
      if (!Array.isArray(vs)) throw new Error(`Invalid scheme SerType: missing vs`);
      return { kind: 'scheme', vars: vs as number[], body: deserializeType(b) };
    }
    case 'opaque':
      // Sentinel for opaque types; return a neutral internal representation.
      return { kind: 'app', name: '__opaque__', args: [] };
    default:
      throw new Error(`Unknown SerType kind: ${String(k)}`);
  }
}

// ---------------------------------------------------------------------------
// CodegenMeta extraction
// ---------------------------------------------------------------------------

/**
 * Extract JVM codegen metadata from the compiled program and typecheck exports.
 * Only exported names (present in `exports` or `exportedTypeAliases`) are included.
 */
export function extractCodegenMeta(
  program: Program,
  exports: Map<string, InternalType>,
  exportedTypeAliases: Map<string, InternalType>,
  exportedTypeVisibility: Map<string, 'local' | 'opaque' | 'export'>
): KtiCodegenMeta {
  const funArities: Record<string, number> = {};
  const asyncFunNames: string[] = [];
  const varNames: string[] = [];
  const valOrVarNames: string[] = [];
  const adtConstructors: KtiAdtConstructorGroup[] = [];
  const exceptionDecls: KtiExceptionEntry[] = [];

  const exportedNames = new Set([...exports.keys(), ...exportedTypeAliases.keys()]);

  for (const node of program.body) {
    if (!node) continue;

    switch (node.kind) {
      case 'FunDecl': {
        const fun = node as FunDecl;
        if (!exportedNames.has(fun.name)) break;
        funArities[fun.name] = fun.params.length;
        if (fun.async) asyncFunNames.push(fun.name);
        break;
      }
      case 'ExternFunDecl': {
        const efun = node as ExternFunDecl;
        if (!exportedNames.has(efun.name)) break;
        funArities[efun.name] = efun.params.length;
        // Async if return type is AppType named 'Task'
        const rt = efun.returnType as { kind?: string; name?: string } | undefined;
        if (rt?.kind === 'AppType' && rt?.name === 'Task') asyncFunNames.push(efun.name);
        break;
      }
      case 'ValDecl': {
        const val = node as { kind: 'ValDecl'; name: string };
        if (!exportedNames.has(val.name)) break;
        valOrVarNames.push(val.name);
        break;
      }
      case 'VarDecl': {
        const varDecl = node as { kind: 'VarDecl'; name: string };
        if (!exportedNames.has(varDecl.name)) break;
        varNames.push(varDecl.name);
        valOrVarNames.push(varDecl.name);
        break;
      }
      case 'TypeDecl': {
        const tdecl = node as TypeDecl;
        // Only include non-opaque exported ADTs (opaque ones are excluded from codegenMeta.adtConstructors)
        const vis = exportedTypeVisibility.get(tdecl.name) ?? tdecl.visibility;
        if (vis === 'opaque') break;
        if (tdecl.body.kind !== 'ADTBody') break;
        adtConstructors.push({
          typeName: tdecl.name,
          constructors: tdecl.body.constructors.map((c) => ({
            name: c.name,
            params: c.params.length,
          })),
        });
        break;
      }
      case 'ExceptionDecl': {
        const exc = node as ExceptionDecl;
        if (!exc.exported) break;
        exceptionDecls.push({ name: exc.name, arity: exc.fields?.length ?? 0 });
        break;
      }
      case 'ExportDecl': {
        // Inner FunDecl/ExternFunDecl/ValDecl/VarDecl/TypeDecl/ExceptionDecl
        // wrapped in an ExportDecl are also processed at the top level since
        // they are directly in program.body after parsing wraps them.
        // No special handling needed here.
        break;
      }
    }
  }

  return { funArities, asyncFunNames, varNames, valOrVarNames, adtConstructors, exceptionDecls };
}

// ---------------------------------------------------------------------------
// KtiV4 builder
// ---------------------------------------------------------------------------

export interface BuildKtiV4Params {
  program: Program;
  source: string;
  /** Absolute paths of direct source dependencies (in dep resolution order). */
  depPaths: string[];
  /** Source hashes for deps, keyed by absolute dep path. */
  depSourceHashes: Map<string, string>;
  exports: Map<string, InternalType>;
  exportedTypeAliases: Map<string, InternalType>;
  exportedConstructors: Map<string, InternalType>;
  exportedTypeVisibility: Map<string, 'local' | 'opaque' | 'export'>;
}

/**
 * Build a KtiV4 object ready for JSON serialization and writing.
 */
export function buildKtiV4(params: BuildKtiV4Params): KtiV4 {
  const {
    program,
    source,
    depPaths,
    depSourceHashes,
    exports,
    exportedTypeAliases,
    exportedConstructors,
    exportedTypeVisibility,
  } = params;

  const sourceHash = createHash('sha256').update(source, 'utf8').digest('hex');

  const depHashes: Record<string, string> = {};
  for (const depPath of depPaths) {
    const h = depSourceHashes.get(depPath);
    if (h != null) depHashes[depPath] = h;
  }

  // Build functions map (value-level exports + constructors)
  // adt_id is assigned per-type as we encounter constructor groups
  const functions: Record<string, KtiExportEntry> = {};
  let adtIdCounter = 0;
  const adtIdByType = new Map<string, number>();

  // Exported constructors: find their adt_id and ctor_index from program body
  for (const node of program.body) {
    if (!node) continue;
    if (node.kind === 'TypeDecl' && node.body.kind === 'ADTBody') {
      const vis = exportedTypeVisibility.get(node.name) ?? node.visibility;
      if (vis === 'opaque') continue;
      const adtId = adtIdCounter++;
      adtIdByType.set(node.name, adtId);
      for (let ci = 0; ci < node.body.constructors.length; ci++) {
        const ctor = node.body.constructors[ci]!;
        const ctorType = exportedConstructors.get(ctor.name);
        if (ctorType == null) continue;
        functions[ctor.name] = {
          kind: 'constructor',
          adt_id: adtId,
          ctor_index: ci,
          arity: ctor.params.length,
          type: serializeType(ctorType),
        };
      }
    }
  }

  // Value-level exports (functions, vals, vars, exceptions)
  for (const [name, t] of exports) {
    if (functions[name] != null) continue; // already handled as constructor
    if (exportedTypeAliases.has(name)) continue; // goes to types map
    // Determine kind from program body
    let found = false;
    for (const node of program.body) {
      if (!node) continue;
      if ((node.kind === 'FunDecl' || node.kind === 'ExternFunDecl') && (node as { name: string }).name === name) {
        const arity = (node as { params: unknown[] }).params.length;
        functions[name] = { kind: 'function', function_index: 0, arity, type: serializeType(t) };
        found = true;
        break;
      }
      if (node.kind === 'VarDecl' && (node as { name: string }).name === name) {
        functions[name] = { kind: 'var', function_index: 0, setter_index: 0, type: serializeType(t) };
        found = true;
        break;
      }
      if (node.kind === 'ValDecl' && (node as { name: string }).name === name) {
        functions[name] = { kind: 'val', function_index: 0, type: serializeType(t) };
        found = true;
        break;
      }
      if (node.kind === 'ExceptionDecl' && (node as { name: string; exported?: boolean }).name === name) {
        // Exceptions are constructor-like; record as constructor with adt_id based on name hash
        const exn = node as ExceptionDecl;
        const adtId = adtIdByType.get(name) ?? adtIdCounter++;
        adtIdByType.set(name, adtId);
        functions[name] = {
          kind: 'constructor',
          adt_id: adtId,
          ctor_index: 0,
          arity: exn.fields?.length ?? 0,
          type: serializeType(t),
        };
        found = true;
        break;
      }
    }
    if (!found) {
      // Fallback: export as a 0-arity val
      functions[name] = { kind: 'val', function_index: 0, type: serializeType(t) };
    }
  }

  // Build types map (type-level exports: aliases and ADTs)
  const types: Record<string, KtiTypeEntry> = {};
  for (const [name, t] of exportedTypeAliases) {
    const vis = exportedTypeVisibility.get(name) ?? 'export';
    // Find if this is an ADT in program body
    let isAdt = false;
    let adtConstructorsList: { name: string; params: unknown[] }[] | undefined;
    let typeParamsList: string[] | undefined;
    for (const node of program.body) {
      if (!node) continue;
      if ((node.kind === 'TypeDecl' || node.kind === 'ExternTypeDecl') && (node as { name: string }).name === name) {
        typeParamsList = (node as { typeParams?: string[] }).typeParams;
        if (node.kind === 'TypeDecl' && node.body.kind === 'ADTBody') {
          isAdt = true;
          if (vis !== 'opaque') {
            adtConstructorsList = node.body.constructors.map((c) => ({
              name: c.name,
              params: c.params.map((p) => serializeType({ kind: 'prim', name: 'Unit' } as InternalType)),
            }));
          }
        }
        break;
      }
    }

    const entry: KtiTypeEntry = {
      visibility: vis === 'opaque' ? 'opaque' : 'export',
      kind: isAdt ? 'adt' : 'alias',
    };
    if (vis !== 'opaque') {
      entry.type = serializeType(t);
    } else {
      entry.type = { k: 'opaque' };
    }
    if (adtConstructorsList != null) {
      entry.constructors = adtConstructorsList;
    }
    if (typeParamsList && typeParamsList.length > 0) {
      entry.typeParams = typeParamsList;
    }
    types[name] = entry;
  }

  const codegenMeta = extractCodegenMeta(program, exports, exportedTypeAliases, exportedTypeVisibility);

  return {
    version: 4,
    functions,
    types,
    sourceHash,
    depHashes,
    codegenMeta,
  };
}

// ---------------------------------------------------------------------------
// File writer
// ---------------------------------------------------------------------------

/**
 * Write a KtiV4 object to the given file path as pretty-printed JSON.
 */
export function writeKtiFile(ktiPath: string, kti: KtiV4): void {
  writeFileSync(ktiPath, JSON.stringify(kti, null, 2) + '\n', 'utf-8');
}
