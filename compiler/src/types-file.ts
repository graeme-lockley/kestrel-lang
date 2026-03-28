/**
 * Types file (07 §5): compile-time artifact for package consumers.
 * Format: JSON with exported names and offsets (function_index, arity, type).
 */
import { readFileSync, writeFileSync, statSync } from 'fs';
import type { InternalType } from './types/internal.js';
import { freshVar } from './types/internal.js';

/** Bump when export shape changes (e.g. new `kind` values) so stale cache `.kti` files are rejected and deps recompiled. */
const KTI_VERSION = 3;

/** Serialized type for JSON (var ids in scheme body are 0-based indices into scheme vars). */
type SerType =
  | { kind: 'var'; id: number }
  | { kind: 'prim'; name: string }
  | { kind: 'arrow'; params: SerType[]; return: SerType }
  | { kind: 'record'; fields: { name: string; mut: boolean; type: SerType }[]; row?: SerType }
  | { kind: 'app'; name: string; args: SerType[] }
  | { kind: 'tuple'; elements: SerType[] }
  | { kind: 'union'; left: SerType; right: SerType }
  | { kind: 'inter'; left: SerType; right: SerType }
  | { kind: 'scheme'; varCount: number; body: SerType };

function serializeType(t: InternalType, schemeVarToIndex?: Map<number, number>): SerType {
  if (t.kind === 'var') {
    if (schemeVarToIndex != null) {
      const idx = schemeVarToIndex.get(t.id);
      if (idx !== undefined) return { kind: 'var', id: idx };
    }
    return { kind: 'var', id: t.id };
  }
  if (t.kind === 'prim') return { kind: 'prim', name: t.name };
  if (t.kind === 'arrow') {
    return {
      kind: 'arrow',
      params: t.params.map((p) => serializeType(p, schemeVarToIndex)),
      return: serializeType(t.return, schemeVarToIndex),
    };
  }
  if (t.kind === 'record') {
    return {
      kind: 'record',
      fields: t.fields.map((f) => ({
        name: f.name,
        mut: f.mut,
        type: serializeType(f.type, schemeVarToIndex),
      })),
      row: t.row ? serializeType(t.row, schemeVarToIndex) : undefined,
    };
  }
  if (t.kind === 'app') {
    return {
      kind: 'app',
      name: t.name,
      args: t.args.map((a) => serializeType(a, schemeVarToIndex)),
    };
  }
  if (t.kind === 'tuple') {
    return {
      kind: 'tuple',
      elements: t.elements.map((e) => serializeType(e, schemeVarToIndex)),
    };
  }
  if (t.kind === 'union') {
    return {
      kind: 'union',
      left: serializeType(t.left, schemeVarToIndex),
      right: serializeType(t.right, schemeVarToIndex),
    };
  }
  if (t.kind === 'inter') {
    return {
      kind: 'inter',
      left: serializeType(t.left, schemeVarToIndex),
      right: serializeType(t.right, schemeVarToIndex),
    };
  }
  if (t.kind === 'scheme') {
    const varToIndex = new Map<number, number>();
    t.vars.forEach((v, i) => varToIndex.set(v, i));
    return {
      kind: 'scheme',
      varCount: t.vars.length,
      body: serializeType(t.body, varToIndex),
    };
  }
  return { kind: 'prim', name: 'Unit' };
}

function deserializeType(raw: unknown, schemeVars?: InternalType[]): InternalType {
  if (raw == null || typeof raw !== 'object' || !('kind' in raw)) {
    return { kind: 'prim', name: 'Unit' };
  }
  const o = raw as Record<string, unknown>;
  const kind = o.kind as string;
  if (kind === 'var') {
    const id = o.id as number;
    if (schemeVars != null && id >= 0 && id < schemeVars.length) return schemeVars[id]!;
    return { kind: 'var', id };
  }
  if (kind === 'prim') {
    const name = o.name as string;
    if (['Int', 'Float', 'Bool', 'String', 'Unit', 'Char', 'Rune'].includes(name)) {
      return { kind: 'prim', name: name as 'Int' | 'Float' | 'Bool' | 'String' | 'Unit' | 'Char' | 'Rune' };
    }
    return { kind: 'prim', name: 'Unit' };
  }
  if (kind === 'arrow') {
    return {
      kind: 'arrow',
      params: (o.params as unknown[]).map((p) => deserializeType(p, schemeVars)),
      return: deserializeType(o.return, schemeVars),
    };
  }
  if (kind === 'record') {
    return {
      kind: 'record',
      fields: ((o.fields as unknown[]) || []).map((f: unknown) => {
        const r = f as Record<string, unknown>;
        return { name: r.name as string, mut: (r.mut as boolean) ?? false, type: deserializeType(r.type, schemeVars) };
      }),
      row: o.row != null ? deserializeType(o.row, schemeVars) : undefined,
    };
  }
  if (kind === 'app') {
    return {
      kind: 'app',
      name: o.name as string,
      args: ((o.args as unknown[]) || []).map((a) => deserializeType(a, schemeVars)),
    };
  }
  if (kind === 'tuple') {
    return {
      kind: 'tuple',
      elements: ((o.elements as unknown[]) || []).map((e) => deserializeType(e, schemeVars)),
    };
  }
  if (kind === 'union') {
    return {
      kind: 'union',
      left: deserializeType(o.left, schemeVars),
      right: deserializeType(o.right, schemeVars),
    };
  }
  if (kind === 'inter') {
    return {
      kind: 'inter',
      left: deserializeType(o.left, schemeVars),
      right: deserializeType(o.right, schemeVars),
    };
  }
  if (kind === 'scheme') {
    const varCount = (o.varCount as number) ?? 0;
    const vars = Array.from({ length: varCount }, () => freshVar());
    return {
      kind: 'scheme',
      vars: vars.map((v) => (v as { kind: 'var'; id: number }).id),
      body: deserializeType(o.body, vars),
    };
  }
  return { kind: 'prim', name: 'Unit' };
}

