import * as path from 'node:path';
import { pathToFileURL } from 'node:url';

import type { CompilerDiagnostic } from './document-manager';

export interface CompileResult {
  diagnostics: CompilerDiagnostic[];
}

type CompileFn = (source: string, options?: { sourceFile?: string }) =>
  | { ok: true; ast: unknown }
  | { ok: false; diagnostics: CompilerDiagnostic[] };

let compileFnPromise: Promise<CompileFn> | undefined;

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
  if (result.ok) {
    return { diagnostics: [] };
  }
  return { diagnostics: result.diagnostics };
}
