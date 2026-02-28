/**
 * Kestrel compiler — parse, typecheck, emit .kbc bytecode.
 */
import { tokenize } from './lexer/index.js';
import { parse, ParseError } from './parser/index.js';
import { typecheck } from './typecheck/index.js';
import { codegen } from './codegen/codegen.js';
import { writeKbc, writeMinimalKbc } from './bytecode/write.js';
import type { Diagnostic } from './diagnostics/types.js';
import { CODES, locationFileOnly } from './diagnostics/types.js';

export interface CompileOptions {
  /** Source file path for diagnostics (spec 10). Default `<source>` for compile(source). */
  sourceFile?: string;
}

export function compile(source: string, compileOptions?: CompileOptions): { ok: true; ast: import('./parser/index.js').Program } | { ok: false; diagnostics: Diagnostic[] } {
  const sourceFile = compileOptions?.sourceFile ?? '<source>';
  try {
    const tokens = tokenize(source);
    const ast = parse(tokens);
    const tc = typecheck(ast, { sourceFile });
    if (!tc.ok) return { ok: false, diagnostics: tc.diagnostics };
    return { ok: true, ast };
  } catch (e) {
    if (e instanceof ParseError) {
      return {
        ok: false,
        diagnostics: [{
          severity: 'error',
          code: CODES.parse.unexpected_token,
          message: e.message,
          location: { file: sourceFile, line: e.line, column: e.column, offset: e.offset },
        }],
      };
    }
    const err = e as Error & { offset?: number; line?: number; column?: number };
    return {
      ok: false,
      diagnostics: [{
        severity: 'error',
        code: CODES.type.check,
        message: err.message,
        location: err.line != null && err.column != null
          ? { file: sourceFile, line: err.line, column: err.column }
          : locationFileOnly(sourceFile),
      }],
    };
  }
}

/** Emit .kbc from typed AST (codegen + full sections). */
export function emitKbc(ast: import('./parser/index.js').Program): Uint8Array {
  const { stringTable, constantPool, code, functionTable, importSpecifierIndices, shapes, adts, nGlobals } = codegen(ast);
  return writeKbc(stringTable, constantPool, code, functionTable, importSpecifierIndices, [], shapes, adts, nGlobals ?? 0);
}

export { tokenize } from './lexer/index.js';
export { parse, ParseError } from './parser/index.js';
export type { Program } from './parser/index.js';
