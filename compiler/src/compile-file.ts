/**
 * Multi-module compilation: resolve imports, compile dependencies, bundle.
 */
import { readFileSync, existsSync } from 'fs';
import { resolve as pathResolve, dirname } from 'path';
import { tokenize } from './lexer/index.js';
import { parse } from './parser/index.js';
import { typecheck, type TypecheckOptions } from './typecheck/check.js';
import { codegen, type CodegenResult } from './codegen/codegen.js';
import { writeKbc } from './bytecode/write.js';
import { resolveSpecifier } from './resolve.js';
import { bundleCodegenResults } from './bundle.js';
import type { Program, ImportDecl } from './ast/nodes.js';
import type { InternalType } from './types/internal.js';

export interface CompileFileOptions {
  /** Project root (for stdlib resolution). Default: process.cwd() */
  projectRoot?: string;
  /** Path to stdlib directory. Default: projectRoot/stdlib */
  stdlibDir?: string;
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

/** Export set: names we consider exported (top-level FunDecl). */
function getExportSet(program: Program): Set<string> {
  const names = new Set<string>();
  for (const node of program.body) {
    if (node.kind === 'FunDecl') names.add(node.name);
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

export function compileFile(
  inputPath: string,
  options?: CompileFileOptions
): { ok: true; kbc: Uint8Array } | { ok: false; errors: string[] } {
  const projectRoot = options?.projectRoot ?? process.cwd();
  const stdlibDir = options?.stdlibDir ?? pathResolve(projectRoot, 'stdlib');
  const absPath = pathResolve(inputPath);

  const visited = new Set<string>();
  const cache = new Map<string, { program: Program; exports: Map<string, InternalType>; codegenResult: CodegenResult }>();

  function compileOne(filePath: string): { ok: true; program: Program; exports: Map<string, InternalType>; codegenResult: CodegenResult } | { ok: false; errors: string[] } {
    if (visited.has(filePath)) {
      return { ok: false, errors: [`Circular import: ${filePath}`] };
    }
    visited.add(filePath);

    const cached = cache.get(filePath);
    if (cached) return { ok: true, ...cached };

    let source: string;
    try {
      source = readFileSync(filePath, 'utf-8');
    } catch {
      return { ok: false, errors: [`Cannot read file: ${filePath}`] };
    }

    const tokens = tokenize(source);
    const program = parse(tokens);

    const resolveOpts = { fromFile: filePath, projectRoot, stdlibDir };
    const specs = getDistinctSpecifiers(program);

    const resolved = new Map<string, string>();
    for (const spec of specs) {
      const r = resolveSpecifier(spec, resolveOpts);
      if (!r.ok) return { ok: false, errors: [r.error] };
      resolved.set(spec, r.path);
    }

    const importBindings = new Map<string, InternalType>();
    const depResults: { spec: string; path: string; result: CodegenResult; exportSet: Set<string> }[] = [];

    for (const spec of specs) {
      const depPath = resolved.get(spec)!;
      const depOut = compileOne(depPath);
      if (!depOut.ok) return depOut;

      const depExports = depOut.exports;
      const depExportSet = new Set(depExports.keys());

      for (const imp of program.imports) {
        if (imp.spec !== spec) continue;
        const requested = getRequestedImports(imp);
        for (const [localName, externalName] of requested) {
          const t = depExports.get(externalName);
          if (t == null) {
            return { ok: false, errors: [`Module ${spec} does not export ${externalName}`] };
          }
          importBindings.set(localName, t);
        }
      }

      depResults.push({
        spec,
        path: depPath,
        result: depOut.codegenResult,
        exportSet: depExportSet,
      });
    }

    const tcOpts: TypecheckOptions = { importBindings: importBindings.size > 0 ? importBindings : undefined, captureExports: true };
    const tc = typecheck(program, tcOpts);
    if (!tc.ok) return { ok: false, errors: tc.errors };
    if (!tc.exports) return { ok: false, errors: ['Typecheck did not return exports'] };

    const mainFuncCount = program.body.filter((n) => n.kind === 'FunDecl').length;
    const importedFuncIds = new Map<string, number>();
    let funcOffset = mainFuncCount;
    for (const { spec, result, exportSet } of depResults) {
      const depNameToIndex = new Map<string, number>();
      for (let i = 0; i < result.functionTable.length; i++) {
        const fnName = result.stringTable[result.functionTable[i]!.nameIndex];
        if (fnName) depNameToIndex.set(fnName, i);
      }
      for (const imp of program.imports) {
        if (imp.kind !== 'NamedImport' || imp.spec !== spec) continue;
        for (const s of imp.specs) {
          const depIdx = depNameToIndex.get(s.external);
          if (depIdx !== undefined && exportSet.has(s.external)) {
            importedFuncIds.set(s.local, funcOffset + depIdx);
          }
        }
      }
      funcOffset += result.functionTable.length;
    }

    const mainResult = codegen(program, { importedFuncIds });
    const bundled = depResults.length > 0
      ? bundleCodegenResults(mainResult, depResults.map((d) => d.result))
      : mainResult;

    cache.set(filePath, { program, exports: tc.exports, codegenResult: bundled });
    visited.delete(filePath);
    return { ok: true, program, exports: tc.exports, codegenResult: bundled };
  }

  const out = compileOne(absPath);
  if (!out.ok) return out;

  const kbc = writeKbc(
    out.codegenResult.stringTable,
    out.codegenResult.constantPool,
    out.codegenResult.code,
    out.codegenResult.functionTable,
    out.codegenResult.importSpecifierIndices,
    out.codegenResult.shapes,
    out.codegenResult.adts
  );

  return { ok: true, kbc };
}
