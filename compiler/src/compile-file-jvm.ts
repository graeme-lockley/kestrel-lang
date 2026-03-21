/**
 * Multi-module JVM compilation: resolve imports, emit .class files per module.
 * Modeled on compile-file.ts but uses jvmCodegen and writes .class + inner classes.
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs';
import { resolve as pathResolve, dirname } from 'path';
import { tokenize } from './lexer/index.js';
import { parse } from './parser/index.js';
import { typecheck, type TypecheckOptions } from './typecheck/check.js';
import { jvmCodegen, type JvmCodegenResult } from './jvm-codegen/index.js';
import { resolveSpecifier } from './resolve.js';
import type { Program, ImportDecl } from './ast/nodes.js';
import type { InternalType } from './types/internal.js';
import type { Diagnostic } from './diagnostics/types.js';
import { CODES, locationFromSpan, locationFileOnly } from './diagnostics/types.js';
import type { Span } from './lexer/types.js';

export interface CompileFileJvmOptions {
  projectRoot?: string;
  stdlibDir?: string;
  onCompilingFile?: (absolutePath: string, durationMs: number) => void;
  stalePaths?: Set<string>;
  /** Return class output directory for a source path. Writes <classDir>/<ClassName>.class and inner classes. */
  getClassOutputDir?: (sourcePath: string) => string;
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

/**
 * Derive JVM internal class name from the absolute source path.
 * Example:
 * - /Users/me/proj/mandelbrot.ks -> Users/me/proj/Mandelbrot
 *
 * This is intentionally stable regardless of:
 * - whether the file is an entry vs dependency
 * - the current working directory
 */
function classNameForPath(absolutePath: string): string {
  const normalized = pathResolve(absolutePath).replace(/\\/g, '/');
  const rel = normalized.startsWith('/') ? normalized.slice(1) : normalized;
  const withoutExt = rel.endsWith('.ks') ? rel.slice(0, -3) : rel;
  const parts = withoutExt.split('/');
  const last = parts[parts.length - 1] ?? '';
  const cap = last.charAt(0).toUpperCase() + last.slice(1);
  if (parts.length === 1) return cap;
  return parts.slice(0, -1).join('/') + '/' + cap;
}

