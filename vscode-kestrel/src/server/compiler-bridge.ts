import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import type { CompilerDiagnostic } from './document-manager';

export interface CompileResult {
  ast: unknown | null;
  diagnostics: CompilerDiagnostic[];
}

type CompileFn = (source: string, options?: { sourceFile?: string }) =>
  | { ok: true; ast: unknown }
  | { ok: false; diagnostics: CompilerDiagnostic[] };

type TokenizeFn = (source: string) => unknown[];
type ParseFn = (tokens: unknown[]) => unknown;
type TypecheckFn = (program: unknown, options?: { sourceFile?: string; sourceContent?: string }) => unknown;
type FindNodeAtOffsetFn = (program: unknown, offset: number) => unknown;
type GetInferredTypeFn = (node: unknown) => unknown;
type PrintTypeFn = (t: unknown) => string;
type ResolveSpecifierFn = (
  spec: string,
  options: { fromFile: string; projectRoot?: string; stdlibDir?: string; cacheRoot?: string },
) => { ok: true; path: string } | { ok: false; error: string };

let compileFnPromise: Promise<CompileFn> | undefined;
let helperModulesPromise: Promise<{
  tokenize: TokenizeFn;
  parse: ParseFn;
  typecheck: TypecheckFn;
  findNodeAtOffset: FindNodeAtOffsetFn;
  getInferredType: GetInferredTypeFn;
  printType: PrintTypeFn;
  resolveSpecifier: ResolveSpecifierFn;
}> | undefined;

async function loadCompileFn(): Promise<CompileFn> {
  if (compileFnPromise != null) {
    return compileFnPromise;
  }

  compileFnPromise = (async () => {
    const compilerEntry = path.join(resolveCompilerDistSrcDir(), 'index.js');
    const moduleUrl = pathToFileURL(compilerEntry).href;
    const mod = (await import(moduleUrl)) as { compile: CompileFn };
    if (typeof mod.compile !== 'function') {
      throw new Error('Failed to load compile() from compiler/dist/index.js');
    }
    return mod.compile;
  })();

  return compileFnPromise;
}

function resolveCompilerDistSrcDir(): string {
  const candidates = [
    path.resolve(__dirname, '../../compiler/dist/src'),
    path.resolve(__dirname, '../../../../compiler/dist/src'),
    path.resolve(__dirname, '../../../compiler/dist/src'),
    path.resolve(process.cwd(), 'compiler/dist/src'),
    path.resolve(process.cwd(), '../compiler/dist/src'),
    path.resolve(process.cwd(), '../../compiler/dist/src'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(path.join(c, 'index.js'))) {
      return c;
    }
  }
  throw new Error('Unable to locate compiler/dist/src directory from vscode-kestrel server context');
}

export async function compileSource(source: string, sourceFile: string): Promise<CompileResult> {
  const compile = await loadCompileFn();
  const result = compile(source, { sourceFile });
  const diagnostics = result.ok ? [] : result.diagnostics;

  const { tokenize, parse, typecheck } = await loadHelperModules();
  const tokens = tokenize(source);
  const parsed = parse(tokens) as { ok?: boolean };
  if ('ok' in parsed && parsed.ok === false) {
    return { ast: null, diagnostics };
  }

  const ast = parsed as unknown;
  typecheck(ast, { sourceFile, sourceContent: source });
  return { ast, diagnostics };
}

async function loadHelperModules(): Promise<{
  tokenize: TokenizeFn;
  parse: ParseFn;
  typecheck: TypecheckFn;
  findNodeAtOffset: FindNodeAtOffsetFn;
  getInferredType: GetInferredTypeFn;
  printType: PrintTypeFn;
  resolveSpecifier: ResolveSpecifierFn;
}> {
  if (helperModulesPromise != null) {
    return helperModulesPromise;
  }

  helperModulesPromise = (async () => {
    const compilerDist = resolveCompilerDistSrcDir();
    const parserModule = pathToFileURL(path.join(compilerDist, 'parser', 'index.js')).href;
    const typecheckModule = pathToFileURL(path.join(compilerDist, 'typecheck', 'index.js')).href;
    const astModule = pathToFileURL(path.join(compilerDist, 'ast', 'index.js')).href;
    const typesModule = pathToFileURL(path.join(compilerDist, 'types', 'index.js')).href;
    const rootModule = pathToFileURL(path.join(compilerDist, 'index.js')).href;
    const resolveModule = pathToFileURL(path.join(compilerDist, 'resolve.js')).href;

    const [parser, typecheck, ast, types, root, resolve] = await Promise.all([
      import(parserModule),
      import(typecheckModule),
      import(astModule),
      import(typesModule),
      import(rootModule),
      import(resolveModule),
    ]);

    return {
      tokenize: root.tokenize as TokenizeFn,
      parse: parser.parse as ParseFn,
      typecheck: typecheck.typecheck as TypecheckFn,
      findNodeAtOffset: ast.findNodeAtOffset as FindNodeAtOffsetFn,
      getInferredType: typecheck.getInferredType as GetInferredTypeFn,
      printType: types.printType as PrintTypeFn,
      resolveSpecifier: resolve.resolveSpecifier as ResolveSpecifierFn,
    };
  })();

  return helperModulesPromise;
}

