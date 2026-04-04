/**
 * Multi-module JVM compilation: resolve imports, emit .class files per module.
 * Uses jvmCodegen and writes .class + inner classes.
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync, utimesSync, unlinkSync } from 'fs';
import { resolve as pathResolve, dirname } from 'path';
import { tokenize } from './lexer/index.js';
import { parse } from './parser/index.js';
import { typecheck, type TypecheckOptions, type DependencyExportSnapshot } from './typecheck/check.js';
import { distinctSpecifiersInSourceOrder, spanForSpecifier } from './module-specifiers.js';
import { jvmCodegen, type JvmCodegenResult } from './jvm-codegen/index.js';
import { resolveSpecifier } from './resolve.js';
import { isMavenSpecifier, resolveMavenSpecifiers, type MavenResolvedDependency } from './maven.js';
import type { Program, ImportDecl, Expr, TopLevelStmt, TopLevelDecl, BlockExpr } from './ast/nodes.js';
import type { FunDecl, ExternFunDecl, TypeDecl } from './ast/nodes.js';
import { getInferredType } from './typecheck/check.js';
import type { InternalType } from './types/internal.js';
import type { Diagnostic } from './diagnostics/types.js';
import { CODES, locationFromSpan, locationFileOnly } from './diagnostics/types.js';
import type { Span } from './lexer/types.js';
import { uniqueDependencyPaths } from './dependency-paths.js';

export interface CompileFileJvmOptions {
  projectRoot?: string;
  stdlibDir?: string;
  onCompilingFile?: (absolutePath: string, durationMs: number) => void;
  stalePaths?: Set<string>;
  /** Return class output directory for a source path. Writes <classDir>/<ClassName>.class and inner classes. */
  getClassOutputDir?: (sourcePath: string) => string;
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

function collectJvmNamespaceConstructorDiags(
  program: Program,
  nsCtorByNs: Map<string, Set<string>>,
  file: string,
  source: string
): Diagnostic[] {
  const diags: Diagnostic[] = [];
  const msgCall = (ns: string, f: string) =>
    `Namespace-qualified ADT constructor ${ns}.${f} is not supported; use a wrapper function in the dependency.`;

  function visit(e: Expr, isCallCallee: boolean): void {
    switch (e.kind) {
      case 'CallExpr': {
        if (e.callee.kind === 'FieldExpr' && e.callee.object.kind === 'IdentExpr') {
          const ns = e.callee.object.name;
          const f = e.callee.field;
          if (nsCtorByNs.get(ns)?.has(f)) {
            diags.push(diag(file, CODES.compile.jvm_namespace_constructor, msgCall(ns, f), e.callee.span, source));
          }
        }
        visit(e.callee, true);
        for (const a of e.args) visit(a, false);
        return;
      }
      case 'FieldExpr': {
        visit(e.object, false);
        if (!isCallCallee && e.object.kind === 'IdentExpr') {
          const ns = e.object.name;
          const f = e.field;
          if (nsCtorByNs.get(ns)?.has(f)) {
            const t = getInferredType(e);
            if (t?.kind === 'app') {
              diags.push(diag(file, CODES.compile.jvm_namespace_constructor, msgCall(ns, f), e.span, source));
            }
          }
        }
        return;
      }
      case 'IfExpr':
        visit(e.cond, false);
        visit(e.then, false);
        if (e.else) visit(e.else, false);
        return;
      case 'IsExpr':
        visit(e.expr, false);
        return;
      case 'WhileExpr':
        visit(e.cond, false);
        for (const st of e.body.stmts) visitBlockStmt(st);
        visit(e.body.result, false);
        return;
      case 'BlockExpr':
        for (const st of e.stmts) visitBlockStmt(st);
        visit(e.result, false);
        return;
      case 'MatchExpr':
        visit(e.scrutinee, false);
        for (const c of e.cases) visit(c.body, false);
        return;
      case 'TryExpr':
        visit(e.body, false);
        for (const c of e.cases) visit(c.body, false);
        return;
      case 'LambdaExpr':
        visit(e.body, false);
        return;
      case 'PipeExpr':
        visit(e.left, false);
        visit(e.right, false);
        return;
      case 'TemplateExpr':
        for (const p of e.parts) if (p.type === 'interp') visit(p.expr, false);
        return;
      case 'BinaryExpr':
        visit(e.left, false);
        visit(e.right, false);
        return;
      case 'UnaryExpr':
        visit(e.operand, false);
        return;
      case 'ConsExpr':
        visit(e.head, false);
        visit(e.tail, false);
        return;
      case 'TupleExpr':
        for (const el of e.elements) visit(el, false);
        return;
      case 'ListExpr':
        for (const el of e.elements) {
          if (typeof el === 'object' && el !== null && 'spread' in el) {
            visit((el as { expr: Expr }).expr, false);
          } else {
            visit(el as Expr, false);
          }
        }
        return;
      case 'RecordExpr':
        if (e.spread) visit(e.spread, false);
        for (const f of e.fields) visit(f.value, false);
        return;
      case 'ThrowExpr':
        visit(e.value, false);
        return;
      case 'AwaitExpr':
        visit(e.value, false);
        return;
      default:
        return;
    }
  }

  function visitBlockStmt(s: BlockExpr['stmts'][number]): void {
    switch (s.kind) {
      case 'ExprStmt':
        visit(s.expr, false);
        return;
      case 'ValStmt':
      case 'VarStmt':
        visit(s.value, false);
        return;
      case 'AssignStmt':
        visit(s.target, false);
        visit(s.value, false);
        return;
      case 'FunStmt':
        visit(s.body, false);
        return;
      case 'BreakStmt':
      case 'ContinueStmt':
        return;
    }
  }

  function visitStmt(s: TopLevelStmt): void {
    if (!s) return;
    switch (s.kind) {
      case 'ExprStmt':
        visit(s.expr, false);
        return;
      default:
        return;
    }
  }

  for (const node of program.body) {
    if (!node) continue;
    const n = node as TopLevelDecl | TopLevelStmt;
    if (n.kind === 'FunDecl') {
      visit(n.body, false);
    } else if (n.kind === 'ValDecl' || n.kind === 'VarDecl') {
      visit(n.value, false);
    } else {
      visitStmt(n as TopLevelStmt);
    }
  }
  return diags;
}

