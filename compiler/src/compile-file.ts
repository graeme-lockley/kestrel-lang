/**
 * Multi-module compilation: resolve imports, emit one .kbc + .kti per package (07 §5).
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs';
import { resolve as pathResolve, dirname } from 'path';
import { tokenize } from './lexer/index.js';
import { parse } from './parser/index.js';
import { typecheck, type TypecheckOptions, type DependencyExportSnapshot } from './typecheck/check.js';
import { distinctSpecifiersInSourceOrder, spanForSpecifier } from './module-specifiers.js';
import { codegen, type CodegenResult } from './codegen/codegen.js';
import { writeKbc, type ImportedFunctionEntry } from './bytecode/write.js';
import { resolveSpecifier } from './resolve.js';
import {
  readTypesFile,
  writeTypesFile,
  isTypesFileFresh,
  type TypesFileExportInput,
  type ResolvedTypesFileExport,
  type ResolvedTypeAliasExport,
} from './types-file.js';
import type { Program, ImportDecl, Expr, ExceptionDecl, TypeDecl } from './ast/nodes.js';
import type { InternalType } from './types/internal.js';
import { tUnit } from './types/internal.js';
import type { Diagnostic } from './diagnostics/types.js';
import { CODES, locationFromSpan, locationFileOnly } from './diagnostics/types.js';
import type { Span } from './lexer/types.js';
import { uniqueDependencyPaths } from './dependency-paths.js';

/** Count all LambdaExpr nodes in an expression tree (used to predict function table size). */
function countLambdasInExpr(e: Expr): number {
  switch (e.kind) {
    case 'LambdaExpr': return 1 + countLambdasInExpr(e.body);
    case 'CallExpr': return countLambdasInExpr(e.callee) + e.args.reduce((n, a) => n + countLambdasInExpr(a), 0);
    case 'BinaryExpr': return countLambdasInExpr(e.left) + countLambdasInExpr(e.right);
    case 'UnaryExpr': return countLambdasInExpr(e.operand);
    case 'IfExpr': return countLambdasInExpr(e.cond) + countLambdasInExpr(e.then) + (e.else !== undefined ? countLambdasInExpr(e.else) : 0);
    case 'IsExpr': return countLambdasInExpr(e.expr);
    case 'WhileExpr': return countLambdasInExpr(e.cond) + countLambdasInExpr(e.body);
    case 'MatchExpr': return countLambdasInExpr(e.scrutinee) + e.cases.reduce((n, c) => n + countLambdasInExpr(c.body), 0);
    case 'TryExpr': return countLambdasInExpr(e.body) + e.cases.reduce((n, c) => n + countLambdasInExpr(c.body), 0);
    case 'PipeExpr': return countLambdasInExpr(e.left) + countLambdasInExpr(e.right);
    case 'ConsExpr': return countLambdasInExpr(e.head) + countLambdasInExpr(e.tail);
    case 'FieldExpr': return countLambdasInExpr(e.object);
    case 'ThrowExpr': return countLambdasInExpr(e.value);
    case 'AwaitExpr': return countLambdasInExpr(e.value);
    case 'TupleExpr': return e.elements.reduce((n, el) => n + countLambdasInExpr(el), 0);
    case 'ListExpr': return e.elements.reduce((n, el) => {
      if (typeof el === 'object' && 'spread' in el) return n + countLambdasInExpr((el as { spread: true; expr: Expr }).expr);
      return n + countLambdasInExpr(el as Expr);
    }, 0);
    case 'RecordExpr': return (e.spread ? countLambdasInExpr(e.spread) : 0) + e.fields.reduce((n, f) => n + countLambdasInExpr(f.value), 0);
    case 'TemplateExpr': return e.parts.reduce((n, p) => n + (p.type === 'interp' ? countLambdasInExpr(p.expr) : 0), 0);
    case 'NeverExpr':
      return 0;
    case 'BlockExpr': {
      let n = countLambdasInExpr(e.result);
      for (const s of e.stmts) {
        if (s.kind === 'ExprStmt') n += countLambdasInExpr(s.expr);
        else if (s.kind === 'AssignStmt') n += countLambdasInExpr(s.target) + countLambdasInExpr(s.value);
        else if (s.kind === 'FunStmt') n += 1 + countLambdasInExpr(s.body);
        else if (s.kind === 'ValStmt' || s.kind === 'VarStmt') n += countLambdasInExpr(s.value);
      }
      return n;
    }
    default: return 0;
  }
}

function countLambdasInProgram(program: Program): number {
  let n = 0;
  for (const node of program.body) {
    if (!node) continue;
    if ('body' in node && node.kind === 'FunDecl') n += countLambdasInExpr(node.body);
    if (node.kind === 'ValDecl' || node.kind === 'VarDecl') n += countLambdasInExpr(node.value);
    if (node.kind === 'ValStmt' || node.kind === 'VarStmt') n += countLambdasInExpr(node.value);
    if (node.kind === 'ExprStmt') n += countLambdasInExpr(node.expr);
    if (node.kind === 'AssignStmt') n += countLambdasInExpr(node.value);
  }
  return n;
}

export interface CompileFileOptions {
  /** Project root (for stdlib resolution). Default: process.cwd() */
  projectRoot?: string;
  /** Path to stdlib directory. Default: projectRoot/stdlib */
  stdlibDir?: string;
  /** Called once per file after compile (not on cache hit). Receives absolute path and duration in ms. */
  onCompilingFile?: (absolutePath: string, durationMs: number) => void;
  /** If set, only call onCompilingFile for paths in this set (so only "stale" files are reported). */
  stalePaths?: Set<string>;
  /** If set, write each compiled package's .kbc and .kti here. Enables VM to load deps on first use. */
  getOutputPaths?: (sourcePath: string) => { kbc: string; kti: string };
}