export async function hoverTypeAtOffset(ast: unknown | null, offset: number): Promise<string | null> {
  if (ast == null) {
    return null;
  }

  const { findNodeAtOffset, getInferredType, printType } = await loadHelperModules();
  const node = findNodeAtOffset(ast, offset);
  if (node == null) {
    return null;
  }
  const inferred = getInferredType(node);
  if (inferred == null) {
    return null;
  }
  return printType(inferred);
}

export async function inferredTypeText(node: unknown): Promise<string | null> {
  const { getInferredType, printType } = await loadHelperModules();
  const inferred = getInferredType(node);
  if (inferred == null) {
    return null;
  }
  return printType(inferred);
}

export async function tokenizeSource(source: string): Promise<unknown[]> {
  const { tokenize } = await loadHelperModules();
  return tokenize(source);
}

function isIdentChar(ch: string): boolean {
  return /[A-Za-z0-9_]/.test(ch);
}

function identifierAtOffset(source: string, offset: number): string | null {
  if (source.length === 0) {
    return null;
  }
  const clamped = Math.max(0, Math.min(offset, source.length - 1));
  let left = clamped;
  let right = clamped;

  if (!isIdentChar(source[clamped] ?? '') && clamped > 0 && isIdentChar(source[clamped - 1] ?? '')) {
    left = clamped - 1;
    right = clamped - 1;
  }

  while (left > 0 && isIdentChar(source[left - 1] ?? '')) {
    left--;
  }
  while (right + 1 < source.length && isIdentChar(source[right + 1] ?? '')) {
    right++;
  }

  const ident = source.slice(left, right + 1);
  return ident.length > 0 && /^[A-Za-z_][A-Za-z0-9_]*$/.test(ident) ? ident : null;
}

function collectDocByDeclName(source: string): Map<string, string> {
  const out = new Map<string, string>();
  const lines = source.split(/\r?\n/);
  let pendingDoc: string[] = [];

  for (const rawLine of lines) {
    const line = rawLine.trim();
    const docMatch = line.match(/^\/\/\/\s?(.*)$/);
    if (docMatch != null) {
      pendingDoc.push(docMatch[1] ?? '');
      continue;
    }

    const declMatch = line.match(/^(?:export\s+)?(?:async\s+)?(?:fun|val|var|type|exception)\s+([A-Za-z_][A-Za-z0-9_]*)\b/);
    if (declMatch != null) {
      const name = declMatch[1];
      if (pendingDoc.length > 0) {
        out.set(name, pendingDoc.join('\n').trim());
      }
      pendingDoc = [];
      continue;
    }

    if (line === '' || line.startsWith('//')) {
      continue;
    }

    pendingDoc = [];
  }

  return out;
}

export async function hoverDocAtOffset(
  source: string,
  offset: number,
  uri?: string,
  workspaceIndex?: WorkspaceIndex,
): Promise<string | null> {
  if (uri != null && workspaceIndex != null) {
    const resolved = resolveWorkspaceSymbolAtOffset(uri, source, offset, workspaceIndex);
    if (resolved?.declaration != null) {
      const module = workspaceIndex.modulesByUri.get(resolved.declaration.uri);
      const doc = module?.docCommentsByName.get(resolved.declaration.name);
      if (doc != null && doc.length > 0) {
        return doc;
      }
    }
  }

  const ident = identifierAtOffset(source, offset);
  if (ident == null) {
    return null;
  }

  const docsByName = collectDocByDeclName(source);
  const doc = docsByName.get(ident);
  return doc == null || doc.length === 0 ? null : doc;
}

export interface WorkspaceDecl {
  name: string;
  kind: 'fun' | 'val' | 'var' | 'type' | 'exception';
  exported: boolean;
  uri: string;
  bindingKey: string;
  start: number;
  end: number;
  line: number;
  column: number;
  endLine: number;
  endColumn: number;
}

export interface SymbolOccurrence {
  bindingKey: string;
  name: string;
  uri: string;
  start: number;
  end: number;
  role: 'declaration' | 'reference' | 'import';
}

export interface WorkspaceBinding {
  key: string;
  name: string;
  uri: string;
  start: number;
  end: number;
  kind: 'top-level' | 'local' | 'import' | 'namespace';
  exported: boolean;
}