export type TypesFileExportKind = 'function' | 'val' | 'var' | 'type' | 'exception' | 'constructor';

export interface TypesFileFunctionExport {
  kind: 'function';
  function_index: number;
  arity: number;
  type: SerType;
}

export interface TypesFileValExport {
  kind: 'val';
  function_index: number;
  type: SerType;
}

export interface TypesFileVarExport {
  kind: 'var';
  function_index: number;
  setter_index: number;
  type: SerType;
}

export interface TypesFileTypeAliasExport {
  kind: 'type';
  type: SerType;
  opaque?: boolean;
}

/** Exported `export exception Name` (VM/runtime ADT); not a function slot. */
export interface TypesFileExceptionExport {
  kind: 'exception';
  type: SerType;
}

/** Exported non-opaque ADT constructor (namespace `M.Ctor` / `.kti` consumers). */
export interface TypesFileConstructorExport {
  kind: 'constructor';
  adt_id: number;
  ctor_index: number;
  arity: number;
  type: SerType;
}

export type TypesFileExportEntry =
  | TypesFileFunctionExport
  | TypesFileValExport
  | TypesFileVarExport
  | TypesFileTypeAliasExport
  | TypesFileExceptionExport
  | TypesFileConstructorExport;

export interface TypesFileExport {
  functions: Record<string, TypesFileExportEntry>;
}

export interface ResolvedTypesFileExport {
  kind: TypesFileExportKind;
  function_index: number;
  arity: number;
  type: InternalType;
  /** Setter function index in package function table; present when kind === 'var'. */
  setter_index?: number;
  /** Present when kind === 'constructor' (dependency bytecode ADT table index). */
  adt_id?: number;
  ctor_index?: number;
}

export interface ResolvedTypeAliasExport {
  kind: 'type';
  type: InternalType;
  opaque?: boolean;
}

export type TypesFileExportInput = {
  kind?: TypesFileExportKind;
  function_index: number;
  arity?: number;
  type: InternalType;
  /** Required when kind === 'var'. */
  setter_index?: number;
  /** Required when kind === 'constructor'. */
  adt_id?: number;
  ctor_index?: number;
};

/**
 * Write a types file for a package. Call after codegen; exports include kind ('function' | 'val' | 'var' | 'exception').
 */
export function writeTypesFile(
  path: string, 
  exports: Map<string, TypesFileExportInput>, 
  typeAliasExports?: Map<string, InternalType>,
  typeVisibility?: Map<string, 'local' | 'opaque' | 'export'>
): void {
  const functions: Record<string, TypesFileExportEntry> = {};
  for (const [name, exp] of exports) {
    const kind = exp.kind ?? 'function';
    if (kind === 'constructor') {
      const adt_id = exp.adt_id;
      const ctor_index = exp.ctor_index;
      const arity = exp.arity ?? 0;
      if (adt_id === undefined || ctor_index === undefined) {
        throw new Error(`Types file: constructor export "${name}" requires adt_id and ctor_index`);
      }
      functions[name] = {
        kind: 'constructor',
        adt_id,
        ctor_index,
        arity,
        type: serializeType(exp.type),
      };
      continue;
    }
    if (kind === 'exception') {
      functions[name] = { kind: 'exception', type: serializeType(exp.type) };
      continue;
    }
    const serType = serializeType(exp.type);
    if (kind === 'val') {
      functions[name] = { kind: 'val', function_index: exp.function_index, type: serType };
    } else if (kind === 'var') {
      const setter_index = exp.setter_index;
      if (setter_index === undefined) throw new Error(`Types file: var export "${name}" requires setter_index`);
      functions[name] = { kind: 'var', function_index: exp.function_index, setter_index, type: serType };
    } else {
      functions[name] = {
        kind: 'function',
        function_index: exp.function_index,
        arity: exp.arity ?? 0,
        type: serType,
      };
    }
  }
  if (typeAliasExports) {
    for (const [name, t] of typeAliasExports) {
      const isOpaque = typeVisibility?.get(name) === 'opaque';
      if (isOpaque) {
        functions[name] = { 
          kind: 'type', 
          type: serializeType({ kind: 'app' as const, name, args: [] }), 
          opaque: true 
        };
      } else {
        functions[name] = { kind: 'type', type: serializeType(t), opaque: false };
      }
    }
  }
  const payload: TypesFileExport = { functions };
  const content = JSON.stringify({ version: KTI_VERSION, ...payload }, null, 0);
  writeFileSync(path, content, 'utf-8');
}