function exportSnapshotFromTypesRead(
  typesExports: Map<string, ResolvedTypesFileExport>,
  typesTypeAliases: Map<string, ResolvedTypeAliasExport>
): DependencyExportSnapshot {
  const exports = new Map<string, InternalType>();
  const exportedTypeAliases = new Map<string, InternalType>();
  const exportedConstructors = new Map<string, InternalType>();
  const exportedTypeVisibility = new Map<string, 'local' | 'opaque' | 'export'>();
  for (const [name, exp] of typesExports) {
    if (exp.kind === 'constructor' && exp.adt_id !== undefined && exp.ctor_index !== undefined) {
      exportedConstructors.set(name, exp.type);
      continue;
    }
    if (exp.kind === 'exception') {
      exports.set(name, exp.type);
      continue;
    }
    if (exp.kind === 'function' || exp.kind === 'val' || exp.kind === 'var') {
      exports.set(name, exp.type);
    }
  }
  for (const [name, ta] of typesTypeAliases) {
    exportedTypeAliases.set(name, ta.type);
    if (!exports.has(name)) exports.set(name, ta.type);
    exportedTypeVisibility.set(name, ta.opaque ? 'opaque' : 'export');
  }
  return { exports, exportedTypeAliases, exportedConstructors, exportedTypeVisibility };
}

/** Val/var exports use a 0-ary getter at runtime (CALL), not a first-class fn ref. */
function isExportThunk(program: Program, exportName: string): boolean {
  for (const node of program.body) {
    if (!node) continue;
    if (node.kind === 'ValDecl' && node.name === exportName) return true;
    if (node.kind === 'VarDecl' && node.name === exportName) return true;
  }
  return false;
}

/** Build import bindings from NamedImport: localName -> must be in dep's exports. */
function getRequestedImports(imp: ImportDecl): Map<string, string> {
  const m = new Map<string, string>();
  if (imp.kind === 'NamedImport') {
    for (const s of imp.specs) m.set(s.local, s.external);
  }
  return m;
}

function diag(file: string, code: string, message: string, span?: Span, source?: string): Diagnostic {
  return {
    severity: 'error',
    code,
    message,
    location: span ? locationFromSpan(file, span, source) : locationFileOnly(file),
  };
}

/** ADT name → index in dependency bytecode ADT section (same order as codegen). */
function adtBytecodeIndex(result: CodegenResult, adtName: string): number {
  for (let i = 0; i < result.adts.length; i++) {
    const n = result.stringTable[result.adts[i]!.nameIndex];
    if (n === adtName) return i;
  }
  throw new Error(`compile-file: ADT "${adtName}" not found in codegen adt table`);
}

function ctorMetaForExportedCtor(program: Program, ctorName: string): { adtName: string; ctorIndex: number } | undefined {
  for (const node of program.body) {
    if (node == null || node.kind !== 'TypeDecl') continue;
    if (node.visibility !== 'export' || node.body.kind !== 'ADTBody') continue;
    const idx = node.body.constructors.findIndex((c) => c.name === ctorName);
    if (idx >= 0) return { adtName: node.name, ctorIndex: idx };
  }
  return undefined;
}

function ctorArityInProgram(program: Program, adtName: string, ctorIndex: number): number {
  for (const node of program.body) {
    if (node == null || node.kind !== 'TypeDecl') continue;
    if (node.name !== adtName || node.body.kind !== 'ADTBody') continue;
    return node.body.constructors[ctorIndex]?.params.length ?? 0;
  }
  return 0;
}

interface NamespaceImportConstructorInfo {
  importIndex: number;
  adtId: number;
  ctorIndex: number;
  arity: number;
}