interface WorkspaceImportBinding {
  kind: 'named' | 'namespace';
  local: string;
  external: string;
  spec: string;
  start: number;
  end: number;
  targetUri?: string;
  bindingKey?: string;
}

export interface WorkspaceModule {
  ast: unknown | null;
  docCommentsByName: Map<string, string>;
  namedImports: Map<string, WorkspaceImportBinding>;
  namespaceImports: Map<string, WorkspaceImportBinding>;
  occurrences: SymbolOccurrence[];
}

export interface ResolvedWorkspaceSymbol {
  key: string;
  name: string;
  declaration: WorkspaceBinding | null;
  occurrences: SymbolOccurrence[];
}

export interface WorkspaceIndex {
  decls: WorkspaceDecl[];
  declsByName: Map<string, WorkspaceDecl[]>;
  declsByUri: Map<string, WorkspaceDecl[]>;
  exportedNames: string[];
  sourcesByUri: Map<string, string>;
  modulesByUri: Map<string, WorkspaceModule>;
  bindingDeclarations: Map<string, WorkspaceBinding>;
  bindingOccurrences: Map<string, SymbolOccurrence[]>;
}

interface SpanLike {
  start?: number;
  end?: number;
  line?: number;
  column?: number;
}

interface BindingState {
  key: string;
  name: string;
  kind: WorkspaceBinding['kind'];
  exported: boolean;
  namespaceTargetUri?: string;
}

function makeBindingKey(uri: string, start: number, end: number, name: string): string {
  return `${uri}:${start}:${end}:${name}`;
}

function offsetFromLineColumn(source: string, line: number, column: number): number {
  if (line <= 1) {
    return Math.max(0, column - 1);
  }

  let currentLine = 1;
  let offset = 0;
  while (offset < source.length && currentLine < line) {
    if (source.charCodeAt(offset) === 10) {
      currentLine++;
    }
    offset++;
  }
  return Math.max(0, Math.min(source.length, offset + column - 1));
}

function hasSpan(value: unknown): value is { span: SpanLike } {
  return value != null && typeof value === 'object' && 'span' in (value as object);
}

function spanStart(value: unknown): number | null {
  if (!hasSpan(value)) {
    return null;
  }
  return typeof value.span.start === 'number' ? value.span.start : null;
}

function spanEnd(value: unknown): number | null {
  if (!hasSpan(value)) {
    return null;
  }
  return typeof value.span.end === 'number' ? value.span.end : null;
}

function findIdentifierOffsetInRange(source: string, name: string, start: number, end: number, from = start): number | null {
  let cursor = Math.max(start, from);
  while (cursor <= end) {
    const found = source.indexOf(name, cursor);
    if (found < 0 || found + name.length > end) {
      return null;
    }
    const before = found === 0 ? '' : source[found - 1] ?? '';
    const after = source[found + name.length] ?? '';
    if (!/[A-Za-z0-9_]/.test(before) && !/[A-Za-z0-9_]/.test(after)) {
      return found;
    }
    cursor = found + name.length;
  }
  return null;
}

function pushOccurrence(
  occurrences: SymbolOccurrence[],
  bindingKey: string,
  name: string,
  uri: string,
  start: number,
  end: number,
  role: SymbolOccurrence['role'],
): void {
  occurrences.push({ bindingKey, name, uri, start, end, role });
}

function createSyntheticBinding(name: string, uri: string, counter: number): BindingState {
  return {
    key: `local:${uri}:${counter}:${name}`,
    name,
    kind: 'local',
    exported: false,
  };
}

