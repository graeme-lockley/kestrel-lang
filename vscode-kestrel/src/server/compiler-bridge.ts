import * as path from 'node:path';
import { pathToFileURL } from 'node:url';

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
    const compilerEntry = path.resolve(__dirname, '../../../../compiler/dist/index.js');
    const moduleUrl = pathToFileURL(compilerEntry).href;
    const mod = (await import(moduleUrl)) as { compile: CompileFn };
    if (typeof mod.compile !== 'function') {
      throw new Error('Failed to load compile() from compiler/dist/index.js');
    }
    return mod.compile;
  })();

  return compileFnPromise;
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
    const parserModule = pathToFileURL(path.resolve(__dirname, '../../../../compiler/dist/parser/index.js')).href;
    const typecheckModule = pathToFileURL(path.resolve(__dirname, '../../../../compiler/dist/typecheck/index.js')).href;
    const astModule = pathToFileURL(path.resolve(__dirname, '../../../../compiler/dist/ast/index.js')).href;
    const typesModule = pathToFileURL(path.resolve(__dirname, '../../../../compiler/dist/types/index.js')).href;
    const rootModule = pathToFileURL(path.resolve(__dirname, '../../../../compiler/dist/index.js')).href;

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
