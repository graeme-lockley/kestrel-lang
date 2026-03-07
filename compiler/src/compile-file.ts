/**
 * Multi-module compilation: resolve imports, emit one .kbc + .kti per package (07 §5).
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs';
import { resolve as pathResolve, dirname } from 'path';
import { tokenize } from './lexer/index.js';
import { parse, ParseError } from './parser/index.js';
import { typecheck, type TypecheckOptions } from './typecheck/check.js';
import { codegen, type CodegenResult } from './codegen/codegen.js';
import { writeKbc, type ImportedFunctionEntry } from './bytecode/write.js';
import { resolveSpecifier } from './resolve.js';
import { readTypesFile, writeTypesFile, isTypesFileFresh } from './types-file.js';
import type { Program, ImportDecl, Expr } from './ast/nodes.js';
import type { InternalType } from './types/internal.js';
import type { Diagnostic } from './diagnostics/types.js';
import { CODES, locationFromSpan, locationFileOnly } from './diagnostics/types.js';
import type { Span } from './lexer/types.js';

/** Count all LambdaExpr nodes in an expression tree (used to predict function table size). */
function countLambdasInExpr(e: Expr): number {
  switch (e.kind) {
    case 'LambdaExpr': return 1 + countLambdasInExpr(e.body);
    case 'CallExpr': return countLambdasInExpr(e.callee) + e.args.reduce((n, a) => n + countLambdasInExpr(a), 0);
    case 'BinaryExpr': return countLambdasInExpr(e.left) + countLambdasInExpr(e.right);
    case 'UnaryExpr': return countLambdasInExpr(e.operand);
    case 'IfExpr': return countLambdasInExpr(e.cond) + countLambdasInExpr(e.then) + (e.else !== undefined ? countLambdasInExpr(e.else) : 0);
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
    case 'BlockExpr': {
      let n = countLambdasInExpr(e.result);
      for (const s of e.stmts) {
        if (s.kind === 'ExprStmt') n += countLambdasInExpr(s.expr);
        else if (s.kind === 'AssignStmt') n += countLambdasInExpr(s.target) + countLambdasInExpr(s.value);
        else if (s.kind === 'FunStmt') n += 1 + countLambdasInExpr(s.body);
        else n += countLambdasInExpr(s.value);
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

function getDistinctSpecifiers(program: Program): string[] {
  const seen = new Set<string>();
  const specs: string[] = [];
  for (const imp of program.imports) {
    const spec = imp.spec;
    if (!seen.has(spec)) {
      seen.add(spec);
      specs.push(spec);
    }
  }
  return specs;
}

/** Export set: names we consider exported (top-level FunDecl, ValDecl, VarDecl, TypeDecl). */
function getExportSet(program: Program): Set<string> {
  const names = new Set<string>();
  for (const node of program.body) {
    if (!node) continue;
    if (node.kind === 'FunDecl' && node.exported) names.add(node.name);
    else if (node.kind === 'TypeDecl' && node.visibility === 'export') names.add(node.name);
    else if (node.kind === 'ValDecl' || node.kind === 'VarDecl') names.add(node.name);
  }
  return names;
}

/** Build import bindings from NamedImport: localName -> must be in dep's exports. */
function getRequestedImports(imp: ImportDecl): Map<string, string> {
  const m = new Map<string, string>();
  if (imp.kind === 'NamedImport') {
    for (const s of imp.specs) m.set(s.local, s.external);
  }
  return m;
}

function diag(file: string, code: string, message: string, span?: Span): Diagnostic {
  return {
    severity: 'error',
    code,
    message,
    location: span ? locationFromSpan(file, span) : locationFileOnly(file),
  };
}

export function compileFile(
  inputPath: string,
  options?: CompileFileOptions
): { ok: true; kbc: Uint8Array; dependencyPaths: string[] } | { ok: false; diagnostics: Diagnostic[] } {
  const projectRoot = options?.projectRoot ?? process.cwd();
  const stdlibDir = options?.stdlibDir ?? pathResolve(projectRoot, 'stdlib');
  const absPath = pathResolve(inputPath);

  const visited = new Set<string>();
  const cache = new Map<string, { program: Program; exports: Map<string, InternalType>; exportedTypeAliases: Map<string, InternalType>; codegenResult: CodegenResult; dependencyPaths: string[] }>();
  const onCompilingFile = options?.onCompilingFile;
  const stalePaths = options?.stalePaths;

  function compileOne(filePath: string): { ok: true; program: Program; exports: Map<string, InternalType>; exportedTypeAliases: Map<string, InternalType>; exportedTypeVisibility?: Map<string, 'local' | 'opaque' | 'export'>; codegenResult: CodegenResult; dependencyPaths: string[] } | { ok: false; diagnostics: Diagnostic[] } {
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
    let program: Program;
    try {
      program = parse(tokens);
    } catch (e) {
      if (e instanceof ParseError) {
        return {
          ok: false,
          diagnostics: [{
            severity: 'error',
            code: CODES.parse.unexpected_token,
            message: e.message,
            location: { file: filePath, line: e.line, column: e.column, offset: e.offset },
          }],
        };
      }
      throw e;
    }

    const resolveOpts = { fromFile: filePath, projectRoot, stdlibDir };
    const specs = getDistinctSpecifiers(program);

    const resolved = new Map<string, string>();
    for (const spec of specs) {
      const r = resolveSpecifier(spec, resolveOpts);
      if (!r.ok) {
        const imp = program.imports.find((i) => i.spec === spec);
        return { ok: false, diagnostics: [diag(filePath, CODES.resolve.module_not_found, r.error, (imp as { span?: Span })?.span)] };
      }
      resolved.set(spec, r.path);
    }

    const getOutputPaths = options?.getOutputPaths;
    const importBindings = new Map<string, InternalType>();
    const typeAliasBindings = new Map<string, InternalType>();
    const importOpaqueTypes = new Set<string>();
    type DepResult =
      | { spec: string; path: string; result: CodegenResult; exportSet: Set<string>; dependencyPaths: string[]; fromTypesFile?: false }
      | { spec: string; path: string; exportSet: Set<string>; nameToExport: Map<string, { function_index: number; arity: number; type: InternalType; setter_index?: number }>; fromTypesFile: true };
    const depResults: DepResult[] = [];

    for (const spec of specs) {
      const depPath = resolved.get(spec)!;
      let usedTypesFile = false;
      if (getOutputPaths) {
        const paths = getOutputPaths(depPath);
        if (isTypesFileFresh(paths.kti, depPath)) {
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
            const nameToExport = new Map<string, { function_index: number; arity: number; type: InternalType; setter_index?: number }>();
            for (const [name, exp] of typesExports) {
              if (exp.kind === 'function' || exp.kind === 'val' || exp.kind === 'var') {
                const entry: { function_index: number; arity: number; type: InternalType; setter_index?: number } = { function_index: exp.function_index, arity: exp.arity, type: exp.type };
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
                  return { ok: false, diagnostics: [diag(filePath, CODES.export.not_exported, `Module ${spec} does not export ${externalName}`, (imp as { span?: Span })?.span)] };
                }
                if (ta != null) {
                  typeAliasBindings.set(localName, ta.type);
                  if (ta.opaque) {
                    importOpaqueTypes.add(localName);
                  }
                } else if (exp != null && (exp.kind === 'function' || exp.kind === 'val' || exp.kind === 'var')) {
                  importBindings.set(localName, exp.type);
                }
              }
            }
            depResults.push({ spec, path: depPath, exportSet, nameToExport, fromTypesFile: true });
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
        const depExportSet = new Set(depOut.exports.keys());
        for (const imp of program.imports) {
          if (imp.spec !== spec) continue;
          const requested = getRequestedImports(imp);
          for (const [localName, externalName] of requested) {
            const t = depOut.exports.get(externalName);
            if (t == null) {
              const imp = program.imports.find((i) => i.spec === spec);
              return { ok: false, diagnostics: [diag(filePath, CODES.export.not_exported, `Module ${spec} does not export ${externalName}`, (imp as { span?: Span })?.span)] };
            }
            if (depOut.exportedTypeAliases.has(externalName)) {
              typeAliasBindings.set(localName, t);
              if (depOut.exportedTypeVisibility?.get(externalName) === 'opaque') {
                importOpaqueTypes.add(localName);
              }
            } else {
              importBindings.set(localName, t);
            }
          }
        }
        depResults.push({
          spec,
          path: depPath,
          result: depOut.codegenResult,
          exportSet: depExportSet,
          dependencyPaths: depOut.dependencyPaths,
        });
      }
    }

    const tcOpts: TypecheckOptions = {
      importBindings: importBindings.size > 0 ? importBindings : undefined,
      typeAliasBindings: typeAliasBindings.size > 0 ? typeAliasBindings : undefined,
      importOpaqueTypes: importOpaqueTypes.size > 0 ? importOpaqueTypes : undefined,
      sourceFile: filePath,
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
                importedFunctionTable.push({ importIndex: specIndex, functionIndex: exp.setter_index });
                importedVarSetterIds.set(s.local, mainFuncCount + importedFunctionTable.length - 1);
              } else {
                importedFunctionTable.push({ importIndex: specIndex, functionIndex: exp.function_index });
                importedFuncIds.set(s.local, mainFuncCount + importedFunctionTable.length - 1);
              }
            }
          }
        }
      } else {
        const { result, exportSet } = dep;
        const depNameToIndex = new Map<string, number>();
        for (let i = 0; i < result.functionTable.length; i++) {
          const fnName = result.stringTable[result.functionTable[i]!.nameIndex];
          if (fnName && !fnName.endsWith('$set')) depNameToIndex.set(fnName, i);
        }
        for (const imp of program.imports) {
          if (imp.kind !== 'NamedImport' || imp.spec !== spec) continue;
          for (const s of imp.specs) {
            const depIdx = depNameToIndex.get(s.external);
            if (depIdx !== undefined && exportSet.has(s.external)) {
              const setterIdx = result.varSetterIndices?.get(s.external);
              if (setterIdx !== undefined) {
                importedFunctionTable.push({ importIndex: specIndex, functionIndex: depIdx });
                importedFuncIds.set(s.local, mainFuncCount + importedFunctionTable.length - 1);
                importedFunctionTable.push({ importIndex: specIndex, functionIndex: setterIdx });
                importedVarSetterIds.set(s.local, mainFuncCount + importedFunctionTable.length - 1);
              } else {
                importedFunctionTable.push({ importIndex: specIndex, functionIndex: depIdx });
                importedFuncIds.set(s.local, mainFuncCount + importedFunctionTable.length - 1);
              }
            }
          }
        }
      }
    }

    const mainResult = codegen(program, { importedFuncIds, importedVarSetterIds: importedVarSetterIds.size > 0 ? importedVarSetterIds : undefined });
    mainResult.importedFunctionTable = importedFunctionTable;

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
        mainResult.nGlobals ?? 0
      );
      writeFileSync(paths.kbc, kbcBytes);
      const exportKind = new Map<string, 'function' | 'val' | 'var'>();
      for (const node of program.body) {
        if (!node) continue;
        if (node.kind === 'FunDecl' && node.exported) exportKind.set(node.name, 'function');
        if (node.kind === 'ValDecl') exportKind.set(node.name, 'val');
        if (node.kind === 'VarDecl') exportKind.set(node.name, 'var');
      }
      const typeExports = new Map<string, { kind: 'function' | 'val' | 'var'; function_index: number; arity: number; type: InternalType; setter_index?: number }>();
      for (let i = 0; i < mainResult.functionTable.length; i++) {
        const name = mainResult.stringTable[mainResult.functionTable[i]!.nameIndex];
        const t = tc.exports.get(name);
        if (name && t) {
          const kind = exportKind.get(name) ?? 'function';
          const entry: { kind: 'function' | 'val' | 'var'; function_index: number; arity: number; type: InternalType; setter_index?: number } = {
            kind,
            function_index: i,
            arity: mainResult.functionTable[i]!.arity,
            type: t,
          };
          if (kind === 'var') entry.setter_index = mainResult.varSetterIndices?.get(name);
          typeExports.set(name, entry);
        }
      }
      writeTypesFile(paths.kti, typeExports, tc.exportedTypeAliases, tc.exportedTypeVisibility);
    }

    const dependencyPaths = [
      filePath,
      ...depResults.flatMap((d) => {
        if ('dependencyPaths' in d) return [d.path, ...d.dependencyPaths];
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
        }
        return [d.path, ...transitive];
      }),
    ];
    if (getOutputPaths) {
      const paths = getOutputPaths(filePath);
      writeFileSync(paths.kbc + '.deps', dependencyPaths.join('\n') + '\n');
    }
    cache.set(filePath, { program, exports: tc.exports, exportedTypeAliases: tc.exportedTypeAliases, codegenResult: mainResult, dependencyPaths });
    visited.delete(filePath);
    const durationMs = Math.round(performance.now() - compileStart);
    // Report every file we compile (so incremental runs show full chain: e.g. m3, m2, hello)
    onCompilingFile?.(filePath, durationMs);
    return { ok: true, program, exports: tc.exports, exportedTypeAliases: tc.exportedTypeAliases, exportedTypeVisibility: tc.exportedTypeVisibility, codegenResult: mainResult, dependencyPaths };
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
    out.codegenResult.nGlobals ?? 0
  );

  return { ok: true, kbc, dependencyPaths: out.dependencyPaths };
}