function collectImportBindings(
  tokens: Array<{ kind?: string; value?: string; span?: SpanLike }>,
  sourceUri: string,
  rootDir: string,
  declsByUri: Map<string, WorkspaceDecl[]>,
  resolveSpecifier: ResolveSpecifierFn,
): {
  namedImports: Map<string, WorkspaceImportBinding>;
  namespaceImports: Map<string, WorkspaceImportBinding>;
} {
  const namedImports = new Map<string, WorkspaceImportBinding>();
  const namespaceImports = new Map<string, WorkspaceImportBinding>();
  const fromFile = fileURLToPath(sourceUri);
  let index = 0;

  while (index < tokens.length) {
    const token = tokens[index];
    if (token?.kind === 'newline') {
      index++;
      continue;
    }
    if (token?.kind !== 'keyword' || token.value !== 'import') {
      break;
    }

    index++;
    if (tokens[index]?.kind === 'op' && tokens[index]?.value === '*') {
      index++;
      if (tokens[index]?.kind === 'keyword' && tokens[index]?.value === 'as') {
        index++;
      }
      const nameToken = tokens[index];
      index++;
      if (tokens[index]?.kind === 'keyword' && tokens[index]?.value === 'from') {
        index++;
      }
      const specToken = tokens[index];
      index++;
      if (nameToken?.kind === 'ident' && typeof nameToken.value === 'string' && specToken?.kind === 'string' && typeof specToken.value === 'string' && nameToken.span != null) {
        const resolved = resolveSpecifier(specToken.value, {
          fromFile,
          projectRoot: rootDir,
          stdlibDir: path.join(rootDir, 'stdlib'),
        });
        namespaceImports.set(nameToken.value, {
          kind: 'namespace',
          local: nameToken.value,
          external: nameToken.value,
          spec: specToken.value,
          start: nameToken.span.start ?? 0,
          end: nameToken.span.end ?? nameToken.span.start ?? 0,
          targetUri: resolved.ok ? pathToFileURL(resolved.path).href : undefined,
        });
      }
      continue;
    }

    if (tokens[index]?.kind === 'string') {
      index++;
      continue;
    }

    if (tokens[index]?.kind !== 'lbrace') {
      continue;
    }
    index++;

    const specs: WorkspaceImportBinding[] = [];
    while (index < tokens.length && tokens[index]?.kind !== 'rbrace') {
      const externalToken = tokens[index];
      if (externalToken?.kind !== 'ident' || typeof externalToken.value !== 'string' || externalToken.span == null) {
        index++;
        continue;
      }
      index++;

      let localToken = externalToken;
      if (tokens[index]?.kind === 'keyword' && tokens[index]?.value === 'as') {
        index++;
        if (tokens[index]?.kind === 'ident' && typeof tokens[index]?.value === 'string' && tokens[index]?.span != null) {
          localToken = tokens[index] as { kind?: string; value?: string; span?: SpanLike };
          index++;
        }
      }

      const localSpan = localToken.span ?? externalToken.span;

      specs.push({
        kind: 'named',
        local: localToken.value ?? externalToken.value,
        external: externalToken.value,
        spec: '',
        start: localSpan?.start ?? 0,
        end: localSpan?.end ?? localSpan?.start ?? 0,
      });

      if (tokens[index]?.kind === 'comma') {
        index++;
      }
    }

    if (tokens[index]?.kind === 'rbrace') {
      index++;
    }
    if (tokens[index]?.kind === 'keyword' && tokens[index]?.value === 'from') {
      index++;
    }
    const specToken = tokens[index];
    index++;
    if (specToken?.kind !== 'string' || typeof specToken.value !== 'string') {
      continue;
    }

    const resolved = resolveSpecifier(specToken.value, {
      fromFile,
      projectRoot: rootDir,
      stdlibDir: path.join(rootDir, 'stdlib'),
    });
    const targetUri = resolved.ok ? pathToFileURL(resolved.path).href : undefined;
    for (const spec of specs) {
      const targetDecl = targetUri == null
        ? undefined
        : (declsByUri.get(targetUri) ?? []).find((decl) => decl.exported && decl.name === spec.external);
      namedImports.set(spec.local, {
        ...spec,
        spec: specToken.value,
        targetUri,
        bindingKey: targetDecl?.bindingKey,
      });
    }
  }

  return { namedImports, namespaceImports };
}

function lookupBinding(scopes: Array<Map<string, BindingState>>, name: string): BindingState | null {
  for (let index = scopes.length - 1; index >= 0; index--) {
    const binding = scopes[index]?.get(name);
    if (binding != null) {
      return binding;
    }
  }
  return null;
}

function collectPatternBindings(pattern: unknown, uri: string, scope: Map<string, BindingState>, localCounter: { value: number }): void {
  if (pattern == null || typeof pattern !== 'object') {
    return;
  }
  const node = pattern as { kind?: string; [key: string]: unknown };
  switch (node.kind) {
    case 'VarPattern':
      if (typeof node.name === 'string') {
        scope.set(node.name, createSyntheticBinding(node.name, uri, localCounter.value++));
      }
      return;
    case 'ListPattern':
      for (const element of Array.isArray(node.elements) ? node.elements : []) {
        collectPatternBindings(element, uri, scope, localCounter);
      }
      if (typeof node.rest === 'string') {
        scope.set(node.rest, createSyntheticBinding(node.rest, uri, localCounter.value++));
      }
      return;
    case 'ConsPattern':
      collectPatternBindings(node.head, uri, scope, localCounter);
      collectPatternBindings(node.tail, uri, scope, localCounter);
      return;
    case 'TuplePattern':
      for (const element of Array.isArray(node.elements) ? node.elements : []) {
        collectPatternBindings(element, uri, scope, localCounter);
      }
      return;
    case 'ConstructorPattern':
      for (const field of Array.isArray(node.fields) ? node.fields : []) {
        collectPatternBindings((field as { pattern?: unknown }).pattern, uri, scope, localCounter);
      }
      return;
    default:
      return;
  }
}