/**
 * Read a types file and return export set for use as import bindings.
 * Returns map: local name (when used as import) -> { kind, function_index, arity, type }.
 * Val/var have arity 0 (getter). Type aliases returned separately.
 */
export function readTypesFile(path: string): { exports: Map<string, ResolvedTypesFileExport>; typeAliases: Map<string, ResolvedTypeAliasExport> } {
  const content = readFileSync(path, 'utf-8');
  const data = JSON.parse(content) as { version?: number; functions?: Record<string, TypesFileExportEntry> };
  if (data.version !== KTI_VERSION) {
    throw new Error(`Types file ${path}: unsupported version ${data.version ?? 'missing'}`);
  }
  const out = new Map<string, ResolvedTypesFileExport>();
  const typeAliases = new Map<string, ResolvedTypeAliasExport>();
  const functions = data.functions ?? {};
  for (const [name, exp] of Object.entries(functions)) {
    const kind = exp.kind ?? 'function';
    if (kind === 'type') {
      const typeExp = exp as TypesFileTypeAliasExport;
      typeAliases.set(name, { 
        kind: 'type', 
        type: deserializeType(typeExp.type),
        opaque: typeExp.opaque 
      });
      continue;
    }
    if (kind === 'constructor') {
      const ce = exp as TypesFileConstructorExport;
      out.set(name, {
        kind: 'constructor',
        function_index: 0,
        arity: ce.arity,
        type: deserializeType(ce.type),
        adt_id: ce.adt_id,
        ctor_index: ce.ctor_index,
      });
      continue;
    }
    if (kind === 'exception') {
      const ex = exp as TypesFileExceptionExport;
      out.set(name, {
        kind: 'exception',
        function_index: 0,
        arity: 0,
        type: deserializeType(ex.type),
      });
      continue;
    }
    const arity = kind === 'function' ? (exp as TypesFileFunctionExport).arity : 0;
    const resolved: ResolvedTypesFileExport = {
      kind: kind as TypesFileExportKind,
      function_index: (exp as TypesFileFunctionExport | TypesFileValExport | TypesFileVarExport).function_index,
      arity,
      type: deserializeType(exp.type),
    };
    if (kind === 'var') {
      const ve = exp as TypesFileVarExport;
      if (ve.setter_index !== undefined) resolved.setter_index = ve.setter_index;
    }
    out.set(name, resolved);
  }
  return { exports: out, typeAliases };
}

/**
 * Check if a types file exists and is not stale relative to sourcePath.
 * Returns true if typesPath exists and is newer than sourcePath (or sourcePath doesn't exist).
 *
 * When `bytecodePath` is set and that file exists, the types file must also be at least as new
 * as the dependency `.kbc`; otherwise exported `function_index` values in the .kti can disagree
 * with the actual bytecode (e.g. after a recompile that changed the function table order).
 */
export function isTypesFileFresh(typesPath: string, sourcePath: string, bytecodePath?: string): boolean {
  try {
    const typesStat = statSync(typesPath, { throwIfNoEntry: false });
    if (!typesStat?.isFile()) return false;
    if (bytecodePath) {
      const kbcStat = statSync(bytecodePath, { throwIfNoEntry: false });
      if (kbcStat?.isFile() && typesStat.mtimeMs < kbcStat.mtimeMs) return false;
    }
    let sourceStat: ReturnType<typeof statSync> | null = null;
    try {
      sourceStat = statSync(sourcePath, { throwIfNoEntry: false });
    } catch {
      return true; // no source -> consider types fresh
    }
    if (!sourceStat) return true;
    return typesStat.mtimeMs >= sourceStat.mtimeMs;
  } catch {
    return false;
  }
}
