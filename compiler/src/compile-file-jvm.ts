/**
 * Multi-module JVM compilation: resolve imports, emit .class files per module.
 * Uses jvmCodegen and writes .class + inner classes.
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync, utimesSync, unlinkSync } from 'fs';
import { createHash } from 'node:crypto';
import { resolve as pathResolve, dirname } from 'path';
import { tokenize } from './lexer/index.js';
import { parse } from './parser/index.js';
import { typecheck, type TypecheckOptions, type DependencyExportSnapshot } from './typecheck/check.js';
import { distinctSpecifiersInSourceOrder, spanForSpecifier } from './module-specifiers.js';
import { jvmCodegen, type JvmCodegenResult } from './jvm-codegen/index.js';
import { resolveSpecifier } from './resolve.js';
import { isMavenSpecifier, resolveMavenSpecifiers, type MavenResolvedDependency } from './maven.js';
import type { Program, ImportDecl, Expr, TopLevelStmt, TopLevelDecl, BlockExpr } from './ast/nodes.js';
import type { FunDecl, ExternFunDecl, TypeDecl, ExternTypeDecl, ExternImportDecl, Param, Type } from './ast/nodes.js';
import { readClassMetadata, generateStubs, renderExternKs } from './jvm-metadata/index.js';
import { getInferredType } from './typecheck/check.js';
import type { InternalType } from './types/internal.js';
import type { Diagnostic } from './diagnostics/types.js';
import { CODES, locationFromSpan, locationFileOnly } from './diagnostics/types.js';
import type { Span } from './lexer/types.js';
import { uniqueDependencyPaths } from './dependency-paths.js';
import { buildKtiV4, writeKtiFile, readKtiFile, deserializeExports, extractCodegenMeta, type KtiCodegenMeta } from './kti.js';

export interface CompileFileJvmOptions {
  projectRoot?: string;
  stdlibDir?: string;
  onCompilingFile?: (absolutePath: string, durationMs: number) => void;
  stalePaths?: Set<string>;
  /** Return class output directory for a source path. Writes <classDir>/<ClassName>.class and inner classes. */
  getClassOutputDir?: (sourcePath: string) => string;
  /** Root directory for the URL import cache (spec 07 §7). Defaults to ~/.kestrel/cache/. */
  urlCacheRoot?: string;
  /** Allow http:// (non-TLS) URL imports. Defaults to false. */
  allowHttp?: boolean;
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

// ---------------------------------------------------------------------------
// extern import expansion
// ---------------------------------------------------------------------------

function makeJavaTypeMapper(): { map: (javaType: string) => Type; typeParams: string[] } {
  const typeParams: string[] = [];
  let counter = 0;
  const map = (javaType: string): Type => {
    switch (javaType) {
      case 'void': return { kind: 'PrimType', name: 'Unit' };
      case 'int':
      case 'long':
      case 'short':
      case 'byte':
      case 'char': return { kind: 'PrimType', name: 'Int' };
      case 'float':
      case 'double': return { kind: 'PrimType', name: 'Float' };
      case 'boolean': return { kind: 'PrimType', name: 'Bool' };
      case 'java.lang.String': return { kind: 'PrimType', name: 'String' };
      default: {
        const name = `_T${counter++}`;
        typeParams.push(name);
        return { kind: 'IdentType', name };
      }
    }
  };
  return { map, typeParams };
}

/**
 * Convert an AST Type node to a Kestrel source-level type string.
 * Used for rendering override signatures in sidecar files.
 */
function typeToString(t: Type): string {
  switch (t.kind) {
    case 'PrimType': return t.name;
    case 'IdentType': return t.name;
    case 'QualifiedType': return `${t.namespace}.${t.name}`;
    case 'AppType': return `${t.name}<${t.args.map(typeToString).join(', ')}>`;
    case 'ArrowType': return `(${t.params.map(typeToString).join(', ')}) -> ${typeToString(t.return)}`;
    case 'TupleType': return `(${t.elements.map(typeToString).join(', ')})`;
    case 'UnionType': return `${typeToString(t.left)} | ${typeToString(t.right)}`;
    default: return 'Any';
  }
}

/**
 * ExternTypeDecl + ExternFunDecl nodes.  Returns the updated body, a map of
 * alias → sidecar content (for .extern.ks file emission), and any diagnostics.
 */
