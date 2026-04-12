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

let compileFnPromise: Promise<CompileFn> | undefined;
let helperModulesPromise: Promise<{
  tokenize: TokenizeFn;
  parse: ParseFn;
  typecheck: TypecheckFn;
  findNodeAtOffset: FindNodeAtOffsetFn;
  getInferredType: GetInferredTypeFn;
  printType: PrintTypeFn;
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

    const [parser, typecheck, ast, types, root] = await Promise.all([
      import(parserModule),
      import(typecheckModule),
      import(astModule),
      import(typesModule),
      import(rootModule),
    ]);

    return {
      tokenize: root.tokenize as TokenizeFn,
      parse: parser.parse as ParseFn,
      typecheck: typecheck.typecheck as TypecheckFn,
      findNodeAtOffset: ast.findNodeAtOffset as FindNodeAtOffsetFn,
      getInferredType: typecheck.getInferredType as GetInferredTypeFn,
      printType: types.printType as PrintTypeFn,
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

export async function hoverDocAtOffset(source: string, offset: number): Promise<string | null> {
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
  line: number;
  column: number;
  endLine: number;
  endColumn: number;
}

export interface WorkspaceIndex {
  decls: WorkspaceDecl[];
  declsByName: Map<string, WorkspaceDecl[]>;
  exportedNames: string[];
  sourcesByUri: Map<string, string>;
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
    out.push({
      name,
      kind,
      exported,
      uri,
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

  for (const [uri, source] of sourcesByUri) {
    const fileDecls = scanTopLevelDecls(source, uri);
    for (const decl of fileDecls) {
      decls.push(decl);
      const arr = declsByName.get(decl.name) ?? [];
      arr.push(decl);
      declsByName.set(decl.name, arr);
    }
  }

  const exportedNames = [...new Set(decls.filter((d) => d.exported).map((d) => d.name))].sort();
  return { decls, declsByName, exportedNames, sourcesByUri };
}