export function compileFile(
  inputPath: string,
  options?: CompileFileOptions
): { ok: true; kbc: Uint8Array; dependencyPaths: string[] } | { ok: false; diagnostics: Diagnostic[] } {
  const projectRoot = options?.projectRoot ?? process.cwd();
  const stdlibDir = options?.stdlibDir ?? pathResolve(projectRoot, 'stdlib');
  const absPath = pathResolve(inputPath);

  const visited = new Set<string>();
  const cache = new Map<
    string,
    {
      program: Program;
      exports: Map<string, InternalType>;
      exportedTypeAliases: Map<string, InternalType>;
      exportedConstructors: Map<string, InternalType>;
      codegenResult: CodegenResult;
      dependencyPaths: string[];
      /** Merged function table index per exported value (for importers when the export is re-exported). */
      exportFunctionSlotByName: Map<string, number>;
    }
  >();
  const onCompilingFile = options?.onCompilingFile;
  const stalePaths = options?.stalePaths;

  function compileOne(filePath: string): {
    ok: true;
    program: Program;
    exports: Map<string, InternalType>;
    exportedTypeAliases: Map<string, InternalType>;
    exportedConstructors: Map<string, InternalType>;
    exportedTypeVisibility?: Map<string, 'local' | 'opaque' | 'export'>;
    codegenResult: CodegenResult;
    dependencyPaths: string[];
    exportFunctionSlotByName: Map<string, number>;
  } | { ok: false; diagnostics: Diagnostic[] } {
    if (visited.has(filePath)) {
      return { ok: false, diagnostics: [diag(filePath, CODES.file.circular_import, `Circular import: ${filePath}`)] };
    }

    const cached = cache.get(filePath);
    if (cached) return { ok: true, ...cached };

    visited.add(filePath);

    const compileStart = performance.now();

    let source: string;
    try {
      source = readFileSync(filePath, 'utf-8');
    } catch {
      return { ok: false, diagnostics: [diag(filePath, CODES.file.read_error, `Cannot read file: ${filePath}`)] };
    }

    const tokens = tokenize(source);
    const parseResult = parse(tokens);
    let program: Program;
    if ('ok' in parseResult && !parseResult.ok) {
      return {
        ok: false,
        diagnostics: parseResult.errors.map((e) => ({
          severity: 'error' as const,
          code: e.code,
          message: e.message,
          location: locationFromSpan(filePath, e.span, source),
        })),
      };
    }
    program = parseResult as Program;

    const resolveOpts = { fromFile: filePath, projectRoot, stdlibDir };
    const specs = distinctSpecifiersInSourceOrder(program);

    const resolved = new Map<string, string>();
    for (const spec of specs) {
      const r = resolveSpecifier(spec, resolveOpts);
      if (!r.ok) {
        const span = spanForSpecifier(program, spec);
        return { ok: false, diagnostics: [diag(filePath, CODES.resolve.module_not_found, r.error, span, source)] };
      }
      resolved.set(spec, r.path);
    }

    // Validate namespace names: UPPER_IDENT uniqueness and no conflict with named import locals
    const namespaceNames = new Set<string>();
    for (const imp of program.imports) {
      if (imp.kind === 'NamespaceImport') {
        if (namespaceNames.has(imp.name)) {
          return { ok: false, diagnostics: [diag(filePath, CODES.export.import_conflict, `Duplicate namespace name: ${imp.name}`, (imp as { span?: Span })?.span, source)] };
        }
        namespaceNames.add(imp.name);
      }
    }
    for (const imp of program.imports) {
      if (imp.kind === 'NamedImport') {
        for (const s of imp.specs) {
          if (namespaceNames.has(s.local)) {
            return { ok: false, diagnostics: [diag(filePath, CODES.export.import_conflict, `Import name '${s.local}' conflicts with namespace name`, (imp as { span?: Span })?.span, source)] };
          }
        }
      }
    }

    const getOutputPaths = options?.getOutputPaths;
    const importBindings = new Map<string, InternalType>();
    const typeAliasBindings = new Map<string, InternalType>();
    const importOpaqueTypes = new Set<string>();
    type DepResult =
      | {
          spec: string;
          path: string;
          result: CodegenResult;
          exportSet: Set<string>;
          dependencyPaths: string[];
          program: Program;
          exports: Map<string, InternalType>;
          exportedTypeAliases: Map<string, InternalType>;
          exportedConstructors: Map<string, InternalType>;
          exportedTypeVisibility: Map<string, 'local' | 'opaque' | 'export'>;
          fromTypesFile?: false;
        }
      | {
          spec: string;
          path: string;
          exportSet: Set<string>;
          nameToExport: Map<
            string,
            {
              function_index: number;
              arity: number;
              type: InternalType;
              setter_index?: number;
              exportKind: 'function' | 'val' | 'var';
            }
          >;
          exportSnapshot: DependencyExportSnapshot;
          exceptionExportNames: Set<string>;
          fromTypesFile: true;
        };
    const depResults: DepResult[] = [];
    /** Imported exception ADTs (e.g. `kestrel:runtime`) for codegen catch patterns + VM cross-module `==`. */
    const exceptionImports: { canonical: string; local: string }[] = [];
    const namespaceImportConstructors = new Map<string, Map<string, NamespaceImportConstructorInfo>>();

    function resolveExportedCtorOrigin(
      depFilePath: string,
      exportName: string,
      visited: Set<string>
    ):
      | { adtName: string; ctorIndex: number; bytecode: CodegenResult; program: Program }
      | undefined {
      if (visited.has(depFilePath)) return undefined;
      visited.add(depFilePath);
      const ent = cache.get(depFilePath);
      if (!ent) return undefined;
      const direct = ctorMetaForExportedCtor(ent.program, exportName);
      if (direct != null) {
        return {
          adtName: direct.adtName,
          ctorIndex: direct.ctorIndex,
          bytecode: ent.codegenResult,
          program: ent.program,
        };
      }
      const ro = { fromFile: depFilePath, projectRoot, stdlibDir };
      for (const node of ent.program.body) {
        if (node?.kind !== 'ExportDecl') continue;
        const inner = node.inner;
        if (inner.kind === 'ExportStar') {
          const r = resolveSpecifier(inner.spec, ro);
          if (!r.ok) continue;
          const sub = resolveExportedCtorOrigin(r.path, exportName, visited);
          if (sub) return sub;
        } else if (inner.kind === 'ExportNamed') {
          for (const { external, local } of inner.specs) {
            if (local !== exportName) continue;
            const r = resolveSpecifier(inner.spec, ro);
            if (!r.ok) continue;
            const sub = resolveExportedCtorOrigin(r.path, external, visited);
            if (sub) return sub;
          }
        }
      }
      return undefined;
    }

    for (let specIndex = 0; specIndex < specs.length; specIndex++) {
      const spec = specs[specIndex]!;
      const depPath = resolved.get(spec)!;
      let usedTypesFile = false;
      if (getOutputPaths) {
        const paths = getOutputPaths(depPath);
        if (isTypesFileFresh(paths.kti, depPath, paths.kbc)) {
          // If any transitive dep is in the stale set, force recompile (so m2 recompiles when m3 is stale)
          let anyTransitiveStale = false;
          if (stalePaths?.size) {
            const depsFile = paths.kbc + '.deps';
            if (existsSync(depsFile)) {
              try {
                const content = readFileSync(depsFile, 'utf-8');
                for (const line of content.split('\n')) {
                  const p = line.trim();
                  if (p && stalePaths.has(p)) {
                    anyTransitiveStale = true;
                    break;
                  }
                }
              } catch {
                /* ignore */
              }
            }
          }
          if (!anyTransitiveStale) {
            try {
              const { exports: typesExports, typeAliases: typesTypeAliases } = readTypesFile(paths.kti);
            const exportSet = new Set([...typesExports.keys(), ...typesTypeAliases.keys()]);
            const nameToExport = new Map<
              string,
              {
                function_index: number;
                arity: number;
                type: InternalType;
                setter_index?: number;
                exportKind: 'function' | 'val' | 'var';
              }
            >();
            const exceptionExportNames = new Set<string>();
            for (const [name, exp] of typesExports) {
              if (exp.kind === 'exception') exceptionExportNames.add(name);
            }
            for (const [name, exp] of typesExports) {
              if (exp.kind === 'function' || exp.kind === 'val' || exp.kind === 'var') {
                const entry: {
                  function_index: number;
                  arity: number;
                  type: InternalType;
                  setter_index?: number;
                  exportKind: 'function' | 'val' | 'var';
                } = {
                  function_index: exp.function_index,
                  arity: exp.arity,
                  type: exp.type,
                  exportKind: exp.kind,
                };
                if (exp.kind === 'var' && exp.setter_index !== undefined) entry.setter_index = exp.setter_index;
                nameToExport.set(name, entry);
              }
            }
            for (const imp of program.imports) {
              if (imp.spec !== spec) continue;
              const requested = getRequestedImports(imp);
              for (const [localName, externalName] of requested) {
                const exp = typesExports.get(externalName);
                const ta = typesTypeAliases.get(externalName);
                if (exp == null && ta == null) {
                  const imp = program.imports.find((i) => i.spec === spec);
                  return { ok: false, diagnostics: [diag(filePath, CODES.export.not_exported, `Module ${spec} does not export ${externalName}`, (imp as { span?: Span })?.span, source)] };
                }
                if (ta != null) {
                  typeAliasBindings.set(localName, ta.type);
                  if (ta.opaque) {
                    importOpaqueTypes.add(localName);
                  }
                } else if (
                  exp != null &&
                  (exp.kind === 'function' || exp.kind === 'val' || exp.kind === 'var' || exp.kind === 'exception')
                ) {
                  importBindings.set(localName, exp.type);
                  if (exp.kind === 'exception' && exp.type.kind === 'app' && exp.type.args.length === 0) {
                    exceptionImports.push({ canonical: exp.type.name, local: localName });
                  }
                }
              }
            }
            for (const imp of program.imports) {
              if (imp.kind !== 'NamespaceImport' || imp.spec !== spec) continue;
              const bindings = new Map<string, InternalType>();
              for (const [name, exp] of typesExports) {
                if (exp.kind === 'function' || exp.kind === 'val' || exp.kind === 'var' || exp.kind === 'exception') {
                  bindings.set(name, exp.type);
                }
                if (exp.kind === 'constructor') {
                  bindings.set(name, exp.type);
                }
              }
              for (const [name, ta] of typesTypeAliases) {
                bindings.set(name, ta.type);
              }
              importBindings.set(imp.name, { kind: 'namespace', bindings });
              const nsCtorMap = new Map<string, NamespaceImportConstructorInfo>();
              for (const [name, exp] of typesExports) {
                if (
                  exp.kind === 'constructor' &&
                  exp.adt_id !== undefined &&
                  exp.ctor_index !== undefined
                ) {
                  nsCtorMap.set(name, {
                    importIndex: specIndex,
                    adtId: exp.adt_id,
                    ctorIndex: exp.ctor_index,
                    arity: exp.arity,
                  });
                }
              }
              namespaceImportConstructors.set(imp.name, nsCtorMap);
            }
            const exportSnapshot = exportSnapshotFromTypesRead(typesExports, typesTypeAliases);
            depResults.push({
              spec,
              path: depPath,
              exportSet,
              nameToExport,
              exportSnapshot,
              exceptionExportNames,
              fromTypesFile: true,
            });
            usedTypesFile = true;
            } catch {
              // Fall through to compile
            }
          }
        }
      }
      if (!usedTypesFile) {
        const depOut = compileOne(depPath);
        if (!depOut.ok) return depOut;
        const depExportSet = new Set([...depOut.exports.keys(), ...depOut.exportedConstructors.keys()]);
        for (const imp of program.imports) {
          if (imp.spec !== spec) continue;
          const requested = getRequestedImports(imp);
          for (const [localName, externalName] of requested) {
            const t = depOut.exports.get(externalName);
            if (t == null) {
              const imp = program.imports.find((i) => i.spec === spec);
              return { ok: false, diagnostics: [diag(filePath, CODES.export.not_exported, `Module ${spec} does not export ${externalName}`, (imp as { span?: Span })?.span, source)] };
            }
            if (depOut.exportedTypeAliases.has(externalName)) {
              typeAliasBindings.set(localName, t);
              if (depOut.exportedTypeVisibility?.get(externalName) === 'opaque') {
                importOpaqueTypes.add(localName);
              }
            } else {
              importBindings.set(localName, t);
              const isExc = depOut.program.body.some(
                (n): n is ExceptionDecl =>
                  n != null && n.kind === 'ExceptionDecl' && n.exported && n.name === externalName,
              );
              if (isExc) exceptionImports.push({ canonical: externalName, local: localName });
            }
          }
        }
        for (const imp of program.imports) {
          if (imp.kind !== 'NamespaceImport' || imp.spec !== spec) continue;
          const bindings = new Map<string, InternalType>();
          for (const [name, t] of depOut.exports) {
            bindings.set(name, t);
          }
          for (const [name, t] of depOut.exportedTypeAliases) {
            bindings.set(name, t);
          }
          for (const [name, t] of depOut.exportedConstructors) {
            bindings.set(name, t);
          }
          importBindings.set(imp.name, { kind: 'namespace', bindings });
          const nsCtorMap = new Map<string, NamespaceImportConstructorInfo>();
          for (const ctorName of depOut.exportedConstructors.keys()) {
            const origin = resolveExportedCtorOrigin(depPath, ctorName, new Set());
            if (origin == null) continue;
            nsCtorMap.set(ctorName, {
              importIndex: specIndex,
              adtId: adtBytecodeIndex(origin.bytecode, origin.adtName),
              ctorIndex: origin.ctorIndex,
              arity: ctorArityInProgram(origin.program, origin.adtName, origin.ctorIndex),
            });
          }
          namespaceImportConstructors.set(imp.name, nsCtorMap);
        }
        depResults.push({
          spec,
          path: depPath,
          result: depOut.codegenResult,
          exportSet: depExportSet,
          dependencyPaths: depOut.dependencyPaths,
          program: depOut.program,
          exports: depOut.exports,
          exportedTypeAliases: depOut.exportedTypeAliases,
          exportedConstructors: depOut.exportedConstructors,
          exportedTypeVisibility: depOut.exportedTypeVisibility ?? new Map(),
        });
      }
    }

    const dependencyExportsBySpec = new Map<string, DependencyExportSnapshot>();
    for (const dr of depResults) {
      if (dr.fromTypesFile) {
        dependencyExportsBySpec.set(dr.spec, dr.exportSnapshot);
      } else {
        dependencyExportsBySpec.set(dr.spec, {
          exports: dr.exports,
          exportedTypeAliases: dr.exportedTypeAliases,
          exportedConstructors: dr.exportedConstructors,
          exportedTypeVisibility: dr.exportedTypeVisibility,
        });
      }
    }

    const tcOpts: TypecheckOptions = {
      importBindings: importBindings.size > 0 ? importBindings : undefined,
      typeAliasBindings: typeAliasBindings.size > 0 ? typeAliasBindings : undefined,
      importOpaqueTypes: importOpaqueTypes.size > 0 ? importOpaqueTypes : undefined,
      sourceFile: filePath,
      sourceContent: source,
      dependencyExportsBySpec,
    };
    const tc = typecheck(program, tcOpts);
    if (!tc.ok) return { ok: false, diagnostics: tc.diagnostics };

    const funDeclCount = program.body.filter((n) => n != null && n.kind === 'FunDecl').length;
    const lambdaCount = countLambdasInProgram(program);
    const valOrVarCount = program.body.filter((n) => n != null && (n.kind === 'ValDecl' || n.kind === 'VarDecl')).length;
    const varSetterCount = program.body.filter((n) => n != null && n.kind === 'VarDecl').length;
    const mainFuncCount = funDeclCount + lambdaCount + valOrVarCount + varSetterCount;
    const importedFuncIds = new Map<string, number>();
    const importedVarSetterIds = new Map<string, number>();
    const importedThunkLocals = new Set<string>();
    const importedFunctionTable: ImportedFunctionEntry[] = [];
    for (let specIndex = 0; specIndex < specs.length; specIndex++) {
      const spec = specs[specIndex]!;
      const dep = depResults.find((d) => d.spec === spec);
      if (!dep) continue;
      if (dep.fromTypesFile) {
        const { exportSet, nameToExport } = dep;
        for (const imp of program.imports) {
          if (imp.kind !== 'NamedImport' || imp.spec !== spec) continue;
          for (const s of imp.specs) {
            const exp = nameToExport.get(s.external);
            if (exp !== undefined && exportSet.has(s.external)) {
              if (exp.setter_index !== undefined) {
                importedFunctionTable.push({ importIndex: specIndex, functionIndex: exp.function_index });
                importedFuncIds.set(s.local, mainFuncCount + importedFunctionTable.length - 1);
                importedThunkLocals.add(s.local);
                importedFunctionTable.push({ importIndex: specIndex, functionIndex: exp.setter_index });
                importedVarSetterIds.set(s.local, mainFuncCount + importedFunctionTable.length - 1);
              } else {
                importedFunctionTable.push({ importIndex: specIndex, functionIndex: exp.function_index });
                importedFuncIds.set(s.local, mainFuncCount + importedFunctionTable.length - 1);
                if (exp.exportKind === 'val' || exp.exportKind === 'var') importedThunkLocals.add(s.local);
              }
            }
          }
        }
      } else {
        const { result, exportSet, program: depProgram, path: depPathResolved } = dep;
        const cachedSlots = cache.get(depPathResolved)?.exportFunctionSlotByName;
        const depNameToIndex = new Map<string, number>();
        for (let i = 0; i < result.functionTable.length; i++) {
          const fnName = result.stringTable[result.functionTable[i]!.nameIndex];
          if (fnName && !fnName.endsWith('$set')) depNameToIndex.set(fnName, i);
        }
        for (const imp of program.imports) {
          if (imp.kind !== 'NamedImport' || imp.spec !== spec) continue;
          for (const s of imp.specs) {
            const depIdx = cachedSlots?.get(s.external) ?? depNameToIndex.get(s.external);
            if (depIdx !== undefined && exportSet.has(s.external)) {
              const setterIdx = result.varSetterIndices?.get(s.external);
              if (setterIdx !== undefined) {
                importedFunctionTable.push({ importIndex: specIndex, functionIndex: depIdx });
                importedFuncIds.set(s.local, mainFuncCount + importedFunctionTable.length - 1);
                importedThunkLocals.add(s.local);
                importedFunctionTable.push({ importIndex: specIndex, functionIndex: setterIdx });
                importedVarSetterIds.set(s.local, mainFuncCount + importedFunctionTable.length - 1);
              } else {
                importedFunctionTable.push({ importIndex: specIndex, functionIndex: depIdx });
                importedFuncIds.set(s.local, mainFuncCount + importedFunctionTable.length - 1);
                if (isExportThunk(depProgram, s.external)) importedThunkLocals.add(s.local);
              }
            }
          }
        }
      }
    }

    function arityOfNamedExport(result: CodegenResult, exportName: string): number {
      for (let i = 0; i < result.functionTable.length; i++) {
        const fnName = result.stringTable[result.functionTable[i]!.nameIndex];
        if (fnName === exportName && !fnName.endsWith('$set')) return result.functionTable[i]!.arity;
      }
      return 0;
    }

    for (const { exportName, spec, external } of tc.reexports) {
      if (tc.exportedConstructors.has(exportName)) continue;
      const specIndex = specs.indexOf(spec);
      if (specIndex < 0) continue;
      const dep = depResults.find((d) => d.spec === spec);
      if (!dep) continue;
      const t = tc.exports.get(exportName);
      if (t == null) continue;
      if (dep.fromTypesFile) {
        const exp = dep.nameToExport.get(external);
        if (exp === undefined) continue;
        if (exp.setter_index !== undefined) {
          importedFunctionTable.push({ importIndex: specIndex, functionIndex: exp.function_index });
          importedFuncIds.set(exportName, mainFuncCount + importedFunctionTable.length - 1);
          importedThunkLocals.add(exportName);
          importedFunctionTable.push({ importIndex: specIndex, functionIndex: exp.setter_index });
          importedVarSetterIds.set(exportName, mainFuncCount + importedFunctionTable.length - 1);
        } else {
          importedFunctionTable.push({ importIndex: specIndex, functionIndex: exp.function_index });
          importedFuncIds.set(exportName, mainFuncCount + importedFunctionTable.length - 1);
          if (exp.exportKind === 'val' || exp.exportKind === 'var') importedThunkLocals.add(exportName);
        }
      } else {
        const { result, exportSet, program: depProgram, path: depPathRe } = dep;
        if (!exportSet.has(external)) continue;
        const isExc = depProgram.body.some(
          (n): n is ExceptionDecl =>
            n != null && n.kind === 'ExceptionDecl' && n.exported && n.name === external,
        );
        if (isExc) continue;
        const cachedSlotsRe = cache.get(depPathRe)?.exportFunctionSlotByName;
        const depNameToIndex = new Map<string, number>();
        for (let i = 0; i < result.functionTable.length; i++) {
          const fnName = result.stringTable[result.functionTable[i]!.nameIndex];
          if (fnName && !fnName.endsWith('$set')) depNameToIndex.set(fnName, i);
        }
        const depIdx = cachedSlotsRe?.get(external) ?? depNameToIndex.get(external);
        if (depIdx === undefined) continue;
        const setterIdx = result.varSetterIndices?.get(external);
        if (setterIdx !== undefined) {
          importedFunctionTable.push({ importIndex: specIndex, functionIndex: depIdx });
          importedFuncIds.set(exportName, mainFuncCount + importedFunctionTable.length - 1);
          importedThunkLocals.add(exportName);
          importedFunctionTable.push({ importIndex: specIndex, functionIndex: setterIdx });
          importedVarSetterIds.set(exportName, mainFuncCount + importedFunctionTable.length - 1);
        } else {
          importedFunctionTable.push({ importIndex: specIndex, functionIndex: depIdx });
          importedFuncIds.set(exportName, mainFuncCount + importedFunctionTable.length - 1);
          if (isExportThunk(depProgram, external)) importedThunkLocals.add(exportName);
        }
      }
    }

    const namespaceFuncIds = new Map<string, Map<string, number>>();
    const namespaceVarSetterIds = new Map<string, Map<string, number>>();
    const namespaceThunkFields = new Map<string, Set<string>>();
    for (let specIndex = 0; specIndex < specs.length; specIndex++) {
      const spec = specs[specIndex]!;
      const dep = depResults.find((d) => d.spec === spec);
      if (!dep) continue;
      for (const imp of program.imports) {
        if (imp.kind !== 'NamespaceImport' || imp.spec !== spec) continue;
        const perNsFuncIds = new Map<string, number>();
        const perNsSetterIds = new Map<string, number>();
        const perNsThunks = new Set<string>();
        if (dep.fromTypesFile) {
          const { nameToExport } = dep;
          for (const [name, exp] of nameToExport) {
            if (exp.exportKind === 'val' || exp.exportKind === 'var') {
              perNsThunks.add(name);
            }
            if (exp.setter_index !== undefined) {
              importedFunctionTable.push({ importIndex: specIndex, functionIndex: exp.function_index });
              perNsFuncIds.set(name, mainFuncCount + importedFunctionTable.length - 1);
              importedFunctionTable.push({ importIndex: specIndex, functionIndex: exp.setter_index });
              perNsSetterIds.set(name, mainFuncCount + importedFunctionTable.length - 1);
            } else {
              importedFunctionTable.push({ importIndex: specIndex, functionIndex: exp.function_index });
              perNsFuncIds.set(name, mainFuncCount + importedFunctionTable.length - 1);
            }
          }
        } else {
          const { result, exportSet, program: depProgram, path: depPathNs } = dep;
          const cachedSlotsNs = cache.get(depPathNs)?.exportFunctionSlotByName;
          const depNameToIndex = new Map<string, number>();
          for (let i = 0; i < result.functionTable.length; i++) {
            const fnName = result.stringTable[result.functionTable[i]!.nameIndex];
            if (fnName && !fnName.endsWith('$set')) depNameToIndex.set(fnName, i);
          }
          for (const name of exportSet) {
            if (isExportThunk(depProgram, name)) {
              perNsThunks.add(name);
            }
            const depIdx = cachedSlotsNs?.get(name) ?? depNameToIndex.get(name);
            if (depIdx === undefined) continue;
            const setterIdx = result.varSetterIndices?.get(name);
            if (setterIdx !== undefined) {
              importedFunctionTable.push({ importIndex: specIndex, functionIndex: depIdx });
              perNsFuncIds.set(name, mainFuncCount + importedFunctionTable.length - 1);
              importedFunctionTable.push({ importIndex: specIndex, functionIndex: setterIdx });
              perNsSetterIds.set(name, mainFuncCount + importedFunctionTable.length - 1);
            } else {
              importedFunctionTable.push({ importIndex: specIndex, functionIndex: depIdx });
              perNsFuncIds.set(name, mainFuncCount + importedFunctionTable.length - 1);
            }
          }
        }
        namespaceFuncIds.set(imp.name, perNsFuncIds);
        if (perNsSetterIds.size > 0) namespaceVarSetterIds.set(imp.name, perNsSetterIds);
        if (perNsThunks.size > 0) namespaceThunkFields.set(imp.name, perNsThunks);
      }
    }

    const importExcByCanonical = new Map<string, Set<string>>();
    for (const row of exceptionImports) {
      let s = importExcByCanonical.get(row.canonical);
      if (!s) {
        s = new Set<string>();
        importExcByCanonical.set(row.canonical, s);
      }
      s.add(row.canonical);
      s.add(row.local);
    }
    const importedExceptions =
      importExcByCanonical.size > 0
        ? [...importExcByCanonical.entries()].map(([canonical, names]) => ({
            canonical,
            ctorNames: [...names],
          }))
        : undefined;

    const mainResult = codegen(program, {
      importedFuncIds,
      importedThunkLocals: importedThunkLocals.size > 0 ? importedThunkLocals : undefined,
      importedVarSetterIds: importedVarSetterIds.size > 0 ? importedVarSetterIds : undefined,
      localFuncCount: mainFuncCount,
      namespaceFuncIds: namespaceFuncIds.size > 0 ? namespaceFuncIds : undefined,
      namespaceVarSetterIds: namespaceVarSetterIds.size > 0 ? namespaceVarSetterIds : undefined,
      namespaceThunkFields: namespaceThunkFields.size > 0 ? namespaceThunkFields : undefined,
      namespaceImportConstructors:
        namespaceImportConstructors.size > 0 ? namespaceImportConstructors : undefined,
      importedExceptions,
      sourceFile: filePath,
      importSpecifierOrder: specs,
    });
    mainResult.importedFunctionTable = importedFunctionTable;

    const exportFunctionSlotByName = new Map<string, number>();
    for (const [name, slot] of importedFuncIds) {
      if (tc.exports.has(name) && !tc.exportedConstructors.has(name)) {
        exportFunctionSlotByName.set(name, slot);
      }
    }
    for (let i = 0; i < mainResult.functionTable.length; i++) {
      const n = mainResult.stringTable[mainResult.functionTable[i]!.nameIndex];
      if (!n || n === '<lambda>' || n.endsWith('$set')) continue;
      if (tc.exports.has(n) && !tc.exportedConstructors.has(n) && !exportFunctionSlotByName.has(n)) {
        exportFunctionSlotByName.set(n, i);
      }
    }

    if (getOutputPaths) {
      const paths = getOutputPaths(filePath);
      mkdirSync(dirname(paths.kbc), { recursive: true });
      const kbcBytes = writeKbc(
        mainResult.stringTable,
        mainResult.constantPool,
        mainResult.code,
        mainResult.functionTable,
        mainResult.importSpecifierIndices,
        mainResult.importedFunctionTable ?? [],
        mainResult.shapes,
        mainResult.adts,
        mainResult.nGlobals ?? 0,
        mainResult.debugFileStringIndices ?? [],
        mainResult.debugEntries ?? []
      );
      writeFileSync(paths.kbc, kbcBytes);
      const exportKind = new Map<string, 'function' | 'val' | 'var'>();
      for (const node of program.body) {
        if (!node) continue;
        if (node.kind === 'FunDecl' && node.exported) exportKind.set(node.name, 'function');
        if (node.kind === 'ValDecl') exportKind.set(node.name, 'val');
        if (node.kind === 'VarDecl') exportKind.set(node.name, 'var');
      }
      const typeExports = new Map<string, TypesFileExportInput>();
      for (let i = 0; i < mainResult.functionTable.length; i++) {
        const name = mainResult.stringTable[mainResult.functionTable[i]!.nameIndex];
        const t = tc.exports.get(name);
        if (name && t) {
          const kind = exportKind.get(name) ?? 'function';
          const entry: TypesFileExportInput = {
            kind,
            function_index: i,
            arity: mainResult.functionTable[i]!.arity,
            type: t,
          };
          if (kind === 'var') entry.setter_index = mainResult.varSetterIndices?.get(name);
          typeExports.set(name, entry);
        }
      }
      for (const node of program.body) {
        if (node?.kind === 'ExceptionDecl' && node.exported) {
          const t = tc.exports.get(node.name);
          if (t != null) {
            typeExports.set(node.name, { kind: 'exception', function_index: 0, arity: 0, type: t });
          }
        }
      }
      for (const node of program.body) {
        if (node == null || node.kind !== 'TypeDecl') continue;
        const td = node as TypeDecl;
        if (td.visibility !== 'export' || td.body.kind !== 'ADTBody') continue;
        const adtId = adtBytecodeIndex(mainResult, td.name);
        for (let ci = 0; ci < td.body.constructors.length; ci++) {
          const c = td.body.constructors[ci]!;
          const t = tc.exportedConstructors.get(c.name);
          if (t == null) continue;
          typeExports.set(c.name, {
            kind: 'constructor',
            function_index: 0,
            arity: c.params.length,
            adt_id: adtId,
            ctor_index: ci,
            type: t,
          });
        }
      }
      for (const { exportName, spec, external } of tc.reexports) {
        if (typeExports.has(exportName)) continue;
        const t = tc.exports.get(exportName);
        if (t == null) continue;
        const dep = depResults.find((d) => d.spec === spec);
        if (!dep) continue;
        if (tc.exportedConstructors.has(exportName)) {
          const origin = resolveExportedCtorOrigin(filePath, exportName, new Set());
          if (origin == null) continue;
          const adtId = adtBytecodeIndex(origin.bytecode, origin.adtName);
          const ci = origin.ctorIndex;
          const arity = ctorArityInProgram(origin.program, origin.adtName, ci);
          typeExports.set(exportName, {
            kind: 'constructor',
            function_index: 0,
            arity,
            adt_id: adtId,
            ctor_index: ci,
            type: tc.exportedConstructors.get(exportName)!,
          });
          continue;
        }
        if (dep.fromTypesFile && dep.exceptionExportNames.has(external)) {
          typeExports.set(exportName, { kind: 'exception', function_index: 0, arity: 0, type: t });
          continue;
        }
        if (!dep.fromTypesFile) {
          const isExc = dep.program.body.some(
            (n): n is ExceptionDecl =>
              n != null && n.kind === 'ExceptionDecl' && n.exported && n.name === external,
          );
          if (isExc) {
            typeExports.set(exportName, { kind: 'exception', function_index: 0, arity: 0, type: t });
            continue;
          }
        }
        const fnIdx = importedFuncIds.get(exportName);
        if (fnIdx === undefined) continue;
        if (dep.fromTypesFile) {
          const exp = dep.nameToExport.get(external);
          if (exp == null) continue;
          const entry: TypesFileExportInput = {
            kind: exp.exportKind,
            function_index: fnIdx,
            arity: exp.arity,
            type: t,
          };
          if (exp.exportKind === 'var' && exp.setter_index !== undefined) {
            entry.setter_index = importedVarSetterIds.get(exportName);
          }
          typeExports.set(exportName, entry);
        } else {
          let kind: 'function' | 'val' | 'var' = 'function';
          if (isExportThunk(dep.program, external)) {
            kind = dep.program.body.some((n) => n != null && n.kind === 'VarDecl' && n.name === external)
              ? 'var'
              : 'val';
          }
          const entry: TypesFileExportInput = {
            kind,
            function_index: fnIdx,
            arity: arityOfNamedExport(dep.result, external),
            type: t,
          };
          if (kind === 'var') entry.setter_index = importedVarSetterIds.get(exportName);
          typeExports.set(exportName, entry);
        }
      }
      writeTypesFile(paths.kti, typeExports, tc.exportedTypeAliases, tc.exportedTypeVisibility);
    }

    const runtimeKsPathForDeps = pathResolve(stdlibDir, 'kestrel/runtime.ks');
    if (getOutputPaths && existsSync(runtimeKsPathForDeps) && filePath !== runtimeKsPathForDeps) {
      // Only compile runtime.ks if its .kti is stale; otherwise reuse the cached bytecode
      // to avoid updating runtime.kbc's timestamp and cascading recompilation.
      const rtPaths = getOutputPaths(runtimeKsPathForDeps);
      if (!isTypesFileFresh(rtPaths.kti, runtimeKsPathForDeps, rtPaths.kbc)) {
        const rtOut = compileOne(runtimeKsPathForDeps);
        if (!rtOut.ok) {
          visited.delete(filePath);
          return rtOut;
        }
      }
    }

    const dependencyPaths = [
      filePath,
      ...depResults.flatMap((d) => {
        if ('dependencyPaths' in d) {
          if (getOutputPaths) {
            const depKbc = getOutputPaths(d.path).kbc;
            return [d.path, depKbc, ...d.dependencyPaths];
          }
          return [d.path, ...d.dependencyPaths];
        }
        const transitive: string[] = [];
        if (getOutputPaths) {
          const depPaths = getOutputPaths(d.path);
          const depsFile = depPaths.kbc + '.deps';
          if (existsSync(depsFile)) {
            try {
              const content = readFileSync(depsFile, 'utf-8');
              for (const line of content.split('\n')) {
                const p = line.trim();
                if (p) transitive.push(p);
              }
            } catch {
              /* ignore */
            }
          }
          return [d.path, depPaths.kbc, ...transitive];
        }
        return [d.path, ...transitive];
      }),
    ];
    if (getOutputPaths && existsSync(runtimeKsPathForDeps)) {
      const rp = getOutputPaths(runtimeKsPathForDeps);
      if (!dependencyPaths.includes(runtimeKsPathForDeps)) dependencyPaths.push(runtimeKsPathForDeps);
      if (!dependencyPaths.includes(rp.kbc)) dependencyPaths.push(rp.kbc);
    }
    const dependencyPathsUnique = uniqueDependencyPaths(dependencyPaths);
    if (getOutputPaths) {
      const paths = getOutputPaths(filePath);
      writeFileSync(paths.kbc + '.deps', dependencyPathsUnique.join('\n') + '\n');
    }
    cache.set(filePath, {
      program,
      exports: tc.exports,
      exportedTypeAliases: tc.exportedTypeAliases,
      exportedConstructors: tc.exportedConstructors,
      codegenResult: mainResult,
      dependencyPaths: dependencyPathsUnique,
      exportFunctionSlotByName,
    });
    visited.delete(filePath);
    const durationMs = Math.round(performance.now() - compileStart);
    // Report every file we compile (so incremental runs show full chain: e.g. m3, m2, hello)
    onCompilingFile?.(filePath, durationMs);
    return {
      ok: true,
      program,
      exports: tc.exports,
      exportedTypeAliases: tc.exportedTypeAliases,
      exportedConstructors: tc.exportedConstructors,
      exportedTypeVisibility: tc.exportedTypeVisibility,
      codegenResult: mainResult,
      dependencyPaths: dependencyPathsUnique,
      exportFunctionSlotByName,
    };
  }

  const out = compileOne(absPath);
  if (!out.ok) return out;

  const kbc = writeKbc(
    out.codegenResult.stringTable,
    out.codegenResult.constantPool,
    out.codegenResult.code,
    out.codegenResult.functionTable,
    out.codegenResult.importSpecifierIndices,
    out.codegenResult.importedFunctionTable ?? [],
    out.codegenResult.shapes,
    out.codegenResult.adts,
    out.codegenResult.nGlobals ?? 0,
    out.codegenResult.debugFileStringIndices ?? [],
    out.codegenResult.debugEntries ?? []
  );

  return { ok: true, kbc, dependencyPaths: out.dependencyPaths };
}