function expandExternImports(
  program: Program,
  filePath: string,
  source: string,
  mavenDeps: MavenResolvedDependency[]
): { body: (TopLevelDecl | TopLevelStmt)[]; sidecars: Map<string, string>; diagnostics: Diagnostic[] } {
  const sidecars = new Map<string, string>();
  const diagnostics: Diagnostic[] = [];
  const newBody: (TopLevelDecl | TopLevelStmt)[] = [];

  for (const node of program.body) {
    if (!node || node.kind !== 'ExternImportDecl') {
      newBody.push(node as TopLevelDecl | TopLevelStmt);
      continue;
    }

    const decl = node as ExternImportDecl;
    const { target, alias, overrides, span } = decl;

    // Parse scheme: currently supports 'java:' only; 'maven:' requires a jar
    let className: string;
    let jarPaths: string[] | undefined;

    if (target.startsWith('java:')) {
      className = target.slice('java:'.length).trim();
    } else if (target.startsWith('maven:')) {
      // Find the resolved jar path from mavenDeps matching this artifact
      // 'maven:groupId:artifactId:version' — extract groupId:artifactId pattern without version
      const parts = target.slice('maven:'.length).split(':');
      const ga = parts.slice(0, 2).join(':');
      const jarDep = mavenDeps.find((d) => d.ga === ga);
      if (!jarDep) {
        diagnostics.push(diag(filePath, CODES.resolve.module_not_found,
          `extern import: maven artifact '${ga}' not found; add an import "${target}" side-effect import first`,
          span, source));
        continue;
      }
      // Check that the version in the extern import target matches the resolved version.
      // parts[2] may include the '#className' fragment, so strip it first.
      const rawVersionPart = parts.length >= 3 ? parts[2] : undefined;
      const requestedVersion = rawVersionPart ? rawVersionPart.split('#')[0] : undefined;
      if (requestedVersion !== undefined && requestedVersion !== jarDep.version) {
        diagnostics.push(diag(filePath, CODES.resolve.module_not_found,
          `extern import: version mismatch for '${ga}': extern import requests version '${requestedVersion}' but the resolved dependency uses version '${jarDep.version}'. Fix: align the extern import version with the import declaration.`,
          span, source));
        continue;
      }
      // maven: extern import target must supply the class name after a '#' separator
      // e.g. "maven:org.apache.commons:commons-lang3:3.20.0#org.apache.commons.lang3.StringUtils"
      const hash = target.lastIndexOf('#');
      if (hash < 0) {
        diagnostics.push(diag(filePath, CODES.resolve.module_not_found,
          `extern import: maven target must include class name after '#', e.g. "maven:groupId:artifactId:version#com.example.Class"`,
          span, source));
        continue;
      }
      className = target.slice(hash + 1).trim();
      jarPaths = [jarDep.jarPath];
    } else {
      diagnostics.push(diag(filePath, CODES.resolve.module_not_found,
        `extern import: unsupported scheme in '${target}'; expected 'java:' or 'maven:'`,
        span, source));
      continue;
    }

    // Read class metadata via javap
    let meta;
    try {
      meta = readClassMetadata(className, jarPaths);
    } catch (err) {
      diagnostics.push(diag(filePath, CODES.resolve.module_not_found,
        `extern import: ${err instanceof Error ? err.message : String(err)}`,
        span, source));
      continue;
    }

    // Build override map: kestrelName/methodName → { params, returnType }
    // Overrides use the same form as hand-written extern fun (receiver is first param for instance methods).
    const overrideMap = new Map<string, { params: Param[]; returnType: Type }>();
    for (const ov of overrides) {
      overrideMap.set(ov.name, { params: ov.params, returnType: ov.returnType });
    }

    // Generate stubs (string-based, for sidecar)
    // Build stringOverrideMap by converting AST overrides to the string form expected by generateStubs.
    // For instance methods, drop the first param (the receiver) since generateStubs adds it automatically.
    const stringOverrideMap = new Map<string, { params: Array<{ name: string; type: string }>; returnType: string }>();
    for (const [overrideName, ov] of overrideMap.entries()) {
      // Look up the method in meta to determine if it's an instance method
      const method = meta.methods.find(
        (m) => m.jvmMethodName === overrideName ||
          (m.isConstructor && `new${alias}` === overrideName)
      );
      const isInstance = method ? (!method.isStatic && !method.isConstructor) : false;
      // Drop the receiver (first param) for instance methods — generateStubs adds it automatically
      const paramsForSidecar = isInstance ? ov.params.slice(1) : ov.params;
      stringOverrideMap.set(overrideName, {
        params: paramsForSidecar.map((p) => ({ name: p.name, type: p.type ? typeToString(p.type) : 'Any' })),
        returnType: typeToString(ov.returnType),
      });
    }
    const stubs = generateStubs(meta, alias, stringOverrideMap);
    const sidecarContent = renderExternKs(meta, alias, stubs);
    sidecars.set(alias, sidecarContent);

    // Emit ExternTypeDecl for the alias
    const externTypeDecl: ExternTypeDecl = {
      kind: 'ExternTypeDecl',
      visibility: 'local',
      name: alias,
      jvmClass: className,
    };
    newBody.push(externTypeDecl);

    // Emit ExternFunDecl for each stub method
    // Sort constructors by param count ascending so the no-arg constructor (or smallest) gets
    // the base name `new${alias}` rather than a suffixed variant.
    const sortedMethods = [...meta.methods].sort((a, b) => {
      if (a.isConstructor && b.isConstructor) return a.javaParamTypes.length - b.javaParamTypes.length;
      return 0;
    });

    // Track Kestrel-level name occurrences (constructors map to `new${alias}`, not `<init>`)
    const occurrences = new Map<string, number>();

    for (const m of sortedMethods) {
      const baseKestrel = m.isConstructor ? `new${alias}` : m.jvmMethodName;
      const idx = (occurrences.get(baseKestrel) ?? 0) + 1;
      occurrences.set(baseKestrel, idx);
      const kestrelName = idx > 1 ? `${baseKestrel}_${idx}` : baseKestrel;

      // jvm("...") descriptor — include ':ReturnType' suffix for primitive-returning methods
      const primitiveReturnTypes = new Set(['boolean', 'byte', 'char', 'short', 'int', 'long', 'float', 'double']);
      const retSuffix = (!m.isConstructor && primitiveReturnTypes.has(m.javaReturnType)) ? `:${m.javaReturnType}` : '';
      const jvmDescriptor = `${className}#${m.jvmMethodName}(${m.javaParamTypes.join(',')})${retSuffix}`;

      let params: Param[];
      let returnType: Type;
      let typeParams: string[] | undefined;

      // Check for override by kestrelName; fall back to raw JVM method name only for
      // the first (non-suffixed) occurrence to avoid applying a single-overload override
      // to all variants of an overloaded Java method.
      const override = overrideMap.get(kestrelName) ?? (idx === 1 ? overrideMap.get(m.jvmMethodName) : undefined);
      if (override) {
        params = override.params;
        returnType = override.returnType;
      } else {
        // Auto-generate: for instance methods, first param is the receiver
        const mapper = makeJavaTypeMapper();
        const generatedParams: Param[] = m.javaParamTypes.map((t, i) => ({
          kind: 'Param' as const,
          name: `p${i}`,
          type: mapper.map(t),
        }));

        if (!m.isStatic && !m.isConstructor) {
          const receiverParam: Param = {
            kind: 'Param',
            name: 'instance',
            type: { kind: 'IdentType', name: alias },
          };
          params = [receiverParam, ...generatedParams];
        } else {
          params = generatedParams;
        }

        returnType = m.isConstructor
          ? { kind: 'IdentType', name: alias }
          : mapper.map(m.javaReturnType);
        typeParams = mapper.typeParams.length > 0 ? mapper.typeParams : undefined;
      }

      const externFunDecl: ExternFunDecl = {
        kind: 'ExternFunDecl',
        exported: false,
        name: kestrelName,
        typeParams,
        params,
        returnType,
        jvmDescriptor,
      };
      newBody.push(externFunDecl);
    }
  }

  return { body: newBody, sidecars, diagnostics };
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
  const urlCacheRoot = options?.urlCacheRoot;
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
      mavenDeps: MavenResolvedDependency[];
      sourceHash: string;
      codegenMeta?: KtiCodegenMeta;
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
    mavenDeps: MavenResolvedDependency[];
    sourceHash: string;
    codegenMeta?: KtiCodegenMeta;
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
    const sourceHash = createHash('sha256').update(source, 'utf8').digest('hex');

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

    const resolveOpts = { fromFile: filePath, projectRoot, stdlibDir, cacheRoot: urlCacheRoot };
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

    // Freshness check: if a valid .kti exists for this file and all dep/source
    // hashes match, short-circuit typecheck + codegen and load from .kti.
    if (getClassOutputDir && !(stalePaths?.has(filePath))) {
      const classDir = getClassOutputDir(filePath);
      const cn = classNameForPath(filePath);
      const ktiPath = pathResolve(classDir, cn + '.kti');
      const kti = readKtiFile(ktiPath);
      if (kti && kti.sourceHash === sourceHash) {
        let depHashesMatch = true;
        for (const dr of depResults) {
          if (kti.depHashes[dr.path] !== cache.get(dr.path)?.sourceHash) {
            depHashesMatch = false;
            break;
          }
        }
        if (depHashesMatch) {
          const deserialized = deserializeExports(kti);
          const depPaths = depResults.flatMap((d) => [d.path, ...d.dependencyPaths]);
          const dependencyPathsU = uniqueDependencyPaths([filePath, ...depPaths]);
          const entry = {
            program: { kind: 'Program', imports: [], topLevelDecls: [], body: [] } as unknown as Program,
            jvmResult: { className: cn, classBytes: new Uint8Array(), innerClasses: new Map<string, Uint8Array>() } as unknown as JvmCodegenResult,
            dependencyPaths: dependencyPathsU,
            className: cn,
            ...deserialized,
            mavenDeps: [] as MavenResolvedDependency[],
            sourceHash,
            codegenMeta: kti.codegenMeta,
          };
          cache.set(filePath, entry);
          visited.delete(filePath);
          return { ok: true, ...entry };
        }
      }
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

    // Expand extern import declarations into concrete extern type + extern fun nodes
    // before typecheck sees the program.
    let externImportSidecars = new Map<string, string>();
    {
      const expansion = expandExternImports(program, filePath, source, mavenDeps);
      if (expansion.diagnostics.length > 0) {
        return { ok: false, diagnostics: expansion.diagnostics };
      }
      program = { ...program, body: expansion.body };
      externImportSidecars = expansion.sidecars;
    }

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
      const depEntry = cache.get(dep.path);
      const depMeta = depEntry?.codegenMeta;
      const depProg = depEntry?.program;
      importClasses.set(dep.spec, dep.className);
      for (const imp of program.imports) {
        if (imp.kind === 'NamedImport' && imp.spec === dep.spec) {
          for (const s of imp.specs) {
            if (dep.exportSet.has(s.external)) {
              importedNameToClass.set(s.local, dep.className);
              importedNameToOriginal.set(s.local, s.external);
              // Arity and async: prefer codegenMeta, fall back to program walk
              const arity = depMeta?.funArities[s.external] ?? (depProg ? getFunArity(depProg, s.external) : undefined);
              if (arity !== undefined) importedFunArities.set(s.local, arity);
              const isAsync = depMeta
                ? depMeta.asyncFunNames.includes(s.external)
                : (depProg ? isAsyncFun(depProg, s.external) : false);
              if (isAsync) importedAsyncFunNames.add(s.local);
              // Val/Var: prefer codegenMeta
              const isVV = depMeta
                ? depMeta.valOrVarNames.includes(s.external)
                : (depProg ? isValOrVar(depProg, s.external) : false);
              if (isVV) importedValVarToClass.set(s.local, dep.className);
              const isV = depMeta
                ? depMeta.varNames.includes(s.external)
                : (depProg ? isVar(depProg, s.external) : false);
              if (isV) importedVarNames.add(s.local);
              // Exception / ADT constructors: prefer codegenMeta
              if (depMeta) {
                for (const exc of depMeta.exceptionDecls) {
                  if (exc.name === s.external) {
                    importedAdtClasses.set(s.local, { className: dep.className + '$' + s.external, arity: exc.arity });
                  }
                }
                for (const adt of depMeta.adtConstructors) {
                  for (const ctor of adt.constructors) {
                    if (ctor.name === s.external) {
                      importedAdtClasses.set(s.local, { className: dep.className + '$' + adt.typeName + '$' + ctor.name, arity: ctor.params });
                    }
                  }
                }
              } else if (depProg) {
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
          // Build ADT constructor → inner class map and var fields: prefer codegenMeta
          if (depMeta) {
            const funArities = new Map<string, number>(Object.entries(depMeta.funArities));
            const asyncFunNames = new Set<string>(depMeta.asyncFunNames);
            const adtCtors = new Map<string, string>();
            for (const adt of depMeta.adtConstructors) {
              const base = dep.className + '$' + adt.typeName;
              for (const ctor of adt.constructors) {
                adtCtors.set(ctor.name, base + '$' + ctor.name);
              }
            }
            const varFields = new Set<string>(depMeta.varNames);
            if (funArities.size > 0) namespaceFunArities.set(imp.name, funArities);
            if (asyncFunNames.size > 0) namespaceAsyncFunNames.set(imp.name, asyncFunNames);
            if (adtCtors.size > 0) namespaceAdtConstructors.set(imp.name, adtCtors);
            if (varFields.size > 0) namespaceVarFields.set(imp.name, varFields);
          } else if (depProg) {
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

      // Emit .extern.ks sidecar files for each extern import declaration
      for (const [alias, content] of externImportSidecars) {
        const sidecarPath = pathResolve(classDir, alias + '.extern.ks');
        writeFileSync(sidecarPath, content);
      }

      // Write .kti v4 types file alongside the .class output
      const depSourceHashes = new Map<string, string>();
      for (const dr of depResults) {
        const depEntry = cache.get(dr.path);
        if (depEntry) depSourceHashes.set(dr.path, depEntry.sourceHash);
      }
      const ktiV4 = buildKtiV4({
        program,
        source,
        depPaths: depResults.map((dr) => dr.path),
        depSourceHashes,
        exports: tc.exports,
        exportedTypeAliases: tc.exportedTypeAliases,
        exportedConstructors: tc.exportedConstructors,
        exportedTypeVisibility: tc.exportedTypeVisibility ?? new Map(),
      });
      const ktiPath = pathResolve(classDir, jvmResult.className + '.kti');
      writeKtiFile(ktiPath, ktiV4);
    }

    visited.delete(filePath);
    onCompilingFile?.(filePath, Math.round(performance.now() - compileStart));
    const codegenMeta = extractCodegenMeta(program, tc.exports, tc.exportedTypeAliases, tc.exportedTypeVisibility ?? new Map());
    cache.set(filePath, {
      program,
      jvmResult,
      dependencyPaths: dependencyPathsUnique,
      className,
      exports: tc.exports,
      exportedTypeAliases: tc.exportedTypeAliases,
      exportedConstructors: tc.exportedConstructors,
      exportedTypeVisibility: tc.exportedTypeVisibility,
      mavenDeps,
      sourceHash,
      codegenMeta,
    });
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
      mavenDeps,
      sourceHash,
      codegenMeta,
    };
  }

  const out = compileOne(absPath);
  if (!out.ok) return out;

  // Check for Maven version conflicts across all compiled modules
  const gaVersionMap = new Map<string, { version: string; filePath: string }>();
  const conflictDiags: Diagnostic[] = [];
  for (const [fp, cached] of cache.entries()) {
    for (const dep of cached.mavenDeps) {
      const existing = gaVersionMap.get(dep.ga);
      if (existing) {
        if (existing.version !== dep.version) {
          conflictDiags.push({
            severity: 'error',
            code: CODES.resolve.module_not_found,
            message: `Maven version conflict for '${dep.ga}': '${fp}' requires version ${dep.version} but '${existing.filePath}' requires version ${existing.version}. Fix: align both imports to the same version.`,
            location: locationFileOnly(fp),
          });
        }
      } else {
        gaVersionMap.set(dep.ga, { version: dep.version, filePath: fp });
      }
    }
  }
  if (conflictDiags.length > 0) return { ok: false, diagnostics: conflictDiags };

  const classDir = getClassOutputDir ? getClassOutputDir(absPath) : '';
  return {
    ok: true,
    classDir,
    mainClass: out.className,
    dependencyPaths: out.dependencyPaths,
  };
}