export function compileFileJvm(
  inputPath: string,
  options?: CompileFileJvmOptions
): { ok: true; classDir: string; mainClass: string; dependencyPaths: string[] } | { ok: false; diagnostics: Diagnostic[] } {
  const projectRoot = options?.projectRoot ?? process.cwd();
  const stdlibDir = options?.stdlibDir ?? pathResolve(projectRoot, 'stdlib');
  const absPath = pathResolve(inputPath);

  const visited = new Set<string>();
  const cache = new Map<
    string,
    {
      program: Program;
      jvmResult: JvmCodegenResult;
      dependencyPaths: string[];
      className: string;
      exports: Map<string, InternalType>;
      exportedTypeAliases: Map<string, InternalType>;
      exportedTypeVisibility?: Map<string, 'local' | 'opaque' | 'export'>;
    }
  >();
  const onCompilingFile = options?.onCompilingFile;
  const stalePaths = options?.stalePaths;
  const getClassOutputDir = options?.getClassOutputDir;

  function compileOne(
    filePath: string
  ): {
    ok: true;
    program: Program;
    jvmResult: JvmCodegenResult;
    dependencyPaths: string[];
    className: string;
    exports: Map<string, InternalType>;
    exportedTypeAliases: Map<string, InternalType>;
    exportedTypeVisibility?: Map<string, 'local' | 'opaque' | 'export'>;
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
    const specs = getDistinctSpecifiers(program);
    const resolved = new Map<string, string>();
    for (const spec of specs) {
      const r = resolveSpecifier(spec, resolveOpts);
      if (!r.ok) {
        const imp = program.imports.find((i) => i.spec === spec);
        return { ok: false, diagnostics: [diag(filePath, CODES.resolve.module_not_found, r.error, (imp as { span?: Span })?.span, source)] };
      }
      resolved.set(spec, r.path);
    }

    const importBindings = new Map<string, InternalType>();
    const typeAliasBindings = new Map<string, InternalType>();
    const importOpaqueTypes = new Set<string>();
    const depResults: {
      spec: string;
      path: string;
      className: string;
      exportSet: Set<string>;
      dependencyPaths: string[];
    }[] = [];

    for (const spec of specs) {
      const depPath = resolved.get(spec)!;
      const depOut = compileOne(depPath);
      if (!depOut.ok) return depOut;
      const depClassName = depOut.className;
      const depExportSet = getExportSet(depOut.program);

      for (const imp of program.imports) {
        if (imp.kind !== 'NamedImport' || imp.spec !== spec) continue;
        const requested = getRequestedImports(imp);
        for (const [localName, externalName] of requested) {
          if (!depExportSet.has(externalName)) {
            const impNode = program.imports.find((i) => i.spec === spec);
            return { ok: false, diagnostics: [diag(filePath, CODES.export.not_exported, `Module ${spec} does not export ${externalName}`, (impNode as { span?: Span })?.span, source)] };
          }
          const t = depOut.exports.get(externalName);
          if (t != null) {
            if (depOut.exportedTypeAliases.has(externalName)) {
              typeAliasBindings.set(localName, t);
              if (depOut.exportedTypeVisibility?.get(externalName) === 'opaque') importOpaqueTypes.add(localName);
            } else {
              importBindings.set(localName, t);
            }
          }
        }
      }
      for (const imp of program.imports) {
        if (imp.kind !== 'NamespaceImport' || imp.spec !== spec) continue;
        const bindings = new Map<string, InternalType>();
        for (const [name, t] of depOut.exports) bindings.set(name, t);
        for (const [name, t] of depOut.exportedTypeAliases) bindings.set(name, t);
        importBindings.set(imp.name, { kind: 'namespace', bindings });
      }
      depResults.push({
        spec,
        path: depPath,
        className: depClassName,
        exportSet: depExportSet,
        dependencyPaths: depOut.dependencyPaths,
      });
    }

    const tcOpts: TypecheckOptions = {
      importBindings: importBindings.size > 0 ? importBindings : undefined,
      typeAliasBindings: typeAliasBindings.size > 0 ? typeAliasBindings : undefined,
      importOpaqueTypes: importOpaqueTypes.size > 0 ? importOpaqueTypes : undefined,
      sourceFile: filePath,
      sourceContent: source,
    };
    const tc = typecheck(program, tcOpts);
    if (!tc.ok) return { ok: false, diagnostics: tc.diagnostics };

    const className = classNameForPath(filePath);

    const importClasses = new Map<string, string>();
    const namespaceClasses = new Map<string, string>();
    const importedNameToClass = new Map<string, string>();
    const importedNameToOriginal = new Map<string, string>();
    const importedValVarToClass = new Map<string, string>();

    function isValOrVar(prog: Program, name: string): boolean {
      for (const node of prog.body) {
        if (!node) continue;
        if ((node.kind === 'ValDecl' || node.kind === 'VarDecl') && node.name === name) return true;
      }
      return false;
    }

    for (const dep of depResults) {
      const depProg = cache.get(dep.path)?.program;
      importClasses.set(dep.spec, dep.className);
      for (const imp of program.imports) {
        if (imp.kind === 'NamedImport' && imp.spec === dep.spec) {
          for (const s of imp.specs) {
            if (dep.exportSet.has(s.external)) {
              importedNameToClass.set(s.local, dep.className);
              importedNameToOriginal.set(s.local, s.external);
              if (depProg && isValOrVar(depProg, s.external)) importedValVarToClass.set(s.local, dep.className);
            }
          }
        }
        if (imp.kind === 'NamespaceImport' && imp.spec === dep.spec) {
          namespaceClasses.set(imp.name, dep.className);
        }
      }
    }

    const jvmResult = jvmCodegen(program, {
      sourceFile: filePath,
      className,
      importClasses: importClasses.size > 0 ? importClasses : undefined,
      namespaceClasses: namespaceClasses.size > 0 ? namespaceClasses : undefined,
      importedNameToClass: importedNameToClass.size > 0 ? importedNameToClass : undefined,
      importedNameToOriginal: importedNameToOriginal.size > 0 ? importedNameToOriginal : undefined,
      importedValVarToClass: importedValVarToClass.size > 0 ? importedValVarToClass : undefined,
    });

    const dependencyPaths = [
      filePath,
      ...depResults.flatMap((d) => [d.path, ...d.dependencyPaths]),
    ];

    if (getClassOutputDir) {
      const classDir = getClassOutputDir(filePath);
      mkdirSync(classDir, { recursive: true });
      const mainClassPath = pathResolve(classDir, jvmResult.className + '.class');
      mkdirSync(dirname(mainClassPath), { recursive: true });
      writeFileSync(mainClassPath, jvmResult.classBytes);
      for (const [innerName, bytes] of jvmResult.innerClasses) {
        const innerPath = pathResolve(classDir, innerName + '.class');
        mkdirSync(dirname(innerPath), { recursive: true });
        writeFileSync(innerPath, bytes);
      }
      const depsPath = pathResolve(classDir, jvmResult.className + '.class.deps');
      mkdirSync(dirname(depsPath), { recursive: true });
      writeFileSync(depsPath, dependencyPaths.join('\n') + '\n');
    }

    cache.set(filePath, {
      program,
      jvmResult,
      dependencyPaths,
      className,
      exports: tc.exports,
      exportedTypeAliases: tc.exportedTypeAliases,
      exportedTypeVisibility: tc.exportedTypeVisibility,
    });
    visited.delete(filePath);
    onCompilingFile?.(filePath, Math.round(performance.now() - compileStart));
    return {
      ok: true,
      program,
      jvmResult,
      dependencyPaths,
      className,
      exports: tc.exports,
      exportedTypeAliases: tc.exportedTypeAliases,
      exportedTypeVisibility: tc.exportedTypeVisibility,
    };
  }

  const out = compileOne(absPath);
  if (!out.ok) return out;

  const classDir = getClassOutputDir ? getClassOutputDir(absPath) : '';
  return {
    ok: true,
    classDir,
    mainClass: out.className,
    dependencyPaths: out.dependencyPaths,
  };
}