function walkExprOccurrences(
  expr: unknown,
  source: string,
  uri: string,
  scopes: Array<Map<string, BindingState>>,
  workspaceIndex: WorkspaceIndex,
  occurrences: SymbolOccurrence[],
  localCounter: { value: number },
  searchCursor: { value: number },
  searchEnd?: number,
): void {
  if (expr == null || typeof expr !== 'object') {
    return;
  }

  const node = expr as { kind?: string; [key: string]: unknown };
  switch (node.kind) {
    case 'IdentExpr': {
      const name = typeof node.name === 'string' ? node.name : null;
      let start = spanStart(node);
      let end = spanEnd(node);
      if (name != null && (start == null || end == null)) {
        const fallbackStart = findIdentifierOffsetInRange(source, name, searchCursor.value, searchEnd ?? source.length);
        if (fallbackStart != null) {
          start = fallbackStart;
          end = fallbackStart + name.length;
        }
      }
      if (name != null && start != null && end != null) {
        const binding = lookupBinding(scopes, name);
        if (binding != null) {
          pushOccurrence(occurrences, binding.key, name, uri, start, end, 'reference');
          searchCursor.value = end;
        }
      }
      return;
    }
    case 'FieldExpr': {
      const objectExpr = node.object;
      const nodeEnd = spanEnd(node) ?? searchEnd;
      walkExprOccurrences(objectExpr, source, uri, scopes, workspaceIndex, occurrences, localCounter, searchCursor, nodeEnd);
      if (objectExpr != null && typeof objectExpr === 'object' && (objectExpr as { kind?: string }).kind === 'IdentExpr') {
        const objectName = (objectExpr as { name?: string }).name;
        if (typeof objectName === 'string') {
          const binding = lookupBinding(scopes, objectName);
          const targetUri = binding?.namespaceTargetUri;
          const fieldName = typeof node.field === 'string' ? node.field : null;
          if (targetUri != null && fieldName != null) {
            const targetDecl = (workspaceIndex.declsByUri.get(targetUri) ?? []).find((decl) => decl.exported && decl.name === fieldName);
            const start = spanStart(node);
            const end = spanEnd(node);
            if (targetDecl != null && start != null && end != null) {
              const fieldStart = findIdentifierOffsetInRange(source, fieldName, start, end);
              if (fieldStart != null) {
                pushOccurrence(occurrences, targetDecl.bindingKey, fieldName, uri, fieldStart, fieldStart + fieldName.length, 'reference');
                searchCursor.value = fieldStart + fieldName.length;
              }
            }
          }
        }
      }
      return;
    }
    case 'LambdaExpr': {
      const lambdaScope = new Map<string, BindingState>();
      for (const param of Array.isArray(node.params) ? node.params : []) {
        if (param != null && typeof param === 'object' && typeof (param as { name?: string }).name === 'string') {
          lambdaScope.set((param as { name: string }).name, createSyntheticBinding((param as { name: string }).name, uri, localCounter.value++));
        }
      }
      walkExprOccurrences(node.body, source, uri, [...scopes, lambdaScope], workspaceIndex, occurrences, localCounter, searchCursor, spanEnd(node) ?? searchEnd);
      return;
    }
    case 'BlockExpr': {
      const blockScope = new Map<string, BindingState>();
      const nestedScopes = [...scopes, blockScope];
      for (const stmt of Array.isArray(node.stmts) ? node.stmts : []) {
        if (stmt == null || typeof stmt !== 'object') {
          continue;
        }
        const stmtNode = stmt as { kind?: string; name?: string; value?: unknown; body?: unknown; expr?: unknown; target?: unknown; params?: unknown[] };
        if (stmtNode.kind === 'ValStmt' || stmtNode.kind === 'VarStmt') {
          walkExprOccurrences(stmtNode.value, source, uri, nestedScopes, workspaceIndex, occurrences, localCounter, searchCursor, searchEnd);
          if (typeof stmtNode.name === 'string') {
            blockScope.set(stmtNode.name, createSyntheticBinding(stmtNode.name, uri, localCounter.value++));
          }
          continue;
        }
        if (stmtNode.kind === 'FunStmt') {
          if (typeof stmtNode.name === 'string') {
            blockScope.set(stmtNode.name, createSyntheticBinding(stmtNode.name, uri, localCounter.value++));
          }
          const fnScope = new Map<string, BindingState>();
          for (const param of Array.isArray(stmtNode.params) ? stmtNode.params : []) {
            if (param != null && typeof param === 'object' && typeof (param as { name?: string }).name === 'string') {
              fnScope.set((param as { name: string }).name, createSyntheticBinding((param as { name: string }).name, uri, localCounter.value++));
            }
          }
          walkExprOccurrences(stmtNode.body, source, uri, [...nestedScopes, fnScope], workspaceIndex, occurrences, localCounter, searchCursor, searchEnd);
          continue;
        }
        if (stmtNode.kind === 'AssignStmt') {
          walkExprOccurrences(stmtNode.target, source, uri, nestedScopes, workspaceIndex, occurrences, localCounter, searchCursor, searchEnd);
          walkExprOccurrences(stmtNode.value, source, uri, nestedScopes, workspaceIndex, occurrences, localCounter, searchCursor, searchEnd);
          continue;
        }
        if (stmtNode.kind === 'ExprStmt') {
          walkExprOccurrences(stmtNode.expr, source, uri, nestedScopes, workspaceIndex, occurrences, localCounter, searchCursor, searchEnd);
        }
      }
      walkExprOccurrences(node.result, source, uri, nestedScopes, workspaceIndex, occurrences, localCounter, searchCursor, spanEnd(node) ?? searchEnd);
      return;
    }
    case 'MatchExpr':
      walkExprOccurrences(node.scrutinee, source, uri, scopes, workspaceIndex, occurrences, localCounter, searchCursor, spanEnd(node) ?? searchEnd);
      for (const matchCase of Array.isArray(node.cases) ? node.cases : []) {
        const caseScope = new Map<string, BindingState>();
        collectPatternBindings((matchCase as { pattern?: unknown }).pattern, uri, caseScope, localCounter);
        walkExprOccurrences((matchCase as { body?: unknown }).body, source, uri, [...scopes, caseScope], workspaceIndex, occurrences, localCounter, searchCursor, spanEnd(matchCase) ?? searchEnd);
      }
      return;
    case 'TryExpr':
      walkExprOccurrences(node.body, source, uri, scopes, workspaceIndex, occurrences, localCounter, searchCursor, spanEnd(node) ?? searchEnd);
      for (const matchCase of Array.isArray(node.cases) ? node.cases : []) {
        const caseScope = new Map<string, BindingState>();
        if (typeof node.catchVar === 'string' && node.catchVar.length > 0) {
          caseScope.set(node.catchVar, createSyntheticBinding(node.catchVar, uri, localCounter.value++));
        }
        collectPatternBindings((matchCase as { pattern?: unknown }).pattern, uri, caseScope, localCounter);
        walkExprOccurrences((matchCase as { body?: unknown }).body, source, uri, [...scopes, caseScope], workspaceIndex, occurrences, localCounter, searchCursor, spanEnd(matchCase) ?? searchEnd);
      }
      return;
    default:
      const nodeEnd = spanEnd(node) ?? searchEnd;
      for (const [key, value] of Object.entries(node)) {
        if (key === 'span') {
          continue;
        }
        if (Array.isArray(value)) {
          for (const item of value) {
            walkExprOccurrences(item, source, uri, scopes, workspaceIndex, occurrences, localCounter, searchCursor, nodeEnd);
          }
          continue;
        }
        if (value != null && typeof value === 'object') {
          walkExprOccurrences(value, source, uri, scopes, workspaceIndex, occurrences, localCounter, searchCursor, nodeEnd);
        }
      }
  }
}