/**
 * Derive JVM internal class name from the absolute source path.
 * Example:
 * - /Users/me/proj/mandelbrot.ks -> Users/me/proj/Mandelbrot
 * - /Users/me/my-proj/mandelbrot.ks -> Users/me/my_proj/Mandelbrot
 *
 * Each path segment is sanitized so that only characters valid in a Java
 * identifier remain (letters, digits, underscore); anything else is replaced
 * with '_'.  This prevents Java from rejecting class names that contain
 * hyphens or dots from directory names such as "kestrel-lang".
 *
 * This is intentionally stable regardless of:
 * - whether the file is an entry vs dependency
 * - the current working directory
 */
function classNameForPath(absolutePath: string): string {
  const normalized = pathResolve(absolutePath).replace(/\\/g, '/');
  const rel = normalized.startsWith('/') ? normalized.slice(1) : normalized;
  const withoutExt = rel.endsWith('.ks') ? rel.slice(0, -3) : rel;
  const parts = withoutExt.split('/').map((p: string) => p.replace(/[^a-zA-Z0-9_]/g, '_'));
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

  // Only write a .class file if the content has changed, to avoid bumping
  // the file's mtime when the bytecode is identical. This prevents the
  // staleness-check oscillation where repeated compilations of the same
  // runtime dependency cause dependent files to appear stale on every run.
  function writeClassIfChanged(path: string, bytes: Uint8Array): void {
    if (existsSync(path)) {
      const existing = readFileSync(path);
      if (existing.length === bytes.length && existing.every((b, i) => b === bytes[i])) return;
    }
    writeFileSync(path, bytes);
  }

  /** Write the main class file, always touching its mtime so staleness checks reset after recompile. */
  function writeMainClass(path: string, bytes: Uint8Array): void {
    if (existsSync(path)) {
      const existing = readFileSync(path);
      if (existing.length === bytes.length && existing.every((b, i) => b === bytes[i])) {
        const now = new Date();
        utimesSync(path, now, now);
        return;
      }
    }
    writeFileSync(path, bytes);
  }

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
      exportedConstructors: Map<string, InternalType>;
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
    exportedConstructors: Map<string, InternalType>;
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

    for (const imp of program.imports) {
      if (isMavenSpecifier(imp.spec) && imp.kind !== 'SideEffectImport') {
        return {
          ok: false,
          diagnostics: [diag(filePath, CODES.resolve.module_not_found, `maven imports are classpath declarations only; use side-effect form: import \"${imp.spec}\"`, imp.span, source)],
        };
      }
    }

    const resolveOpts = { fromFile: filePath, projectRoot, stdlibDir };
    const specs = distinctSpecifiersInSourceOrder(program);
    const mavenSpecs = specs.filter((s) => isMavenSpecifier(s));
    const sourceSpecs = specs.filter((s) => !isMavenSpecifier(s));
    let mavenDeps: MavenResolvedDependency[] = [];
    try {
      mavenDeps = resolveMavenSpecifiers(mavenSpecs);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return {
        ok: false,
        diagnostics: [diag(filePath, CODES.resolve.module_not_found, `maven resolution failed: ${message}`)],
      };
    }
    const resolved = new Map<string, string>();
    for (const spec of sourceSpecs) {
      const r = resolveSpecifier(spec, resolveOpts);
      if (!r.ok) {
        const span = spanForSpecifier(program, spec);
        return { ok: false, diagnostics: [diag(filePath, CODES.resolve.module_not_found, r.error, span, source)] };
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

    for (const spec of sourceSpecs) {
      const depPath = resolved.get(spec)!;
      const depOut = compileOne(depPath);
      if (!depOut.ok) return depOut;
      const depClassName = depOut.className;
      const depExportSet = new Set([
        ...depOut.exports.keys(),
        ...depOut.exportedConstructors.keys(),
      ]);

      for (const imp of program.imports) {
        if (imp.kind !== 'NamedImport' || imp.spec !== spec) continue;
        const requested = getRequestedImports(imp);
        for (const [localName, externalName] of requested) {
          if (!depExportSet.has(externalName)) {
            const impNode = program.imports.find((i) => i.spec === spec);
            return { ok: false, diagnostics: [diag(filePath, CODES.export.not_exported, `Module ${spec} does not export ${externalName}`, (impNode as { span?: Span })?.span, source)] };
          }
          let t = depOut.exports.get(externalName);
          if (t == null) t = depOut.exportedConstructors.get(externalName);
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
        for (const [name, t] of depOut.exportedConstructors) bindings.set(name, t);
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

    const dependencyExportsBySpec = new Map<string, DependencyExportSnapshot>();
    for (const dr of depResults) {
      const ent = cache.get(dr.path);
      if (ent) {
        dependencyExportsBySpec.set(dr.spec, {
          exports: ent.exports,
          exportedTypeAliases: ent.exportedTypeAliases,
          exportedConstructors: ent.exportedConstructors,
          exportedTypeVisibility: ent.exportedTypeVisibility ?? new Map(),
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

    const className = classNameForPath(filePath);

    const importClasses = new Map<string, string>();
    const namespaceClasses = new Map<string, string>();
    const namespaceFunArities = new Map<string, Map<string, number>>();
    const namespaceAsyncFunNames = new Map<string, Set<string>>();
    const importedNameToClass = new Map<string, string>();
    const importedNameToOriginal = new Map<string, string>();
    const importedFunArities = new Map<string, number>();
    const importedAsyncFunNames = new Set<string>();
    const importedValVarToClass = new Map<string, string>();
    const importedVarNames = new Set<string>();
    const namespaceAdtConstructors = new Map<string, Map<string, string>>();
    const namespaceVarFields = new Map<string, Set<string>>();
    const importedAdtClasses = new Map<string, { className: string; arity: number }>();

    function isValOrVar(prog: Program, name: string): boolean {
      for (const node of prog.body) {
        if (!node) continue;
        if ((node.kind === 'ValDecl' || node.kind === 'VarDecl') && node.name === name) return true;
      }
      return false;
    }

    function isVar(prog: Program, name: string): boolean {
      for (const node of prog.body) {
        if (!node) continue;
        if (node.kind === 'VarDecl' && node.name === name) return true;
      }
      return false;
    }

    function getFunArity(prog: Program, name: string): number | undefined {
      for (const node of prog.body) {
        if (!node) continue;
        if (node.kind === 'FunDecl' && node.name === name) {
          return (node as { params: unknown[] }).params.length;
        }
        if (node.kind === 'ExternFunDecl' && node.name === name) {
          return (node as { params: unknown[] }).params.length;
        }
      }
      return undefined;
    }

    function isAsyncFun(prog: Program, name: string): boolean {
      for (const node of prog.body) {
        if (!node) continue;
        if (node.kind === 'FunDecl' && node.name === name) {
          return (node as FunDecl).async;
        }
        if (node.kind === 'ExternFunDecl' && node.name === name) {
          const t = (node as { returnType?: { kind?: string; name?: string } }).returnType;
          return t?.kind === 'AppType' && t?.name === 'Task';
        }
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
              if (depProg) {
                const arity = getFunArity(depProg, s.external);
                if (arity !== undefined) importedFunArities.set(s.local, arity);
                if (isAsyncFun(depProg, s.external)) importedAsyncFunNames.add(s.local);
              }
              if (depProg && isValOrVar(depProg, s.external)) importedValVarToClass.set(s.local, dep.className);
              if (depProg && isVar(depProg, s.external)) importedVarNames.add(s.local);
                // Check if it's an imported exception or ADT constructor (nullary or parametric)
                if (depProg) {
                  for (const node of depProg.body) {
                    if (!node) continue;
                    if (node.kind === 'ExceptionDecl' && node.name === s.external) {
                      const excArity = (node.fields?.length) ?? 0;
                      importedAdtClasses.set(s.local, { className: dep.className + '$' + s.external, arity: excArity });
                    } else if (node.kind === 'TypeDecl') {
                      const t = node as TypeDecl;
                      if (t.body?.kind !== 'ADTBody') continue;
                      for (const c of (t.body as { constructors: Array<{ name: string; params: unknown[] }> }).constructors) {
                        if (c.name === s.external) {
                          importedAdtClasses.set(s.local, { className: dep.className + '$' + t.name + '$' + c.name, arity: c.params.length });
                        }
                      }
                    }
                  }
                }
            }
          }
        }
        if (imp.kind === 'NamespaceImport' && imp.spec === dep.spec) {
          namespaceClasses.set(imp.name, dep.className);
            // Build ADT constructor → inner class map and var fields set for this namespace import
            if (depProg) {
              const funArities = new Map<string, number>();
              const asyncFunNames = new Set<string>();
              const adtCtors = new Map<string, string>();
              const varFields = new Set<string>();
              for (const node of depProg.body) {
                if (!node) continue;
                if (node.kind === 'FunDecl') {
                  const fun = node as FunDecl;
                  funArities.set(fun.name, fun.params.length);
                  if (fun.async) asyncFunNames.add(fun.name);
                } else if (node.kind === 'ExternFunDecl') {
                  const efun = node as ExternFunDecl;
                  funArities.set(efun.name, efun.params.length);
                  const rt = efun.returnType as { kind?: string; name?: string } | undefined;
                  if (rt?.kind === 'AppType' && rt?.name === 'Task') asyncFunNames.add(efun.name);
                } else if (node.kind === 'TypeDecl') {
                  const t = node as TypeDecl;
                  if (t.body?.kind !== 'ADTBody') continue;
                  const base = dep.className + '$' + t.name;
                  for (const c of t.body.constructors) {
                    adtCtors.set(c.name, base + '$' + c.name);
                  }
                } else if (node.kind === 'VarDecl') {
                  varFields.add((node as { name: string }).name);
                }
              }
              if (funArities.size > 0) namespaceFunArities.set(imp.name, funArities);
              if (asyncFunNames.size > 0) namespaceAsyncFunNames.set(imp.name, asyncFunNames);
              if (adtCtors.size > 0) namespaceAdtConstructors.set(imp.name, adtCtors);
              if (varFields.size > 0) namespaceVarFields.set(imp.name, varFields);
            }
        }
      }
    }

    const jvmResult = jvmCodegen(program, {
      sourceFile: filePath,
      className,
      importClasses: importClasses.size > 0 ? importClasses : undefined,
      namespaceClasses: namespaceClasses.size > 0 ? namespaceClasses : undefined,
      namespaceFunArities: namespaceFunArities.size > 0 ? namespaceFunArities : undefined,
      namespaceAsyncFunNames: namespaceAsyncFunNames.size > 0 ? namespaceAsyncFunNames : undefined,
      namespaceAdtConstructors: namespaceAdtConstructors.size > 0 ? namespaceAdtConstructors : undefined,
      namespaceVarFields: namespaceVarFields.size > 0 ? namespaceVarFields : undefined,
      importedNameToClass: importedNameToClass.size > 0 ? importedNameToClass : undefined,
      importedNameToOriginal: importedNameToOriginal.size > 0 ? importedNameToOriginal : undefined,
      importedFunArities: importedFunArities.size > 0 ? importedFunArities : undefined,
      importedAsyncFunNames: importedAsyncFunNames.size > 0 ? importedAsyncFunNames : undefined,
      importedValVarToClass: importedValVarToClass.size > 0 ? importedValVarToClass : undefined,
      importedVarNames: importedVarNames.size > 0 ? importedVarNames : undefined,
      importedAdtClasses: importedAdtClasses.size > 0 ? importedAdtClasses : undefined,
    });

    const runtimeKsPathForDeps = pathResolve(stdlibDir, 'kestrel/runtime.ks');
    if (getClassOutputDir && existsSync(runtimeKsPathForDeps) && filePath !== runtimeKsPathForDeps) {
      const rtOut = compileOne(runtimeKsPathForDeps);
      if (!rtOut.ok) {
        visited.delete(filePath);
        return rtOut;
      }
    }

    const dependencyPaths = [
      filePath,
      ...depResults.flatMap((d) => [d.path, ...d.dependencyPaths]),
      ...mavenDeps.map((d) => d.jarPath),
    ];
    if (getClassOutputDir && existsSync(runtimeKsPathForDeps)) {
      if (!dependencyPaths.includes(runtimeKsPathForDeps)) dependencyPaths.push(runtimeKsPathForDeps);
      const rtClassDir = getClassOutputDir(runtimeKsPathForDeps);
      const rtClassName = cache.get(runtimeKsPathForDeps)?.className;
      if (rtClassName) {
        const rtMarker = pathResolve(rtClassDir, rtClassName + '.class');
        if (!dependencyPaths.includes(rtMarker)) dependencyPaths.push(rtMarker);
      }
    }

    const dependencyPathsUnique = uniqueDependencyPaths(dependencyPaths);

    if (getClassOutputDir) {
      const classDir = getClassOutputDir(filePath);
      mkdirSync(classDir, { recursive: true });
      const mainClassPath = pathResolve(classDir, jvmResult.className + '.class');
      mkdirSync(dirname(mainClassPath), { recursive: true });
      writeMainClass(mainClassPath, jvmResult.classBytes);
      for (const [innerName, bytes] of jvmResult.innerClasses) {
        const innerPath = pathResolve(classDir, innerName + '.class');
        mkdirSync(dirname(innerPath), { recursive: true });
        writeClassIfChanged(innerPath, bytes);
      }
      const depsPath = pathResolve(classDir, jvmResult.className + '.class.deps');
      mkdirSync(dirname(depsPath), { recursive: true });
      writeFileSync(depsPath, dependencyPathsUnique.join('\n') + '\n');

      const kdepsPath = pathResolve(classDir, jvmResult.className + '.kdeps');
      if (mavenDeps.length > 0) {
        const sorted = [...mavenDeps].sort((a, b) => a.ga.localeCompare(b.ga));
        const payload = {
          maven: Object.fromEntries(sorted.map((d) => [d.ga, d.version])),
          jars: Object.fromEntries(sorted.map((d) => [d.ga, d.jarPath])),
          checksums: Object.fromEntries(sorted.map((d) => [d.ga, d.sha1])),
        };
        writeFileSync(kdepsPath, JSON.stringify(payload, null, 2) + '\n');
      } else if (existsSync(kdepsPath)) {
        unlinkSync(kdepsPath);
      }
    }

    cache.set(filePath, {
      program,
      jvmResult,
      dependencyPaths: dependencyPathsUnique,
      className,
      exports: tc.exports,
      exportedTypeAliases: tc.exportedTypeAliases,
      exportedConstructors: tc.exportedConstructors,
      exportedTypeVisibility: tc.exportedTypeVisibility,
    });
    visited.delete(filePath);
    onCompilingFile?.(filePath, Math.round(performance.now() - compileStart));
    return {
      ok: true,
      program,
      jvmResult,
      dependencyPaths: dependencyPathsUnique,
      className,
      exports: tc.exports,
      exportedTypeAliases: tc.exportedTypeAliases,
      exportedConstructors: tc.exportedConstructors,
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