function buildModuleOccurrences(uri: string, source: string, module: WorkspaceModule, workspaceIndex: WorkspaceIndex): SymbolOccurrence[] {
  const occurrences: SymbolOccurrence[] = [];
  const topLevelScope = new Map<string, BindingState>();
  const scopes = [topLevelScope];
  const localCounter = { value: 0 };
  const searchCursor = { value: 0 };

  for (const decl of workspaceIndex.declsByUri.get(uri) ?? []) {
    topLevelScope.set(decl.name, { key: decl.bindingKey, name: decl.name, kind: 'top-level', exported: decl.exported });
    pushOccurrence(occurrences, decl.bindingKey, decl.name, uri, decl.start, decl.end, 'declaration');
    searchCursor.value = Math.max(searchCursor.value, decl.end);
  }

  for (const binding of module.namedImports.values()) {
    const key = binding.bindingKey ?? makeBindingKey(uri, binding.start, binding.end, binding.local);
    if (binding.bindingKey == null && !workspaceIndex.bindingDeclarations.has(key)) {
      workspaceIndex.bindingDeclarations.set(key, {
        key,
        name: binding.local,
        uri,
        start: binding.start,
        end: binding.end,
        kind: 'import',
        exported: false,
      });
    }
    topLevelScope.set(binding.local, { key, name: binding.local, kind: binding.bindingKey == null ? 'import' : 'top-level', exported: false });
    pushOccurrence(occurrences, key, binding.local, uri, binding.start, binding.end, 'import');
    searchCursor.value = Math.max(searchCursor.value, binding.end);
  }

  for (const binding of module.namespaceImports.values()) {
    const key = makeBindingKey(uri, binding.start, binding.end, binding.local);
    if (!workspaceIndex.bindingDeclarations.has(key)) {
      workspaceIndex.bindingDeclarations.set(key, {
        key,
        name: binding.local,
        uri,
        start: binding.start,
        end: binding.end,
        kind: 'namespace',
        exported: false,
      });
    }
    topLevelScope.set(binding.local, {
      key,
      name: binding.local,
      kind: 'namespace',
      exported: false,
      namespaceTargetUri: binding.targetUri,
    });
    pushOccurrence(occurrences, key, binding.local, uri, binding.start, binding.end, 'import');
    searchCursor.value = Math.max(searchCursor.value, binding.end);
  }

  const program = module.ast as { body?: unknown[] } | null;
  for (const item of program?.body ?? []) {
    if (item == null || typeof item !== 'object') {
      continue;
    }
    const node = item as { kind?: string; value?: unknown; body?: unknown; params?: unknown[]; name?: string; expr?: unknown; target?: unknown };
    switch (node.kind) {
      case 'ValDecl':
      case 'VarDecl':
        walkExprOccurrences(node.value, source, uri, scopes, workspaceIndex, occurrences, localCounter, searchCursor);
        break;
      case 'FunDecl': {
        const fnScope = new Map<string, BindingState>();
        for (const param of Array.isArray(node.params) ? node.params : []) {
          if (param != null && typeof param === 'object' && typeof (param as { name?: string }).name === 'string') {
            fnScope.set((param as { name: string }).name, createSyntheticBinding((param as { name: string }).name, uri, localCounter.value++));
          }
        }
        walkExprOccurrences(node.body, source, uri, [...scopes, fnScope], workspaceIndex, occurrences, localCounter, searchCursor);
        break;
      }
      case 'ExprStmt':
        walkExprOccurrences(node.expr, source, uri, scopes, workspaceIndex, occurrences, localCounter, searchCursor);
        break;
      case 'AssignStmt':
        walkExprOccurrences(node.target, source, uri, scopes, workspaceIndex, occurrences, localCounter, searchCursor);
        walkExprOccurrences(node.value, source, uri, scopes, workspaceIndex, occurrences, localCounter, searchCursor);
        break;
      case 'ValStmt':
      case 'VarStmt':
        walkExprOccurrences(node.value, source, uri, scopes, workspaceIndex, occurrences, localCounter, searchCursor);
        if (typeof node.name === 'string') {
          topLevelScope.set(node.name, createSyntheticBinding(node.name, uri, localCounter.value++));
        }
        break;
      default:
        break;
    }
  }

  return occurrences;
}

function walkKsFiles(rootDir: string): string[] {
  const out: string[] = [];
  const stack = [rootDir];
  const skip = new Set(['.git', 'node_modules', 'dist', 'out', 'build']);

  while (stack.length > 0) {
    const dir = stack.pop();
    if (dir == null) {
      continue;
    }

    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }

    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (!skip.has(entry.name)) {
          stack.push(fullPath);
        }
        continue;
      }
      if (entry.isFile() && fullPath.endsWith('.ks')) {
        out.push(fullPath);
      }
    }
  }

  return out;
}

function scanTopLevelDecls(source: string, uri: string): WorkspaceDecl[] {
  const out: WorkspaceDecl[] = [];
  const lines = source.split(/\r?\n/);
  const declRe = /^(\s*)(export\s+)?(?:async\s+)?(fun|val|var|type|exception)\s+([A-Za-z_][A-Za-z0-9_]*)\b/;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i] ?? '';
    const match = line.match(declRe);
    if (match == null) {
      continue;
    }
    const exported = (match[2] ?? '').trim() === 'export';
    const kind = match[3] as WorkspaceDecl['kind'];
    const name = match[4] ?? '';
    if (name.length === 0) {
      continue;
    }

    const nameIndex = line.indexOf(name);
    if (nameIndex < 0) {
      continue;
    }
    const column = nameIndex + 1;
    const start = offsetFromLineColumn(source, i + 1, column);
    const end = start + name.length;
    out.push({
      name,
      kind,
      exported,
      uri,
      bindingKey: makeBindingKey(uri, start, end, name),
      start,
      end,
      line: i + 1,
      column,
      endLine: i + 1,
      endColumn: column + name.length,
    });
  }

  return out;
}

function workspaceRootToFsPath(workspaceRoot: string): string {
  if (workspaceRoot.startsWith('file://')) {
    return fileURLToPath(workspaceRoot);
  }
  return workspaceRoot;
}

export async function compileWorkspace(
  workspaceRoot: string,
  openDocuments?: Map<string, string>,
): Promise<WorkspaceIndex> {
  const rootDir = workspaceRootToFsPath(workspaceRoot);
  const filePaths = walkKsFiles(rootDir);
  const sourcesByUri = new Map<string, string>();

  for (const filePath of filePaths) {
    const uri = pathToFileURL(filePath).href;
    const openSource = openDocuments?.get(uri);
    if (openSource != null) {
      sourcesByUri.set(uri, openSource);
      continue;
    }
    try {
      const source = fs.readFileSync(filePath, 'utf8');
      sourcesByUri.set(uri, source);
    } catch {
      continue;
    }
  }

  for (const [uri, source] of openDocuments ?? []) {
    if (!sourcesByUri.has(uri) && uri.endsWith('.ks')) {
      sourcesByUri.set(uri, source);
    }
  }

  const decls: WorkspaceDecl[] = [];
  const declsByName = new Map<string, WorkspaceDecl[]>();
  const declsByUri = new Map<string, WorkspaceDecl[]>();

  for (const [uri, source] of sourcesByUri) {
    const fileDecls = scanTopLevelDecls(source, uri);
    declsByUri.set(uri, fileDecls);
    for (const decl of fileDecls) {
      decls.push(decl);
      const arr = declsByName.get(decl.name) ?? [];
      arr.push(decl);
      declsByName.set(decl.name, arr);
    }
  }

  const bindingDeclarations = new Map<string, WorkspaceBinding>();
  for (const decl of decls) {
    bindingDeclarations.set(decl.bindingKey, {
      key: decl.bindingKey,
      name: decl.name,
      uri: decl.uri,
      start: decl.start,
      end: decl.end,
      kind: 'top-level',
      exported: decl.exported,
    });
  }

  const { tokenize, parse, resolveSpecifier } = await loadHelperModules();
  const modulesByUri = new Map<string, WorkspaceModule>();

  for (const [uri, source] of sourcesByUri) {
    const tokens = tokenize(source) as Array<{ kind?: string; value?: string; span?: SpanLike }>;
    const parsed = parse(tokens) as { ok?: boolean };
    const ast = 'ok' in parsed && parsed.ok === false ? null : parsed;
    const imports = collectImportBindings(tokens, uri, rootDir, declsByUri, resolveSpecifier);
    modulesByUri.set(uri, {
      ast,
      docCommentsByName: collectDocByDeclName(source),
      namedImports: imports.namedImports,
      namespaceImports: imports.namespaceImports,
      occurrences: [],
    });
  }

  const exportedNames = [...new Set(decls.filter((d) => d.exported).map((d) => d.name))].sort();
  const workspaceIndex: WorkspaceIndex = {
    decls,
    declsByName,
    declsByUri,
    exportedNames,
    sourcesByUri,
    modulesByUri,
    bindingDeclarations,
    bindingOccurrences: new Map<string, SymbolOccurrence[]>(),
  };

  for (const [uri, module] of modulesByUri) {
    const source = sourcesByUri.get(uri) ?? '';
    module.occurrences = buildModuleOccurrences(uri, source, module, workspaceIndex);
    for (const occurrence of module.occurrences) {
      const arr = workspaceIndex.bindingOccurrences.get(occurrence.bindingKey) ?? [];
      arr.push(occurrence);
      workspaceIndex.bindingOccurrences.set(occurrence.bindingKey, arr);
    }
  }

  return workspaceIndex;
}

export function resolveWorkspaceSymbolAtOffset(
  uri: string,
  source: string,
  offset: number,
  workspaceIndex: WorkspaceIndex,
): ResolvedWorkspaceSymbol | null {
  const module = workspaceIndex.modulesByUri.get(uri);
  if (module == null) {
    return null;
  }

  const occurrence = [...module.occurrences]
    .filter((entry) => entry.start <= offset && offset <= entry.end)
    .sort((left, right) => (left.end - left.start) - (right.end - right.start))[0];

  if (occurrence == null) {
    const ident = identifierAtOffset(source, offset);
    if (ident == null) {
      return null;
    }
    const localImport = module.namedImports.get(ident);
    if (localImport?.bindingKey != null) {
      return {
        key: localImport.bindingKey,
        name: ident,
        declaration: workspaceIndex.bindingDeclarations.get(localImport.bindingKey) ?? null,
        occurrences: workspaceIndex.bindingOccurrences.get(localImport.bindingKey) ?? [],
      };
    }
    return null;
  }

  return {
    key: occurrence.bindingKey,
    name: occurrence.name,
    declaration: workspaceIndex.bindingDeclarations.get(occurrence.bindingKey) ?? null,
    occurrences: workspaceIndex.bindingOccurrences.get(occurrence.bindingKey) ?? [],
  };
}
